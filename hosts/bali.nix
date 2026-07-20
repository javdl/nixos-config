{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

# bali — loom's replacement, on a repurposed EX63 GitHub runner.
# Donor box: github-runner-06 (136.243.104.36). Plain-DHCP networking, so the
# same config would work on any of the other EX63 runners.
#
# Provisioning (wipes the donor! confirm first):
#   1. The donor runs NixOS with no root SSH keys — invoke nixos-anywhere as joost:
#      nix run github:nix-community/nixos-anywhere -- --flake ".#bali" --target-host joost@<donor-ip>
#   2. After first boot, re-key secrets (see .sops.yaml bali anchor):
#      ssh-keygen -R <donor-ip>
#      ssh-keyscan <donor-ip> 2>/dev/null | grep ed25519 | ssh-to-age
#      # replace the &bali anchor, then (on loom, which holds the bootstrap key):
#      SOPS_AGE_KEY=$(sudo ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key) sops updatekeys secrets/bali.yaml
#      make hetzner/copy NIXADDR=<donor-ip> NIXUSER=joost
#      make hetzner/switch NIXADDR=<donor-ip> NIXNAME=bali NIXUSER=joost
#   3. make hetzner/tailscale-auth NIXADDR=<donor-ip> TAILSCALE_AUTHKEY=tskey-auth-xxx

let
  # Hermes cutover switch: flip to true (and disable hermes on loom) when loom
  # retires. Running both gateways with the same tokens double-answers
  # Telegram/Discord/Slack. secrets/bali.yaml already carries hermes-env.
  enableHermes = false;
in
{
  imports = [
    ../modules/hetzner-dedicated-hardware.nix
    ../modules/disko-hetzner-dedicated.nix
    ../modules/cachix.nix
    ../modules/secrets.nix
    ../modules/automatic-nix-gc.nix
    ../modules/nixos-auto-update.nix
    ../modules/security-audit.nix
    ../modules/disk-cleanup.nix
    ../modules/podman.nix
    ../modules/repo-updater.nix
    ../modules/ghostty-terminfo.nix
    inputs.hermes-agent.nixosModules.default
  ];

  # Hermes Agent — personal AI gateway (see hosts/loom.nix, the current holder).
  # Gated as a whole: with the module disabled the hermes user doesn't exist,
  # so an ungated sops secret with owner "hermes" would fail activation.
  sops.secrets."hermes-env" = lib.mkIf enableHermes {
    sopsFile = ../secrets/bali.yaml;
    format = "yaml";
    key = "hermes-env";
    owner = "hermes";
    mode = "0400";
  };

  services.hermes-agent = lib.mkIf enableHermes {
    enable = true;
    addToSystemPackages = true;
    environmentFiles = [ config.sops.secrets."hermes-env".path ];

    # The default sealed venv ships core deps only. The `messaging` extra
    # (pyproject.toml) adds python-telegram-bot, discord.py, slack-bolt —
    # required for the gateway adapters. Without it the service starts but
    # logs "No adapter available for telegram" and no platforms come up.
    extraDependencyGroups = [ "messaging" ];

    settings.model = {
      default = "anthropic/claude-opus-4.6";
      provider = "auto";
      base_url = "https://openrouter.ai/api/v1";
    };
  };

  # joost shares HERMES_HOME with the service (state dir is mode 2770 hermes:hermes).
  users.users.joost.extraGroups = lib.optionals enableHermes [ "hermes" ];

  # The user manager must outlive logins: the chezmoi-memory-sync timer and the
  # persistent tmux service (users/joost/home-manager-server.nix) run under it.
  # On loom this was enabled imperatively via loginctl; here it's declarative.
  users.users.joost.linger = true;

  # Agent ops from loom: joost's personal key (users/joost/nixos.nix "loom")
  # is passphrase-locked, so headless Claude Code sessions on loom use this
  # key instead — the same one every runner host carried for provisioning.
  users.users.joost.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEfx6qICt/nunP+X3Wv8Y6hhZtGo0AZreAp3QOThy0SD loom-agent-nopass"
  ];

  # Latest kernel for best hardware support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use systemd-boot for UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 3;
  boot.loader.efi.canTouchEfiVariables = true;

  # Hostname
  networking.hostName = "bali";

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
    flake = "github:javdl/nixos-config#bali";
    dates = "04:00";
    randomizedDelaySec = "30m";
    allowReboot = false;
  };

  # Repo updater - periodic git sync for development repos
  services.repoUpdater = {
    enable = true;
    user = "joost";
    projectsDir = "/home/joost/code";
    timerInterval = "6h";
    repos = [
      "fuww/developer"
      "Dicklesworthstone/agent_flywheel_clawdbot_skills_and_integrations"
    ];
  };

  # Security auditing — disabled, auditd filled disks on dev servers
  services.securityAudit.enable = false;

  # Weekly disk cleanup (logs, tmp, containers, nix)
  services.diskCleanup.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = _: true;

  # Networking — plain DHCP, like the EX63 runners. No static address block, so
  # this config works unchanged on whichever runner box is the donor.
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
  users.users.joost.shell = lib.mkForce pkgs.zsh;

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

    # IPv6 forwarding for Tailscale exit node capability
    "net.ipv6.conf.all.forwarding" = true;
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

  # Tailscale for secure access with SSH
  services.tailscale = {
    enable = true;
    authKeyFile = "/etc/tailscale/authkey";
    extraUpFlags = [
      "--ssh"
      "--accept-routes"
      "--accept-dns=false"
      "--advertise-exit-node"
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
