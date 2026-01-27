{ config, lib, pkgs, ... }:

# Podman module for rootless containers
#
# Provides Docker-compatible container runtime without daemon:
# - Rootless containers (better security)
# - Docker CLI compatibility via socket emulation
# - OCI-compliant image building with buildah
# - Container composition with podman-compose

let
  cfg = config.virtualisation.podmanConfig;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.virtualisation.podmanConfig = {
    enable = mkEnableOption "Podman container runtime";

    dockerCompat = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Docker CLI compatibility (creates docker -> podman alias)";
    };

    dockerSocket = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Docker socket emulation for tools expecting /var/run/docker.sock";
    };

    enableNvidia = mkOption {
      type = types.bool;
      default = false;
      description = "Enable NVIDIA GPU support in containers";
    };

    storageDriver = mkOption {
      type = types.enum [ "overlay" "btrfs" "zfs" "vfs" ];
      default = "overlay";
      description = "Container storage driver";
    };

    autoPrune = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically prune unused images and containers weekly";
    };
  };

  config = mkIf cfg.enable {
    # Enable Podman
    virtualisation.podman = {
      enable = true;

      # Create docker alias for CLI compatibility
      dockerCompat = cfg.dockerCompat;

      # Enable Docker socket emulation if requested
      dockerSocket.enable = cfg.dockerSocket;

      # Default network with DNS
      defaultNetwork.settings.dns_enabled = true;

      # Use built-in auto-prune feature
      autoPrune = {
        enable = cfg.autoPrune;
        dates = "weekly";
        flags = [ "--all" "--volumes" ];
      };

      # Extra packages for rootless support
      extraPackages = with pkgs; [
        slirp4netns      # For rootless networking
        fuse-overlayfs   # For rootless port forwarding
      ];
    };

    # NVIDIA container support (using current option name)
    hardware.nvidia-container-toolkit.enable = cfg.enableNvidia;

    # Container tools
    environment.systemPackages = with pkgs; [
      podman-compose  # Docker Compose compatible
      buildah         # OCI image builder
      skopeo          # Container image operations
    ];

    # Storage configuration
    virtualisation.containers.storage.settings = {
      storage = {
        driver = cfg.storageDriver;
        graphroot = "/var/lib/containers/storage";
        runroot = "/run/containers/storage";
      };
    };
  };
}
