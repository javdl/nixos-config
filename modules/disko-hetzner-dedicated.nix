# Declarative disk layout for Hetzner dedicated servers (EX-series).
#
# Used by nixos-anywhere during provisioning. EX-series ships with 2x NVMe;
# this layout uses only the first disk (`/dev/nvme0n1`). The second disk
# (`/dev/nvme1n1`) is intentionally left unmanaged so a future host can mount
# it at e.g. /var/lib/github-runner-work without rebuilding the root layout.
#
# Only used during nixos-anywhere install — not activated on running systems.
{ lib, ... }: {
  disko.devices.disk.main = {
    type = "disk";
    device = lib.mkDefault "/dev/nvme0n1";
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
