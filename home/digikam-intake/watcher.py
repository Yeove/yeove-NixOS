#!/usr/bin/env python3
"""
digikam-intake-watcher - NixOS replacement for stamp-source-tray.ps1

Watches the Firefox intake folder for the <media> + <media>.url.txt pairs the
"Save image with source URL" userscript writes. For each complete pair it:

  1. fixes the extension from the file's magic bytes (.bin / mislabelled saves)
  2. stamps the page URL into XMP-photoshop:Source and XMP-dc:Identifier
     (videos, and anything exiftool can't write into, get an .xmp sidecar)
  3. moves the media (+ sidecar) into the library folder on the NAS
  4. deletes the .url.txt - last, so a failed move gets retried later

A pair is processed only once BOTH halves are complete, whichever lands last.
Firefox creates a 0-byte placeholder at the final name, streams into
<name>.part, then renames it over the placeholder - so "non-empty, with no
.part beside it" means done. inotify close_write/moved_to events trigger
processing; a periodic sweep retries anything still waiting (NAS unmounted,
exiftool error) and garbage-collects old leftovers.

Under systemd the log goes to the journal with real priorities:
    journalctl --user -u digikam-intake -f
"""

import argparse
import errno
import os
import re
import select
import shutil
import stat
import subprocess
import time
from pathlib import Path

VIDEO_EXTS = {'.mp4', '.webm', '.mkv'}
EXT_ALIASES = {'.jpeg': '.jpg', '.tiff': '.tif'}

# <media>.url.txt, plus Firefox's collision renames: if "x.jpg" is still in
# the intake when you save it again, you get "x(1).jpg" + "x.jpg.url(1).txt".
COMP_RE = re.compile(r'^(?P<media>.+)\.url\.txt$')
COMP_DUP_RE = re.compile(r'^(?P<base>.+)\.url(?P<sp> ?)\((?P<n>\d+)\)\.txt$')
MEDIA_DUP_RE = re.compile(
    r'^(?P<stem>.+?)(?P<sp> ?)\((?P<n>\d+)\)(?P<ext>\.[A-Za-z0-9]{1,5})?$')

NAS_DOWN = 'Library folder {} not available (NAS mounted?) - holding files in intake'

args = None
_warned = set()


# ---- logging ----------------------------------------------------------------

def log(msg, level='info'):
    if os.environ.get('JOURNAL_STREAM'):           # running under systemd
        prio = {'error': 3, 'warn': 4, 'info': 6}[level]
        print(f'<{prio}>{msg}', flush=True)
    else:
        print(f'{time.strftime("%H:%M:%S")} [{level}] {msg}', flush=True)
    if level == 'error' and args and args.notify and shutil.which('notify-send'):
        subprocess.run(['notify-send', '-a', 'digiKam intake', '-i', 'dialog-error',
                        'digiKam intake', msg], check=False)


def log_once(msg, level='warn'):
    """For conditions the sweep re-detects every few minutes."""
    if msg not in _warned:
        _warned.add(msg)
        log(msg, level)


# ---- file-type sniffing -----------------------------------------------------

def sniff(path):
    try:
        with open(path, 'rb') as f:
            b = f.read(64)
    except OSError:
        return None
    if len(b) < 12:
        return None
    if b[:3] == b'\xff\xd8\xff':
        return '.jpg'
    if b[:4] == b'\x89PNG':
        return '.png'
    if b[:4] == b'GIF8':
        return '.gif'
    if b[:4] == b'RIFF' and b[8:12] == b'WEBP':
        return '.webp'
    if b[:2] == b'BM':
        return '.bmp'
    if b[:4] in (b'II*\x00', b'MM\x00*'):
        return '.tif'
    if b[4:8] == b'ftyp':
        brand = b[8:12]
        if brand in (b'heic', b'heix', b'hevc', b'mif1', b'msf1'):
            return '.heic'
        if brand in (b'avif', b'avis'):
            return '.avif'
        return '.mp4'               # isom, mp41/2, M4V, avc1, qt ...
    if b[:4] == b'\x1aE\xdf\xa3':   # EBML: WebM and Matroska share it
        return '.webm' if b'webm' in b else '.mkv'
    return None


# ---- names and paths --------------------------------------------------------

def swap_ext(p, ext):
    stem, old = os.path.splitext(p.name)
    if not re.fullmatch(r'\.[A-Za-z0-9]{1,5}', old):
        stem = p.name               # no real extension to replace, so append
    return p.with_name(stem + ext)


def sidecar_for(media):
    if args.sidecar_compatible_name:
        return swap_ext(media, '.xmp')                # clip.xmp
    return media.with_name(media.name + '.xmp')       # clip.mp4.xmp (digiKam default)


def unique(p, with_sidecar=False):
    def taken(q):
        return q.exists() or (with_sidecar and sidecar_for(q).exists())
    if not taken(p):
        return p
    stem, ext = os.path.splitext(p.name)
    i = 1
    while taken(p.with_name(f'{stem}_{i}{ext}')):
        i += 1
    return p.with_name(f'{stem}_{i}{ext}')


def media_for(comp):
    """Media path a companion belongs to, or None if it isn't a companion."""
    m = COMP_RE.match(comp.name)
    if m:
        return comp.with_name(m['media'])
    m = COMP_DUP_RE.match(comp.name)
    if m:
        stem, ext = os.path.splitext(m['base'])
        return comp.with_name(f"{stem}{m['sp']}({m['n']}){ext}")
    return None


def companion_for(media):
    c = media.with_name(media.name + '.url.txt')
    if c.exists():
        return c
    m = MEDIA_DUP_RE.match(media.name)
    if m:
        c = media.with_name(f"{m['stem']}{m['ext'] or ''}.url{m['sp']}({m['n']}).txt")
        if c.exists():
            return c
    return None


def complete(p):
    try:
        if p.stat().st_size == 0:
            return False            # Firefox's placeholder, or nothing yet
    except FileNotFoundError:
        return False
    return not p.with_name(p.name + '.part').exists()


# ---- the actual work --------------------------------------------------------

def exiftool(*argv):
    r = subprocess.run(['exiftool', '-q', '-q', *argv], capture_output=True, text=True)
    if r.returncode != 0:
        log(f'exiftool: {(r.stderr or r.stdout).strip()}', 'warn')
    return r.returncode == 0


def write_sidecar(media, tags):
    side = sidecar_for(media)
    if side.exists():
        ok = exiftool('-overwrite_original', *tags, str(side))
    else:
        ok = exiftool('-o', str(side), *tags, str(media))
    return side if ok else None


def move(src, dest):
    try:
        os.rename(src, dest)
        return
    except OSError as e:
        if e.errno != errno.EXDEV:
            raise
    # Different filesystem (local disk -> CIFS): copy under a hidden temp name
    # so digiKam never picks up a half-written file, then rename into place.
    tmp = dest.with_name(f'.{dest.name}.partial')
    try:
        shutil.copyfile(src, tmp)
        try:
            shutil.copystat(src, tmp)
        except OSError:
            pass                    # CIFS often refuses chmod/utime; the bytes are what matter
        os.replace(tmp, dest)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise
    src.unlink()


def process(media, comp):
    if not (complete(media) and complete(comp)):
        return                      # the other half is still downloading

    url = comp.read_text(encoding='utf-8', errors='replace').strip()
    if not url:
        log_once(f'Empty URL in {comp.name}, leaving it', 'warn')
        return

    out = Path(args.output)
    nas_msg = NAS_DOWN.format(out)
    if not out.is_dir():
        log_once(nas_msg, 'error')
        return
    if nas_msg in _warned:
        _warned.discard(nas_msg)
        log(f'Library folder {out} is back')

    real = sniff(media)
    if real is None:
        log_once(f'Unknown format, leaving in intake: {media.name}', 'error')
        return

    cur = media.suffix.lower()
    if EXT_ALIASES.get(cur, cur) != real:
        new = unique(swap_ext(media, real))
        new_comp = new.with_name(new.name + '.url.txt')
        media.rename(new)
        comp.rename(new_comp)       # keep the pair together, or a failed stamp orphans the URL
        log(f'Renamed {media.name} -> {new.name}')
        media, comp = new, new_comp

    tags = (f'-XMP-photoshop:Source={url}', f'-XMP-dc:Identifier={url}')
    sidecar = None
    if real in VIDEO_EXTS:
        # exiftool can write XMP into MP4, but digiKam reads it back unreliably
        sidecar = write_sidecar(media, tags)
        if not sidecar:
            log_once(f'exiftool failed writing a sidecar for {media.name}', 'error')
            return
    elif not exiftool('-overwrite_original', *tags, str(media)):
        sidecar = write_sidecar(media, tags)   # e.g. BMP, which exiftool can't write into
        if not sidecar:
            log_once(f'exiftool failed on {media.name}', 'error')
            return
        log(f'{media.name}: embedded write failed, used a sidecar instead', 'warn')

    try:
        dest = unique(out / media.name, with_sidecar=sidecar is not None)
        move(media, dest)
        if sidecar:
            move(sidecar, sidecar_for(dest))   # must follow the media's FINAL name
    except OSError as e:
        log_once(f'Move to library failed for {media.name}: {e}', 'error')
        return

    comp.unlink(missing_ok=True)
    log(f'Stamped{" (sidecar)" if sidecar else ""} & filed: {dest.name}')


def dispatch(p):
    if p.name.endswith('.part') or p.name.startswith('.'):
        return                      # wait for Firefox's rename to the final name
    try:
        m = media_for(p)
        if m is not None:
            process(m, p)
            return
        c = companion_for(p)
        if c is not None:
            process(p, c)
    except Exception as e:          # never let one bad file kill the watcher
        log(f'Unexpected error on {p.name}: {e!r}', 'error')


def sweep(gc=True):
    intake = Path(args.intake)
    try:
        entries = sorted(intake.iterdir())
    except OSError as e:
        log_once(f'Cannot read intake {intake}: {e}', 'error')
        return

    # 1) retry every pair that's still waiting
    for p in entries:
        if media_for(p) is not None:
            dispatch(p)
    if not gc:
        return

    # 2) garbage-collect old leftovers. Only .txt is ever deleted - media is
    #    your content and is just logged, and sidecars wait for their media.
    cutoff = time.time() - args.gc_age * 60
    for p in entries:
        try:
            st = p.stat()
        except FileNotFoundError:
            continue                # just filed by step 1
        if not stat.S_ISREG(st.st_mode) or st.st_mtime > cutoff:
            continue
        if p.suffix == '.xmp' or p.name.startswith('.'):
            continue
        if p.name.endswith('.txt'):
            m = media_for(p)
            if m is not None and m.exists():
                log_once(f'GC: kept {p.name} - its media is still here, so stamping is failing',
                         'error')
                continue
            try:
                p.unlink()
                log(f'GC: removed stale {p.name}')
            except OSError as e:
                log_once(f'GC: could not remove {p.name} ({e})', 'warn')
        elif companion_for(p) is None:
            log_once(f'GC: media with no source URL left in intake (not deleting): {p.name}')


# ---- main loop --------------------------------------------------------------

def main():
    global args
    ap = argparse.ArgumentParser(
        description='Stamp source URLs into userscript downloads and file them for digiKam.')
    ap.add_argument('--intake', default=str(Path.home() / 'Downloads' / 'Digikam-intake'))
    ap.add_argument('--output', required=True, help='library folder, e.g. on the NAS mount')
    ap.add_argument('--gc-age', type=float, default=30, metavar='MIN',
                    help='age before intake leftovers are cleaned up (default 30)')
    ap.add_argument('--sweep-every', type=float, default=5, metavar='MIN',
                    help='how often to retry waiting pairs and GC (default 5)')
    ap.add_argument('--sidecar-compatible-name', action='store_true',
                    help='write clip.xmp instead of clip.mp4.xmp')
    ap.add_argument('--notify', action='store_true', help='desktop notification on errors')
    ap.add_argument('--once', action='store_true',
                    help='process whatever is waiting, then exit')
    args = ap.parse_args()

    for tool in ['exiftool'] + ([] if args.once else ['inotifywait']):
        if not shutil.which(tool):
            log(f'{tool} not found on PATH', 'error')
            return 1

    intake = Path(args.intake)
    intake.mkdir(parents=True, exist_ok=True)
    # The output folder is deliberately NOT created: if the NAS is unmounted,
    # mkdir would quietly build a fake library on the local disk underneath it.

    if args.once:
        sweep(gc=False)
        return 0

    watcher = subprocess.Popen(
        ['inotifywait', '-m', '-q', '-e', 'close_write,moved_to', '--format', '%f', str(intake)],
        stdout=subprocess.PIPE)
    time.sleep(0.5)                 # let the watch establish before the startup scan
    log(f'Watching {intake} -> {args.output}')
    sweep()

    fd = watcher.stdout.fileno()
    buf = b''
    next_sweep = time.monotonic() + args.sweep_every * 60
    while True:
        ready, _, _ = select.select([fd], [], [], max(0, next_sweep - time.monotonic()))
        if ready:
            chunk = os.read(fd, 65536)
            if not chunk:
                log('inotifywait exited', 'error')
                return 1            # systemd restarts us
            buf += chunk
            *lines, buf = buf.split(b'\n')
            for line in lines:
                if line:
                    dispatch(intake / os.fsdecode(line))
        if time.monotonic() >= next_sweep:
            sweep()
            next_sweep = time.monotonic() + args.sweep_every * 60


if __name__ == '__main__':
    raise SystemExit(main())
