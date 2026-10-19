# RTX 3080 Ti: proprietary driver, open kernel modules, in-kernel suspend.
{ pkgs, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;

  hardware.nvidia = {
    branch = "stable"; # 595 series on 26.05; "beta" / "new_feature" if you ever need them

    # NVIDIA's recommended kernel module for RTX 20-series and newer.
    # If anything regresses after the switch, set this to false.
    open = true;

    modesetting.enable = true; # required for Wayland
    powerManagement.enable = true; # keeps VRAM contents across suspend

    # On 595+ with open modules, 26.05 also turns on kernelSuspendNotifier:
    # the driver suspends in-kernel instead of through the old nvidia-suspend
    # services, which is what the SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false
    # workaround was papering over, so that's gone. If suspend ever misbehaves,
    # set `powerManagement.kernelSuspendNotifier = false;` and bring it back.

    # Black-screen-after-resume workaround (was boot.extraModprobeConfig).
    moduleParams.nvidia-modeset.vblank_sem_control = 0;
  };

  # CUDA is NOT switched on for all of nixpkgs (no global cudaSupport):
  # that made unrelated packages like digiKam build CUDA variants. Blender
  # gets it individually in home/yeove.nix; Resolve, OBS's NVENC and ffmpeg
  # talk to the driver directly and never needed it.
  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit # nvcc etc., for compiling your own CUDA code
  ];
}
