# Shared hardware profile for Hetzner dedicated servers (EX-series, etc.)
#
# Unlike Hetzner Cloud (qemu-guest virtio), these are bare-metal Intel boxes
# with PCIe NVMe storage. This module is the dedicated-server counterpart of
# `modules/hetzner-cloud-hardware.nix`.
{ config, lib, modulesPath, ... }: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # NVMe + AHCI for bare-metal Hetzner EX-series.
  boot.initrd.availableKernelModules = [
    "nvme" "ahci" "xhci_pci" "usbhid" "sd_mod"
  ];

  # Allow Intel microcode + other redistributable firmware blobs.
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
