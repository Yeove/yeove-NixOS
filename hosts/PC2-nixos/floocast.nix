# FlooCast: the config app for the FlooGoo FMA120 Bluetooth audio dongle
# plugged into this machine. Upstream has no package, so this wraps the Python
# source from the floocast flake input (github.com/Flairmesh/FlooCast).
#
#   floocast                       # launch from a shell (or the app grid)
#   nix flake update floocast      # pull upstream changes, then nh os switch
#
# Firmware updates (DFU) aren't in the open-source code; use the Windows
# Store build for those. Settings live in ~/.config/FlooCast.
{ pkgs, inputs, ... }:

let
  # requirements.txt is incomplete upstream: sounddevice and numpy are
  # imported by FlooAuxInput.py but not listed. pystray/notify-py from
  # linuxInstall.txt are never imported, so they're left out.
  python = pkgs.python3.withPackages (
    ps: with ps; [
      wxpython
      pyserial
      pillow
      certifi
      urllib3
      sounddevice
      numpy
    ]
  );

  floocast = pkgs.stdenvNoCC.mkDerivation {
    pname = "floocast";
    version = "unstable-${inputs.floocast.shortRev or "local"}";
    src = inputs.floocast;

    nativeBuildInputs = [
      pkgs.makeWrapper
      pkgs.imagemagick
      pkgs.copyDesktopItems
    ];

    installPhase = ''
      runHook preInstall

      # main.py finds its PNGs and locales next to itself (sys.argv[0]),
      # and the .ico by a bare relative path, hence --chdir below.
      mkdir -p $out/share/floocast
      cp -r . $out/share/floocast

      # GDK_BACKEND=x11: wx.adv.TaskBarIcon uses the old XEmbed tray, which
      # only exists under X11. Under native Wayland the tray icon is never
      # created and "Minimize to System Tray" hides the window for good.
      makeWrapper ${python}/bin/python $out/bin/floocast \
        --add-flags $out/share/floocast/main.py \
        --chdir $out/share/floocast \
        --set GDK_BACKEND x11

      # The .ico is a single 256x256 PNG; desktop entries want a real PNG.
      mkdir -p $out/share/icons/hicolor/256x256/apps
      magick FlooCastApp.ico $out/share/icons/hicolor/256x256/apps/floocast.png

      runHook postInstall
    '';

    desktopItems = [
      (pkgs.makeDesktopItem {
        name = "floocast";
        desktopName = "FlooCast";
        comment = "Configure the FlooGoo FMA120 Bluetooth audio dongle";
        exec = "floocast";
        icon = "floocast";
        categories = [
          "AudioVideo"
          "Audio"
          "Settings"
        ];
      })
    ];
  };
in
{
  environment.systemPackages = [ floocast ];

  # The dongle's control port is /dev/ttyACM*, owned by the dialout group.
  # Merges with the extraGroups list in default.nix. Log out and back in
  # after the first rebuild for it to take effect.
  users.users.yeove.extraGroups = [ "dialout" ];
}
