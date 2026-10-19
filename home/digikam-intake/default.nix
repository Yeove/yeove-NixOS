# Home Manager module: digiKam intake watcher.
# Stamps source URLs from the Firefox "Save image with source URL" userscript
# into XMP and files the media into the library on the NAS.
#
#   journalctl --user -u digikam-intake -f      # live log (replaces the tray window)
#   systemctl --user restart digikam-intake
#   digikam-intake-watcher --output <dir> --once   # one-off run from a shell
{ config, lib, pkgs, ... }:

let
  cfg = config.services.digikamIntake;

  watcher = pkgs.writeShellApplication {
    name = "digikam-intake-watcher";
    runtimeInputs = [ pkgs.python3 pkgs.exiftool pkgs.inotify-tools pkgs.libnotify ];
    text = ''exec python3 ${./watcher.py} "$@"'';
  };
in
{
  options.services.digikamIntake = {
    enable = lib.mkEnableOption "the digiKam intake watcher";

    intakeDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Downloads/Digikam-intake";
      description = "Folder the userscript downloads into (Firefox download dir + subfolder).";
    };

    outputDir = lib.mkOption {
      type = lib.types.str;
      example = "/mnt/nas/Pictures-VisualArts";
      description = "Library folder stamped files are moved into. Never auto-created.";
    };

    gcAgeMinutes = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Age before intake leftovers are cleaned up (.txt deleted, media only logged).";
    };

    sweepMinutes = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "How often to retry waiting pairs and run garbage collection.";
    };

    sidecarCompatibleName = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Write clip.xmp instead of clip.mp4.xmp (match digiKam's sidecar setting).";
    };

    notify = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show a desktop notification when something fails.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ watcher ];

    systemd.user.services.digikam-intake = {
      Unit.Description = "Stamp source URLs into userscript downloads and file them for digiKam";

      Service = {
        ExecStart = lib.escapeShellArgs ([
          "${watcher}/bin/digikam-intake-watcher"
          "--intake" cfg.intakeDir
          "--output" cfg.outputDir
          "--gc-age" (toString cfg.gcAgeMinutes)
          "--sweep-every" (toString cfg.sweepMinutes)
        ]
        ++ lib.optional cfg.sidecarCompatibleName "--sidecar-compatible-name"
        ++ lib.optional cfg.notify "--notify");
        Restart = "on-failure";
        RestartSec = 10;
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
