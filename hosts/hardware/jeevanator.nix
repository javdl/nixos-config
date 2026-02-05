# Hardware configuration for Hetzner server (jeevanator)
# NOTE: UUIDs are placeholders - run 'nixos-generate-config' on the actual
# server after bootstrap0 and update these values.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/profiles/qemu-guest.nix")
    ];

  boot.initrd.availableKernelModules = [ "ahci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # PLACEHOLDER UUIDs - update after running nixos-generate-config on actual hardware
  fileSystems."/" =
    { device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/XXXX-XXXX";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  swapDevices =
    [ { device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"; }
    ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
