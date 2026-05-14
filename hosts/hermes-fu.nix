{ config, pkgs, lib, inputs, ... }:

# Hetzner Cloud VM: hermes-fu — FashionUnited company-wide hermes-agent host
# IP: <fill in after order>
#
# Bootstrap process (one-command, no rescue mode needed — uses nixos-anywhere + disko):
#   1. Order a Hetzner Cloud VM (CCX-class recommended for hermes uv2nix builds)
#   2. make hetzner/provision NIXADDR=<ip> NIXNAME=hermes-fu
#   3. ssh agent@<ip>  → derive age key, populate secrets/hermes-fu.yaml, uncomment sops below
#   4. make hetzner/tailscale-auth NIXADDR=<ip> TAILSCALE_AUTHKEY=tskey-auth-...
#
# This host is a clone of loom's hermes-agent setup (Plans/migrate-hermes-to-nix-module.md).
# Differences from loom: cloud-hardware modules, no static IPv6, no advertise-exit-node,
# no repoUpdater, admin user `agent` instead of `joost`.

{
  imports = [
    ../modules/hetzner-cloud-hardware.nix
    ../modules/disko-hetzner-cloud.nix
    ../modules/cachix.nix
    ../modules/secrets.nix
    ../modules/automatic-nix-gc.nix
    ../modules/nixos-auto-update.nix
    ../modules/security-audit.nix
    ../modules/disk-cleanup.nix
    ../modules/podman.nix
    ../modules/ghostty-terminfo.nix
    inputs.hermes-agent.nixosModules.default
  ];

  # Hermes Agent — FashionUnited company-wide AI gateway.
  # Primary messaging platform: Slack (Socket Mode, no public endpoint required).
  # State: /var/lib/hermes/.hermes (mode 2770, hermes:hermes, hardcoded by upstream).
  # Secrets: secrets/hermes-fu.yaml -> sops -> hermes-env (dotenv, concatenated raw).
  #
  # IMPORTANT: The sops.secrets block and environmentFiles are commented out until
  # post-provisioning. New VMs don't have an SSH host key (and thus no age recipient)
  # until first boot. Workflow:
  #   1. Provision host (this config builds; service starts without env vars)
  #   2. Derive age key from /etc/ssh/ssh_host_ed25519_key.pub, add to .sops.yaml
  #   3. `sops secrets/hermes-fu.yaml` to create the encrypted payload. Required keys:
  #        SLACK_BOT_TOKEN       xoxb-... (from Slack app's Install App page)
  #        SLACK_APP_TOKEN       xapp-... (Socket Mode token, scope: connections:write)
  #        SLACK_ALLOWED_USERS   U01ABC2DEF3,U01XYZ... (comma-separated Slack member IDs)
  #      Optional:
  #        SLACK_HOME_CHANNEL       C012345... (target channel for cron / unsolicited posts)
  #        SLACK_HOME_CHANNEL_NAME  general    (human-readable label for the above)
  #        ANTHROPIC_API_KEY        (or OPENROUTER_API_KEY — provider auto-detect picks one)
  #      Slack app setup steps + required OAuth scopes / event subscriptions are
  #      documented at hermes-agent.nousresearch.com/docs/user-guide/messaging/slack
  #      (or run `hermes slack manifest --write` on the host to generate a manifest).
  #   4. Uncomment the two blocks below
  #   5. Commit + `nixos-rebuild switch --flake github:javdl/nixos-config#hermes-fu`
  #
  # sops.secrets."hermes-env" = {
  #   sopsFile = ../secrets/hermes-fu.yaml;
  #   format = "yaml";
  #   key = "hermes-env";
  #   owner = "hermes";
  #   mode = "0400";
  # };

  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;
    # environmentFiles = [ config.sops.secrets."hermes-env".path ];

    # The default sealed venv ships core deps only. The `messaging` extra
    # (pyproject.toml) adds slack-bolt, slack-sdk, python-telegram-bot, discord.py
    # — required for the gateway adapters. Without it the service starts but
    # logs "No adapter available for slack" and no platforms come up.
    extraDependencyGroups = [ "messaging" ];

    settings = {
      model = {
        default = "anthropic/claude-opus-4.6";
        provider = "auto";
        base_url = "https://openrouter.ai/api/v1";
      };

      # Slack platform — FashionUnited primary surface. Adapter auto-activates
      # when SLACK_BOT_TOKEN is present in $HERMES_HOME/.env; these settings
      # shape the in-channel behavior. Schema reference:
      # github:NousResearch/hermes-agent/gateway/config.py (PlatformConfig).
      platforms.slack = {
        enabled = true;
        reply_to_mode = "first";    # thread only the first chunk of multi-part replies
        extra = {
          reply_in_thread = true;   # keep channels tidy; replies thread under the prompt
          require_mention = true;   # don't auto-engage on every channel message
          unauthorized_dm_behavior = "ignore";  # SLACK_ALLOWED_USERS is the gate
        };
      };

      # Per-user conversation isolation in shared channels (top-level GatewayConfig field).
      group_sessions_per_user = true;
    };
  };

  # agent shares HERMES_HOME with the service (state dir is mode 2770 hermes:hermes).
  users.users.agent.extraGroups = [ "hermes" ];

  # Latest kernel for best hardware support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use systemd-boot for UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Hostname
  networking.hostName = "hermes-fu";

  # Timezone (UTC for servers)
  time.timeZone = "UTC";

  # Nix configuration
  nix = {
    package = pkgs.nixVersions.latest;
    extraOptions = ''
      experimental-features = nix-command flakes
      keep-outputs = true
      keep-derivations = true
    '';
  };

  # Disk-based garbage collection (only runs when disk space is low)
  services.automaticNixGC = {
    enable = true;
    minFreeGB = 50;
    maxFreeGB = 100;
    scheduledThresholdGB = 50;
    keepDays = 14;
  };

  # Automatic NixOS updates from git repository
  services.nixosAutoUpdate = {
    enable = true;
    flake = "github:javdl/nixos-config#hermes-fu";
    dates = "04:00";
    randomizedDelaySec = "30m";
    allowReboot = false;
  };

  # Security auditing — disabled, auditd filled disks on dev servers
  services.securityAudit.enable = false;

  # Weekly disk cleanup (logs, tmp, containers, nix)
  services.diskCleanup.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = _: true;

  # Networking - DHCP for IPv4; IPv6 handled by Hetzner Cloud (no static config needed)
  networking.useDHCP = true;

  # Firewall - base config (Tailscale settings added below)
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # SSH daemon - key-only auth for security
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
      KbdInteractiveAuthentication = false;
    };
  };

  # Don't require password for sudo (convenient for remote dev)
  security.sudo.wheelNeedsPassword = false;

  # Immutable users (passwords managed via config)
  users.mutableUsers = false;

  # Docker for containerized development
  virtualisation.docker.enable = true;

  # Podman for rootless containers (Docker alternative with better security)
  virtualisation.podmanConfig = {
    enable = true;
    dockerCompat = false;
    autoPrune = true;
  };

  # System packages for remote development
  environment.systemPackages = with pkgs; [
    # Essentials
    git
    gnumake
    htop
    btop
    tmux

    # Network tools
    curl
    wget
    rsync

    # Development
    gcc
    gnumake

    # Editors
    neovim

    # Utils
    jq
    ripgrep
    fd
    tree
    unzip
    zip

    # Safety: require typing hostname to confirm shutdown/reboot via SSH
    molly-guard
  ];

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";

  # Use zsh as default shell
  programs.zsh.enable = true;
  users.users.agent.shell = lib.mkForce pkgs.zsh;

  # Run dynamically linked binaries (AppImages, prebuilt tools) without patchelf
  programs.nix-ld.enable = true;

  # Load BBR TCP congestion control module
  boot.kernelModules = [ "tcp_bbr" ];

  # System limits and performance tuning
  boot.kernel.sysctl = {
    # Increase inotify limits for file watching (Claude Code, IDEs)
    "fs.inotify.max_user_watches" = 2097152;
    "fs.inotify.max_user_instances" = 2048;

    # Increase file descriptor limits
    "fs.file-max" = 2097152;

    # Process limits (64-bit max)
    "kernel.pid_max" = 4194303;

    # Network optimizations
    "net.core.somaxconn" = 65535;

    # TCP BBR congestion control (better performance, especially on lossy networks)
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq";

    # Larger socket buffers for high-throughput connections
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_rmem" = "4096 87380 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";
  };

  # PAM limits
  security.pam.loginLimits = [
    {
      domain = "*";
      type = "soft";
      item = "nofile";
      value = "65536";
    }
    {
      domain = "*";
      type = "hard";
      item = "nofile";
      value = "65536";
    }
  ];

  # Disable unnecessary services for a headless server
  services.xserver.enable = false;
  services.printing.enable = false;
  services.pulseaudio.enable = false;

  # Enable useful services
  services.nscd.enable = true;
  services.dbus.enable = true;

  # Tailscale for secure access with SSH (no exit-node advertising — loom-specific)
  services.tailscale = {
    enable = true;
    authKeyFile = "/etc/tailscale/authkey";
    extraUpFlags = [
      "--ssh"
      "--accept-routes"
      "--accept-dns=false"
    ];
  };

  # Allow Tailscale traffic through firewall
  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  # This value determines the NixOS release
  system.stateVersion = "25.05";
}
