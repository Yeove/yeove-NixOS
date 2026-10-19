# TrueNAS SMB share, mounted on first access.
#
# The login lives in /etc/secrets/nas-smb (root-only, mode 600), outside this
# repo and outside the Nix store, which every user on the machine can read:
#   username=...
#   password=...
{ pkgs, ... }:

{
  fileSystems."/mnt/NAS" = {
    # LAN address on purpose: full speed at home. Going over the tailnet
    # would push every file through WireGuard on the NAS's little N150.
    device = "//192.168.2.22/NAS HDD 2025"; # spaces are fine, NixOS escapes them for fstab
    fsType = "cifs";
    options = [
      "x-systemd.automount" # mounts on first access, so boot never waits on the NAS
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
      "credentials=/etc/secrets/nas-smb"
      "uid=1000" # yeove
      "gid=100" # users
      "vers=3.0"
      "x-gvfs-show" # shows up in the Files sidebar
    ];
  };

  environment.systemPackages = with pkgs; [
    cifs-utils
    samba # smbclient / nmblookup, for poking at the NAS when debugging
  ];
}
