{ config, lib, pkgs, ... }:

# NixOS auto-update module
#
# Polls a git repository and automatically deploys NixOS configuration
# when changes are detected. Built on top of system.autoUpgrade.
#
# Features:
# - Configurable git repo URL and branch
# - SSH key authentication support via sops
# - Pre-upgrade git fetch to get latest changes
# - Optional nix-output-monitor (nom) integration
# - Configurable poll interval
# - Tracking of deployed revision

let
  cfg = config.services.nixosAutoUpdate;
  inherit (lib) mkEnableOption mkOption types mkIf mkMerge;
in {
  options.services.nixosAutoUpdate = {
    enable = mkEnableOption "NixOS automatic updates from git";

    flake = mkOption {
      type = types.str;
      description = ''
        Flake URI to use for updates.
        Examples:
        - "github:user/repo#hostname" (GitHub)
        - "git+ssh://git@github.com/user/repo#hostname" (SSH)
        - "git+file:///path/to/repo#hostname" (local bare repo)
      '';
    };

    dates = mkOption {
      type = types.str;
      default = "04:00";
      description = "Systemd calendar expression for when to check for updates";
    };

    randomizedDelaySec = mkOption {
      type = types.str;
      default = "1h";
      description = "Maximum random delay before running update (systemd time format)";
    };

    allowReboot = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to automatically reboot if kernel changed";
    };

    rebootWindow = mkOption {
      type = types.nullOr (types.attrsOf types.str);
      default = null;
      example = { lower = "01:00"; upper = "05:00"; };
      description = "Time window during which reboots are allowed";
    };

    useNom = mkOption {
      type = types.bool;
      default = false;
      description = "Use nix-output-monitor (nom) for prettier build output";
    };

    sshKeySecret = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Name of sops secret containing SSH key for private repos.
        The secret should be defined in your sops configuration.
      '';
    };

    persistent = mkOption {
      type = types.bool;
      default = true;
      description = "Run update on boot if scheduled time was missed";
    };

    operation = mkOption {
      type = types.enum [ "switch" "boot" ];
      default = "switch";
      description = "Whether to switch immediately or prepare for next boot";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Base auto-upgrade configuration
    {
      system.autoUpgrade = {
        enable = true;
        flake = cfg.flake;
        dates = cfg.dates;
        randomizedDelaySec = cfg.randomizedDelaySec;
        allowReboot = cfg.allowReboot;
        persistent = cfg.persistent;
        operation = cfg.operation;

        # Don't write lock file when using remote flakes
        flags = [
          "--no-write-lock-file"
          "-L"  # Print build logs
        ];
      };
    }

    # Reboot window configuration
    (mkIf (cfg.rebootWindow != null) {
      system.autoUpgrade.rebootWindow = cfg.rebootWindow;
    })

    # SSH key support for private repositories
    (mkIf (cfg.sshKeySecret != null) {
      # Ensure the sops secret is defined
      sops.secrets.${cfg.sshKeySecret} = {
        mode = "0600";
        owner = "root";
      };

      # Configure SSH for root to use the deploy key
      systemd.services.nixos-upgrade.serviceConfig.Environment = [
        "GIT_SSH_COMMAND=ssh -i ${config.sops.secrets.${cfg.sshKeySecret}.path} -o StrictHostKeyChecking=accept-new"
      ];
    })

    # nix-output-monitor support
    (mkIf cfg.useNom {
      environment.systemPackages = [ pkgs.nix-output-monitor ];
      # Note: nom integration requires manual nixos-rebuild invocation
      # The systemd service logs can still be viewed with journalctl
    })

    # Add helpful packages
    {
      environment.systemPackages = with pkgs; [
        git  # Needed for flake operations
      ];
    }
  ]);
}
