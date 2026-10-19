# Yeove's own layer: apps and GNOME extensions. Nothing here needs root, and
# someone on a second seat would get their own file like this one.
{ config, pkgs, inputs, ... }:

let
  # Machine-specific: your profile folder, relative to ~
  # (about:support -> Profile Folder).
  firefoxProfile = ".mozilla/firefox/lflohisp.default";

  # Where you cloned github.com/Yeove/Yeoves_Custom_Firefox_CSS
  firefoxCssRepo = "${config.home.homeDirectory}/Projects/Yeoves_Custom_Firefox_CSS";

  # VSCodium with scroll-anywhere-vscode.js baked into workbench.html at build time.
  # Replaces the Custom CSS and JS Loader, which can't patch the read-only /nix/store.
  # Script comes from the momentum-nav flake input (github.com/Yeove/VSCode_Addon_MomentumNavigation).
  # Pull script changes with: nix flake update momentum-nav, then rebuild.
  vscodium-momentum = pkgs.vscodium.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      html=$(find "$out" -type f -name workbench.html -path '*/electron-*/workbench/*' | head -n1)
      [ -n "$html" ] || { echo "momentum-nav: workbench.html not found" >&2; exit 1; }

      cp ${inputs.momentum-nav}/scroll-anywhere-vscode.js "$(dirname "$html")/"
      substituteInPlace "$html" \
        --replace-fail '</html>' '<script src="./scroll-anywhere-vscode.js"></script></html>'
    '';
  });
in
{
  home.stateVersion = "26.05"; # the HM release this started on; leave it alone from now on


  imports = [ ./digikam-intake ];

  # Stamps source URLs from the Firefox userscript and files them into the NAS library
  services.digikamIntake = {
    enable = true;
    outputDir = "/mnt/NAS/Pictures-VisualArts";
  };


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

    # Code (VSCodium itself is installed by programs.vscodium below)
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

  # VSCodium: the momentum-patched build, plus settings and extensions.
  # mutableUserSettings: each rebuild merges these settings INTO a normal, writable
  # settings.json (the values here win), so changes made in VSCodium's own Settings
  # screen still save. The merge rewrites the file as plain JSON, so keep notes here,
  # not as comments in settings.json.
  programs.vscodium = {
    enable = true;
    package = vscodium-momentum.fhs; # vscodium-fhs + momentum scrolling script (see let block)

    profiles.default = {
      mutableUserSettings = true;

      userSettings = {
        "workbench.colorTheme" = "Catppuccin Mocha";

        # Runs vscode-neovim in its own extension host so other extensions can't slow it down
        #"extensions.experimental.affinity" = {
        #  "asvetliakov.vscode-neovim" = 1;
        #};

        # Recommended by VSCode_Addon_MomentumNavigation
        "editor.smoothScrolling" = false; # interferes with the script's momentum
        "editor.mouseWheelScrollSensitivity" = 1; # fine-tune in the script's CONFIG block instead
        "editor.selectionClipboard" = false; # stop middle-click from pasting
      };

      # Installed from nixpkgs. You can still install others from the Extensions panel.
      extensions = with pkgs.vscode-extensions; [
        catppuccin.catppuccin-vsc
        # asvetliakov.vscode-neovim  #Neovim keybinds hurt my soul, so I've disabled them.
      ];
    };
  };

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

  # GNOME 50+ defaults this to off; pinned so it stays off. GTK apps only.
  dconf.settings."org/gnome/desktop/interface".gtk-enable-primary-paste = false;

  # <profile>/chrome -> the chrome folder in your local clone. A live link,
  # not a copy: edit or git pull in the clone, restart Firefox, done.
  home.file."${firefoxProfile}/chrome".source =
    config.lib.file.mkOutOfStoreSymlink "${firefoxCssRepo}/chrome";
}
