# Declarative disk layout for Hetzner Cloud CPX servers (used by nixos-anywhere)
#
# This defines the partitioning scheme that disko applies during provisioning.
# It matches the layout previously done manually by hetzner/bootstrap0.
#
# Only used during nixos-anywhere install — not activated on running systems.
{ lib, ... }: {
  disko.devices.disk.main = {
    type = "disk";
    device = lib.mkDefault "/dev/sda";  # Hetzner Cloud CPX uses /dev/sda
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        swap = {
          size = "8G";
          content = {
            type = "swap";
            randomEncryption = true;
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
