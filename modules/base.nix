# What every machine gets: boot, Nix itself, housekeeping, locale.
{ pkgs, ... }:

{
  # ----------------------------------------------------------------- boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10; # stops old generations filling /boot
  boot.loader.efi.canTouchEfiVariables = true;

  hardware.enableRedistributableFirmware = true; # AMD microcode, Wi-Fi / Bluetooth firmware

  # ------------------------------------------------------------------ nix
  nixpkgs.config.allowUnfree = true;

  # Zotero bundles its own Firefox ESR 140 runtime, which went end-of-life on
  # 2026-10-13. Allowed by exact version only: once nixpkgs moves Zotero to a
  # newer runtime this line stops matching anything and can be deleted.
  nixpkgs.config.permittedInsecurePackages = [
    "firefox-esr-140-bin-unwrapped-140.17.0esr"
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # Prebuilt CUDA packages, which cache.nixos.org doesn't carry.
    substituters = [ "https://cache.nixos-cuda.org" ];
    trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  # The flake is the only source of truth now. With channels off, a stray
  # `sudo nixos-rebuild switch` errors out instead of quietly rebuilding
  # the old /etc/nixos/configuration.nix.
  nix.channel.enable = false;

  # nh: `nh os switch` rebuilds from the flake below and shows what changed.
  programs.nh = {
    enable = true;
    flake = "/home/yeove/nix-config";
    clean = {
      enable = true; # weekly: drop generations older than 14 days, always keep 10
      extraArgs = "--keep-since 14d --keep 10";
    };
  };
  nix.optimise.automatic = true; # weekly: hard-link identical files in the store

  # --------------------------------------------------------------- locale
  time.timeZone = "America/Toronto";

  i18n.defaultLocale = "en_CA.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_CA.UTF-8";
    LC_IDENTIFICATION = "en_CA.UTF-8";
    LC_MEASUREMENT = "en_CA.UTF-8";
    LC_MONETARY = "en_CA.UTF-8";
    LC_NAME = "en_CA.UTF-8";
    LC_NUMERIC = "en_CA.UTF-8";
    LC_PAPER = "en_CA.UTF-8";
    LC_TELEPHONE = "en_CA.UTF-8";
    LC_TIME = "en_DK.UTF-8"; # ISO 8601 dates (YYYY-MM-DD)
  };

  # ---------------------------------------------------------- base tools
  environment.systemPackages = with pkgs; [
    git
    fastfetch
    ffmpeg
    pciutils # lspci
  ];
}
