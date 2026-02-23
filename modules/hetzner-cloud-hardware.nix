# Shared hardware profile for Hetzner Cloud CPX servers
#
# All Hetzner Cloud VMs use identical virtual hardware (QEMU/KVM guest,
# virtio devices, Intel CPU). This module extracts the common config
# that was previously duplicated across each host's hardware file.
{ config, lib, modulesPath, ... }: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [
    "ahci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod"
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
