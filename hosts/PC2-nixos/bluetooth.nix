# ProArt X870E-Creator WiFi Bluetooth fixes
# MediaTek MT7927 (Filogic 380) Wi-Fi 7 + Bluetooth on the ProArt X870E-Creator WiFi.
# This board is rev 2: Foxconn-built module, Bluetooth on USB 0489:e13a.
#
# Workaround for broken drivers.
#
#   1. Kernel. Bluetooth support landed in 7.1, Wi-Fi in 7.2, but the NixOS
#      default is the 6.18 LTS, hence linuxPackages_latest below. Drop that
#      line once the default kernel is 7.2+. If the Nvidia module ever fails
#      to build against a brand-new kernel, pin a versioned linuxPackages_7_*
#      set instead.
#
#   2. Bluetooth firmware. BT_RAM_CODE_MT6639_2_1_hdr.bin isn't in
#      linux-firmware because only MediaTek can submit it (MR !946 was closed
#      for that reason), so it's fetched from the community maintainer's
#      branch, pinned by commit + hash. Delete mt6639-bt-firmware once this
#      prints a filename:
#        ls $(nix build nixpkgs#linux-firmware --no-link --print-out-paths)/lib/firmware/mediatek/mt7927 | grep BT
#
# If Bluetooth vanishes from lsusb entirely, the card's firmware has locked
# up, and that survives warm reboots. Fix: shut down, PSU switch off, wait
# 10 s, power on. Or enable ErP (S4+S5) in the BIOS to cut standby power on
# every shutdown, at the cost of USB ports not charging while off.
#
# Sources:
#   Fix this follows:      https://pmcdade.org/blog/mt7927-linux/
#   Upstream status:       https://github.com/jetm/mediatek-mt7927-dkms

{ pkgs, ... }:

let
  # MT6639 BT firmware, not in linux-firmware yet. Pinned by commit + hash.
  mt6639-bt-firmware = pkgs.runCommand "mt6639-bt-firmware" {
    src = pkgs.fetchurl {
      url = "https://gitlab.com/jetm/linux-firmware/-/raw/77ad2a92acf2ac3e5ea47432b43d925ff99db909/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin";
      sha256 = "669c5c99a0c59c85c1285d3d1b8b31915c2d31341a2244f4eddcbfd60ffbbc76";
    };
  } ''
    install -Dm644 "$src" "$out/lib/firmware/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin"
  '';
in
{
  boot.kernelPackages = pkgs.linuxPackages_latest;  # MT6639 BT driver needs 7.1+

  hardware.firmware = [ mt6639-bt-firmware ];

  # Baseline, needed either way
  hardware.enableRedistributableFirmware = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
}
