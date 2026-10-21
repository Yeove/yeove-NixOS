# PC2-nixos: Ryzen 9 9950X3D, ProArt X870E-Creator, RTX 3080 Ti.
#
# Only things that are true of THIS machine live here: its disks, its tablet,
# who logs into it. Anything another workstation would also want goes in
# ../../modules instead.
{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./bluetooth.nix
    ./wacom.nix
    ./vr.nix
    ../../modules/base.nix
    ../../modules/desktop.nix
    ../../modules/nvidia.nix
    ../../modules/audio.nix
    ../../modules/network.nix
    ../../modules/nas.nix
  ];

  networking.hostName = "PC2-nixos"; # no underscores: they're invalid in DNS / MagicDNS
  nixpkgs.hostPlatform = "x86_64-linux";

  # The release this machine was INSTALLED with, not the one it runs.
  # Never change it on an existing install, even after upgrading NixOS.
  system.stateVersion = "25.11";

  # ---------------------------------------------------------------- users
  users.users.yeove = {
    isNormalUser = true; # first normal user = uid 1000 (the mounts below rely on it)
    description = "Yeove";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  home-manager = {
    useGlobalPkgs = true; # same nixpkgs (and unfree setting) as the system
    useUserPackages = true;
    backupFileExtension = "hm-backup"; # moves pre-existing files aside instead of failing
    users.yeove = import ../../home/yeove.nix;
  };

  # ---------------------------------------------- local NTFS drives (shared with Windows)
  # If one of these won't mount, check Windows Fast Startup is off:
  # a hibernated NTFS volume is refused rather than risk corrupting it.
  fileSystems =
    let
      ntfs = uuid: {
        device = "/dev/disk/by-uuid/${uuid}";
        fsType = "ntfs-3g";
        options = [
          "uid=1000" # yeove
          "gid=100" # users
          "umask=007"
          "nofail" # boot carries on if the drive is missing
          "x-gvfs-show" # shows up in the Files sidebar
        ];
      };
    in
    {
      "/mnt/Production" = ntfs "FEDAAE0EDAADC36F";
      "/mnt/Windows" = ntfs "383437C3343782C4";
      "/mnt/Archive" = ntfs "4478ABA878AB9768";
    };

  # ------------------------------------------------------- Wacom PTH-660
  # Keeps circles round when the tablet is mapped across both monitors.
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/peripherals/tablets/056a:0357".keep-aspect = false; #we keep this false, since we have the wacom.nix file do the actual aspect ratio changes
    }
  ];
}
