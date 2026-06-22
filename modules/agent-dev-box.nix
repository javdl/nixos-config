{
  config,
  pkgs,
  lib,
  ...
}:

# Shared host configuration for agent dev boxes (machines that run autonomous
# coding agents such as rondo). Captures everything common across agent hosts so
# a per-host file only has to set its hostname, hardware import, auto-update
# target, and workload user.
#
# Reuse:
#   - Another machine for an existing agent → new hosts/<agent>-NN.nix importing
#     this module + the shared per-agent users/<agent>/ files.
#   - A brand-new agent user → copy users/<agent>/ and add a host file.
#
# This module intentionally does NOT set networking.hostName,
# services.nixosAutoUpdate.flake, or the workload user — those are host-specific
# and live in the importing hosts/<agent>-NN.nix.

{
  imports = [
    ./cachix.nix
    ./secrets.nix
    ./automatic-nix-gc.nix
    ./nixos-auto-update.nix
    ./security-audit.nix
    ./disk-cleanup.nix
    ./podman.nix
    ./repo-updater.nix
    ./ghostty-terminfo.nix
    ./mosh.nix
  ];

  # Latest kernel for best hardware support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use systemd-boot for UEFI — cap entries so /boot does not fill up
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 3;
  boot.loader.efi.canTouchEfiVariables = true;

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

  # Auto-update is enabled here; each host sets its own flake target.
  services.nixosAutoUpdate = {
    enable = true;
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

  # Networking - IPv4 via DHCP
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

  # Admin user (joost) for management — identical across every agent box
  users.users.joost = {
    isNormalUser = true;
    home = "/home/joost";
    extraGroups = [
      "docker"
      "wheel"
    ];
    shell = pkgs.zsh;
    hashedPassword = "$6$nJOFfAkJl1RJMxUW$DuXpYNq7rc/TE7Awuyjv7vyOyzbUnHmxN3YN1Gz1DiAw363a9GkpEU6bU9MvYa94nXaP7oTSFbZegNb8kAcUm1";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINAQwjDkpe7I8Y6xdD5SbICFy0v5ArILxyTBXhtSOOmw joostvanderlaan@gmail.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFB87It3cS6o8kgD/6r3R59KP2o1eOJz1bgLJl4syLX1 joost"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEx6MK8mQ22KWCA0uDV6uBNvMw/NeBl70Mu4hxrX9SJ9 j8 mac studio"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKiS5X4s5jEKzgpaRMX7gIxKCGcRGSF9qUAlUkOUdFbW j@jlnw.nl"
    ];
  };

  # Docker for containerized development (agents bring up service deps, e.g. the
  # target repo's Postgres, the same way they do on the colleague dev boxes).
  virtualisation.docker.enable = true;

  # Podman for rootless containers
  virtualisation.podmanConfig = {
    enable = true;
    dockerCompat = false;
    autoPrune = true;
  };

  # System packages for remote development
  environment.systemPackages = with pkgs; [
    git
    gnumake
    htop
    btop
    tmux
    curl
    wget
    rsync
    gcc
    neovim
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
}
