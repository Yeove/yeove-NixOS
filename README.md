# Random cmds I like to use




# nix-config

NixOS 26.05 + Home Manager for PC2-nixos.

    flake.nix            inputs (nixpkgs, home-manager) and the list of machines
    hosts/PC2-nixos/     this machine: disks, Wacom, user, hardware scan
    modules/             shared pieces: base, desktop, nvidia, audio, network, nas
    home/yeove.nix       apps and GNOME extensions

## Everyday

    nh os switch         rebuild and activate, with a diff of what changed
    nh os boot           same, but takes effect on next boot (for big upgrades)
    nh os test           activate now without making it the boot default
    nix flake update     move to the newest 26.05 packages, then nh os switch

New files are invisible to the flake until you `git add` them.

Undo: pick an older generation in the boot menu, or
`sudo nixos-rebuild switch --rollback`.

## Not in this repo, on purpose

    /etc/secrets/nas-smb   NAS login for the /mnt/NAS mount (root-only)

## Next NixOS release (26.11)

Change both `26.05` URLs in flake.nix to `26.11`, run `nix flake update`,
then `nh os boot` and reboot. Leave `system.stateVersion` and
`home.stateVersion` alone.
