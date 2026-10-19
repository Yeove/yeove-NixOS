# Yeove's own layer: apps and GNOME extensions. Nothing here needs root, and
# someone on a second seat would get their own file like this one.
{ pkgs, ... }:

{
  home.stateVersion = "26.05"; # the HM release this started on; leave it alone from now on

  home.packages = with pkgs; [
    # 3D, video, art
    pkgsCuda.blender # Cycles with CUDA + OptiX, without making all of nixpkgs CUDA
    davinci-resolve
    krita
  # pureref # upstream download currently fails its checksum; re-enable after a `nix flake update`
    godot

    # Photos and files
    digikam
    fsearch

    # Notes and research
    obsidian
    zotero
    stretchly

    # Code
    vscodium-fhs
    github-desktop

    # Recording and audio
    obs-studio
    polyphone
    audacity

    # Playback
    mpv
    vlc
    strawberry
    gnome-music

    # Web and chat
    google-chrome
    discord

    # Everything else
    bottles
    deluge
    perfect_dark
  ];

  # Installs these AND switches them on, so no trip to the Extensions app.
  # This list becomes the complete set of enabled extensions: one you turned
  # on by hand that isn't listed here gets switched off, so add it here.
  programs.gnome-shell = {
    enable = true;
    extensions = map (pkg: { package = pkg; }) (
      with pkgs.gnomeExtensions;
      [
        appindicator # tray icons for OBS, Discord, Steam
        color-picker
        panel-date-format
        emoji-copy
      ]
    );
  };
}
