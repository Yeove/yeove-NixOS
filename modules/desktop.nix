# GNOME on Wayland, fonts, and the apps that need a NixOS module to work.
{ pkgs, ... }:

{
  # GNOME itself is Wayland-only now, but the NVIDIA module still keys its
  # early kernel-module loading off this, so it stays on.
  services.xserver.enable = true;

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Fractional scaling (your 125%) is standard in GNOME 50, so the old
  # scale-monitor-framebuffer override is gone. Screen-share portals are
  # also wired up by the GNOME module itself.

  # Electron apps (Discord, Obsidian, VSCodium, GitHub Desktop, Stretchly) run
  # as native Wayland: sharp at 125% and screen sharing goes through PipeWire.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  fonts.packages = with pkgs; [
    maple-mono.truetype
  ];

  programs.firefox.enable = true;
  programs.neovim.enable = true;
  programs.steam.enable = true; # also installs the udev rules SteamVR / Vive trackers need

  environment.systemPackages = with pkgs; [
    gnome-tweaks
    gnome-system-monitor
    wl-clipboard # wl-copy / wl-paste
    xeyes # the eyes only follow the cursor over X11 windows: a quick X11-vs-Wayland check
  ];
}
