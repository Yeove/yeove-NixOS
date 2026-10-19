# PipeWire, the OBS -> Discord virtual mic, and LSP plugins for OBS.
{ pkgs, ... }:

{
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;

    # 48 kHz everywhere. Quantum 1024 is what cured the Discord mic stutter
    # on the old 3900X; the 9950X3D can very likely run 512 (~10 ms) if you
    # want snappier OBS monitoring.
    extraConfig.pipewire."92-clock" = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 1024;
        "default.clock.min-quantum" = 32;
        "default.clock.max-quantum" = 2048;
      };
    };

    # Virtual mic (the VB-Cable replacement). One loopback, two faces:
    #   sink   "OBS Virtual Mic" -> set as OBS's Monitoring Device
    #   source "OBS Virtual Mic" -> pick as the input device in Discord
    extraConfig.pipewire."99-obs-virtmic" = {
      "context.modules" = [
        {
          name = "libpipewire-module-loopback";
          args = {
            "node.description" = "OBS Virtual Mic";
            "capture.props" = {
              "node.name" = "obs_virtmic_sink";
              "node.description" = "OBS Virtual Mic";
              "media.class" = "Audio/Sink";
              "audio.position" = [
                "FL"
                "FR"
              ];
            };
            "playback.props" = {
              "node.name" = "obs_virtmic_source";
              "node.description" = "OBS Virtual Mic";
              "media.class" = "Audio/Source/Virtual";
              "audio.position" = [
                "FL"
                "FR"
              ];
            };
          };
        }
      ];
    };

    # Keeps sound cards awake, so there's no pop and no clipped first
    # syllable when audio starts. (Your old comment credited the clock
    # block with this; this rule is what actually does it.)
    wireplumber.extraConfig."51-no-suspend" = {
      "monitor.alsa.rules" = [
        {
          matches = [
            { "node.name" = "~alsa_input.*"; }
            { "node.name" = "~alsa_output.*"; }
          ];
          actions.update-props."session.suspend-timeout-seconds" = 0;
        }
      ];
    };
  };

  # OBS reads VST_PATH and searches it recursively. Setting it replaces OBS's
  # built-in folder list, so ~/.vst is added back for VSTs you drop in by hand.
  environment.sessionVariables.VST_PATH = [
    "/run/current-system/sw/lib/vst"
    "$HOME/.vst"
  ];

  environment.systemPackages = with pkgs; [
    lsp-plugins # EQ + analyzer for OBS (ReaEQ / SPAN stand-ins); must stay system-wide for VST_PATH
    qpwgraph # patchbay: see OBS -> virtual mic -> Discord
    pavucontrol # per-app device picker
  ];
}
