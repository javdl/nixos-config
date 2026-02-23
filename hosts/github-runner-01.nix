{ config, pkgs, lib, ... }:

# Hetzner dedicated GitHub Actions runner for fuww org (github-runner-01)
# CCX33 instance
#
# Bootstrap process:
#   1. Boot Hetzner server into rescue mode (Linux 64-bit)
#   2. Run: make hetzner/bootstrap0 NIXADDR=<ip> NIXNAME=github-runner-01
#   3. After reboot: make hetzner/bootstrap NIXADDR=<ip> NIXNAME=github-runner-01
#   4. Set up Tailscale: make hetzner/tailscale-auth NIXADDR=<ip> TAILSCALE_AUTHKEY=tskey-auth-xxx

{
  imports = [
    ./hardware/github-runner-01.nix
    ../modules/github-actions-runner.nix
    ../modules/cachix.nix
    ../modules/secrets.nix
    ../modules/automatic-nix-gc.nix
    ../modules/nixos-auto-update.nix
    ../modules/security-audit.nix
    ../modules/ghostty-terminfo.nix
    ../modules/mosh.nix
  ];

  # Enable the GitHub Actions runner packages module
  services.github-actions-runner.enable = true;

  # Latest kernel for best hardware support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use systemd-boot for UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Hostname
  networking.hostName = "github-runner-01";

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

  # Disk-based garbage collection (shorter retention for CI - builds are ephemeral)
  services.automaticNixGC = {
    enable = true;
    minFreeGB = 50;
    maxFreeGB = 100;
    scheduledThresholdGB = 50;
    keepDays = 7;
  };

  # Automatic NixOS updates from git repository
  services.nixosAutoUpdate = {
    enable = true;
    flake = "github:javdl/nixos-config#github-runner-01";
    dates = "04:00";
    randomizedDelaySec = "30m";
    allowReboot = false;
  };

  # Security auditing with auditd
  services.securityAudit = {
    enable = true;
    failureMode = "printk";
    maxLogFile = 50;
    numLogs = 10;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = _: true;

  # Networking - DHCP
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

  # Don't require password for sudo
  security.sudo.wheelNeedsPassword = false;

  # Immutable users (passwords managed via config)
  users.mutableUsers = false;

  # Admin user (joost) for SSH management
  users.users.joost = {
    isNormalUser = true;
    home = "/home/joost";
    extraGroups = [ "docker" "wheel" ];
    shell = pkgs.zsh;
    hashedPassword = "$6$nJOFfAkJl1RJMxUW$DuXpYNq7rc/TE7Awuyjv7vyOyzbUnHmxN3YN1Gz1DiAw363a9GkpEU6bU9MvYa94nXaP7oTSFbZegNb8kAcUm1";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINAQwjDkpe7I8Y6xdD5SbICFy0v5ArILxyTBXhtSOOmw joostvanderlaan@gmail.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFB87It3cS6o8kgD/6r3R59KP2o1eOJz1bgLJl4syLX1 joost"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEx6MK8mQ22KWCA0uDV6uBNvMw/NeBl70Mu4hxrX9SJ9 j8 mac studio"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKiS5X4s5jEKzgpaRMX7gIxKCGcRGSF9qUAlUkOUdFbW j@jlnw.nl"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIy0FO1ta1djvSamjM1Ph/YZpMhMtXSeuFE1Zl9GHhkQ joost+agent@fashionunited.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEfx6qICt/nunP+X3Wv8Y6hhZtGo0AZreAp3QOThy0SD loom-agent-nopass"
    ];
  };

  # Docker already enabled by github-actions-runner module;
  # ensure ip_forward for Docker networking
  boot.kernel.sysctl."net.ipv4.ip_forward" = true;

  # System packages for server management
  environment.systemPackages = with pkgs; [
    git
    gnumake
    htop
    btop
    tmux
    curl
    wget
    rsync
    neovim
    jq
    ripgrep
    fd
    tree
    unzip
    zip
    molly-guard
  ];

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";

  # Use zsh as default shell
  programs.zsh.enable = true;

  # Run dynamically linked binaries (AppImages, prebuilt tools) without patchelf
  programs.nix-ld.enable = true;

  # Load BBR TCP congestion control module
  boot.kernelModules = [ "tcp_bbr" ];

  # System limits and performance tuning
  boot.kernel.sysctl = {
    # Increase inotify limits for file watching
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;

    # Increase file descriptor limits
    "fs.file-max" = 2097152;

    # Process limits (64-bit max)
    "kernel.pid_max" = 4194303;

    # Network optimizations
    "net.core.somaxconn" = 65535;
    "net.ipv4.tcp_max_syn_backlog" = 65535;

    # TCP BBR congestion control
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

  # SOPS secrets for GitHub runner token
  # Token must be an org-level runner registration token (NOT a PAT).
  # Get from: https://github.com/organizations/fuww/settings/actions/runners/new
  # Format: AAU5P4... (29 chars). Expires in 1 hour, single-use per registration.
  sops.defaultSopsFile = ../secrets/github-runner-01.yaml;
  sops.secrets.github-runner-token = {
    mode = "0400";
    owner = "root";
  };
  sops.secrets.github-runner-token-2 = {
    mode = "0400";
    owner = "root";
  };

  # GitHub Actions runner service for fuww organization
  # The systemd service runs configure as the 'github-runner' user (not root).
  # On each start, the unconfigure script (root) copies the token to .new-token,
  # then the configure script (github-runner) consumes it to register with GitHub.
  services.github-runners.fuww-runner = {
    enable = true;
    replace = true;
    name = "github-runner-01";
    tokenFile = config.sops.secrets.github-runner-token.path;
    url = "https://github.com/fuww";
    extraLabels = [ "hetzner" "nixos" "ccx33" "self-hosted-16-cores" ];
    user = "github-runner";
    extraPackages = with pkgs; [ docker ];
    extraEnvironment = {
      DOCKER_HOST = "unix:///var/run/docker.sock";
    };
  };

  services.github-runners.fuww-runner-2 = {
    enable = true;
    replace = true;
    name = "github-runner-01b";
    tokenFile = config.sops.secrets.github-runner-token-2.path;
    url = "https://github.com/fuww";
    extraLabels = [ "hetzner" "nixos" "ccx33" "self-hosted-16-cores" ];
    user = "github-runner";
    extraPackages = with pkgs; [ docker ];
    extraEnvironment = {
      DOCKER_HOST = "unix:///var/run/docker.sock";
    };
  };

  # This value determines the NixOS release
  system.stateVersion = "25.05";
}
