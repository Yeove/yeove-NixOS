# Bigscreen Beyond (v1) on the RTX 3080 Ti.
#
#   Beyond + base stations + Vive trackers
#     -> Monado, the open-source VR runtime, tracking through SteamVR's
#        lighthouse driver
#       -> OpenXR games directly; SteamVR (OpenVR) games through xrizer
#
# Monado replaces SteamVR as the runtime because on NVIDIA, SteamVR's image
# lags behind head movement with no fix, while Monado has a workaround (below).
# SteamVR is still needed for its lighthouse driver and for Room Setup.
{ config, pkgs, ... }:

let
  monado = config.services.monado.package;

  # Whatever driver branch modules/nvidia.nix picks, plus the patch below.
  nvidia = config.boot.kernelPackages.nvidiaPackages.${config.hardware.nvidia.branch};
in
{
  # ---------------------------------------------------- NVIDIA: Beyond display
  # The Beyond's display uses Display Stream Compression, and NVIDIA's DSC
  # settings make detailed scenes (fences, text) break up into "rainbow static"
  # blocks. This patch for the open kernel module corrects them; it's the fix
  # the Linux VR wiki lists for NVIDIA. A patched module can't come from a
  # binary cache, so your machine compiles it: a few minutes now, and again
  # after each kernel or driver update.
  #
  # Source: github.com/triple-groove/nvidia-bsb-dsc-fix, commit 2f10c1a,
  # bsb-dsc-fix.patch. Applies cleanly to driver 595.71.05 and compiles.
  #
  # If a rebuild ever fails with a patch error in nvidia-open, a driver update
  # changed the code it touches: get the updated patch from that repo, or
  # comment out this block to go back to the stock driver.
  hardware.nvidia.package = nvidia // {
    open = nvidia.open.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./nvidia-bsb-dsc-fix.patch ];
    });
  };

  # Tearing inside the headset is a known NVIDIA problem when a VRR (G-SYNC)
  # monitor like the PG279QM is connected. If you see it, uncomment this line.
  # It hides VRR from every monitor, so G-SYNC stops working on the desktop too.
  # hardware.nvidia.moduleParams.nvidia-modeset.conceal_vrr_caps = 1;

  # ---------------------------------------------------------------- Monado
  # A user service that starts by itself when a VR app opens. Turn on the
  # headset and every tracker first: Monado only picks up devices that are
  # already on when it starts. By hand:
  #   systemctl --user start monado     (stop / restart the same way)
  #   journalctl --user -u monado -f    (its log)
  services.monado = {
    enable = true;
    defaultRuntime = true; # VR apps outside Steam find Monado through /etc/xdg
  };

  systemd.user.services.monado.environment = {
    # Track with SteamVR's lighthouse driver, which is far better than Monado's
    # own. Monado loads it from your SteamVR install, so keep SteamVR installed.
    STEAMVR_LH_ENABLE = "1";

    # NVIDIA: without these the image trails behind head movement.
    XRT_COMPOSITOR_USE_PRESENT_WAIT = "1";
    U_PACING_COMP_TIME_FRACTION_PERCENT = "90";

    # Take over the headset's display through GNOME (Wayland DRM lease) rather
    # than the X11 route, which is where NVIDIA's vkAcquireXlibDisplayEXT
    # errors come from. If Monado's log says it can't find the display, try
    # commenting this out.
    XRT_COMPOSITOR_FORCE_WAYLAND_DIRECT = "1";

    # Monado renders for the IPD stored in the headset: 64 mm unless you changed
    # it in the Bigscreen Utility on Windows. To use your own, in mm:
    # LH_OVERRIDE_IPD_MM = "64";
  };

  # ----------------------------------------------------------------- Steam
  # Games run inside Steam's container, which hides the VR runtime unless this
  # is set. Set here, it covers every game, so no per-game launch options.
  programs.steam.package = pkgs.steam.override {
    extraEnv.PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES = "1";
  };

  # The Beyond's USB permissions come from Steam's udev rules, already
  # installed by programs.steam in modules/desktop.nix.

  # ---------------------------------------------- per-user runtime pointers
  home-manager.users.yeove =
    { config, ... }:
    {
      # Games inside Steam's container read the runtime from here.
      xdg.configFile."openxr/1/active_runtime.json" = {
        source = "${monado}/share/openxr/1/openxr_monado.json";
        force = true;
      };

      # Sends SteamVR games to xrizer, which runs them on Monado. Read-only on
      # purpose: SteamVR rewrites this file to point at itself whenever it can.
      xdg.configFile."openvr/openvrpaths.vrpath" = {
        force = true;
        text =
          let
            steam = "${config.xdg.dataHome}/Steam";
          in
          builtins.toJSON {
            version = 1;
            jsonid = "vrpathreg";
            external_drivers = null;
            config = [ "${steam}/config" ];
            log = [ "${steam}/logs" ];
            runtime = [ "${pkgs.xrizer}/lib/xrizer" ];
          };
      };
    };
}
