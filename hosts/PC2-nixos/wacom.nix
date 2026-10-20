# ════════════════════════════════════════════════════════════════════════
#  Wacom PTH-660: pen active area anchored near the bottom of the tablet
# ════════════════════════════════════════════════════════════════════════
#
#  WHY
#    GNOME's tablet "area" setting only works on screen tablets (Cintiqs),
#    and "Keep Aspect Ratio" always keeps its strip at the top. So this
#    shortens the pen's vertical range at the udev level instead: everything
#    outside the strip becomes dead space, and GNOME treats the strip as the
#    whole tablet. Keep "Keep Aspect Ratio" off in GNOME (Home Manager:
#    keep-aspect = false under org/gnome/desktop/peripherals/tablets/056a:0357).
#
#  SETTINGS  (top of the let block below)
#    bottomMarginMm     Gap between the active area and the tablet's bottom
#                       edge, in mm. 0 = flush with the bottom; raise it to
#                       move the area up. Range 0-85 (the area is 63 mm tall
#                       on a 148 mm tablet). Decimals like 7.5 are fine.
#    screenW, screenH   GNOME's desktop size in logical pixels. Only change
#                       these if your monitor layout or scaling changes;
#                       they set the area's height so circles stay round.
#
#  APPLYING A CHANGE
#    1. Edit the value(s).
#    2. nh os switch
#    3. wacom-reload
#
#    wacom-reload reloads udev, unplugs and replugs the tablet in software,
#    then prints what the kernel now reports for the pen next to what this
#    file expects. If the tablet isn't on USB (e.g. Bluetooth), unplug and
#    replug it by hand instead.
#
#  GOOD TO KNOW
#    Hovering the pen over a dead zone parks the cursor on the nearest
#    screen edge. Near the tablet's top-left that can trigger the Activities
#    hot corner (Settings > Multitasking > Hot Corner).
#
{ config, pkgs, ... }:
let
  # ── Settings ──────────────────────────────────────────────────────────
  bottomMarginMm = 10;

  # ASUS 2560 / 1.333 = 1920 wide, plus the Dell's 1920; both 1080 tall
  screenW = 3840;
  screenH = 1080;

  # ── Tablet constants (from the kernel; don't change) ──────────────────
  tabletX = 44800; # 224 mm
  tabletY = 29600; # 148 mm
  unitsPerMm = 200;
  penName = "Wacom Intuos Pro M Pen";

  # ── Derived ───────────────────────────────────────────────────────────
  stripH = tabletX * screenH / screenW; # area height: 12600 units = 63 mm
  marginUnits = builtins.floor (bottomMarginMm * unitsPerMm + 0.5);
  yMax = tabletY - marginUnits; # bottom edge of the active area
  yMin = yMax - stripH; # top edge of the active area
  maxMarginMm = (tabletY - stripH) / unitsPerMm;
  range = "${toString yMin}:${toString yMax}";

  wacom-reload = pkgs.writeShellApplication {
    name = "wacom-reload";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      config.systemd.package
    ];
    text = ''
      sudo udevadm control --reload

      # Software replug: de-authorize and re-authorize the tablet's USB device
      dev=""
      for d in /sys/bus/usb/devices/*; do
        if [ "$(cat "$d/idVendor" 2>/dev/null):$(cat "$d/idProduct" 2>/dev/null)" = "056a:0357" ]; then
          dev="$d"
        fi
      done
      if [ -z "$dev" ]; then
        echo "Tablet not found on USB. Unplug and replug it by hand." >&2
        exit 1
      fi
      echo 0 | sudo tee "$dev/authorized" >/dev/null
      sleep 1
      echo 1 | sudo tee "$dev/authorized" >/dev/null

      # Wait for the pen device to come back
      ev=""
      for _ in $(seq 20); do
        ev=$(grep -A5 'Name="${penName}"' /proc/bus/input/devices | grep -o 'event[0-9]*' || true)
        if [ -n "$ev" ]; then break; fi
        sleep 0.25
      done
      if [ -z "$ev" ]; then
        echo "Pen didn't come back. Unplug and replug the tablet by hand." >&2
        exit 1
      fi
      sudo udevadm settle

      echo "Expected: EVDEV_ABS_01=${range}  ID_INPUT_HEIGHT_MM=${toString (stripH / unitsPerMm)}"
      echo "Kernel now reports:"
      udevadm info "/dev/input/$ev" | grep -E 'EVDEV_ABS|_MM=' || true
    '';
  };
in
{
  assertions = [
    {
      assertion = stripH <= tabletY;
      message = "wacom.nix: the desktop is narrower than the tablet; this module only handles wide desktops.";
    }
    {
      assertion = bottomMarginMm >= 0 && yMin >= 0;
      message = "wacom.nix: bottomMarginMm must be between 0 and ${toString maxMarginMm}.";
    }
  ];

  services.udev.extraHwdb = ''
    evdev:name:${penName}:*
      EVDEV_ABS_01=${range}
  '';

  environment.systemPackages = [ wacom-reload ];
}
