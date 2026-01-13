# Hardware configuration for Hetzner dedicated server
#
# This is a placeholder that will be replaced by `nixos-generate-config`
# during the bootstrap process. The bootstrap script will:
#   1. Partition the drives
#   2. Run nixos-generate-config
#   3. Copy the generated hardware config here
#
# After bootstrap, commit the actual hardware configuration to git.

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")  # Remove if not a VM/cloud instance
  ];

  # Common modules for Hetzner servers (NVMe, AHCI, USB)
  boot.initrd.availableKernelModules = [
    "nvme"
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];  # Virtualization support
  boot.extraModulePackages = [ ];

  # Filesystem configuration (matches bootstrap0 partitioning)
  # These use labels which are set during partitioning
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
  };

  swapDevices = [
    { device = "/dev/disk/by-label/swap"; }
  ];

  # Platform
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # CPU microcode updates (enable the relevant one based on your CPU)
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  # hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
