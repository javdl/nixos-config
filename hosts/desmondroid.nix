{ config, pkgs, lib, ... }:

# Hetzner dedicated server for desmond (desmondroid)
# IP: 91.99.228.135 (Nuremberg, CPX32)
#
# Bootstrap process:
#   1. Boot Hetzner server into rescue mode (Linux 64-bit)
#   2. Run: make hetzner/bootstrap0 NIXADDR=<ip> NIXNAME=desmondroid
#   3. After reboot: make hetzner/bootstrap NIXADDR=<ip> NIXNAME=desmondroid
#   4. Connect: ssh desmondroid (uses ~/.ssh config)

{
  imports = [
    ./hardware/desmondroid.nix
    ../modules/cachix.nix
    ../modules/secrets.nix
    ../modules/automatic-nix-gc.nix
    ../modules/nixos-auto-update.nix
    ../modules/security-audit.nix
    ../modules/podman.nix
    ../modules/repo-updater.nix
    ../modules/ghostty-terminfo.nix
  ];

  # Latest kernel for best hardware support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use systemd-boot for UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Hostname
  networking.hostName = "desmondroid";

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
    flake = "github:javdl/nixos-config#desmondroid";
    dates = "04:00";
    randomizedDelaySec = "30m";
    allowReboot = false;
  };

  # Repo updater - periodic git sync for development repos
  services.repoUpdater = {
    enable = true;
    user = "desmond";
    projectsDir = "/home/desmond/code";
    timerInterval = "6h";
    repos = [
      "fuww/developer"
      "fuww/frontend"
      "fuww/api"
      "fuww/prompts"
      "fuww/about"
    ];
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

  # Networking - dual stack (IPv4 via DHCP + static IPv6)
  networking.useDHCP = true;
  # IPv6 address will be configured after provisioning
  # networking.interfaces.enp1s0.ipv6.addresses = [{
  #   address = "2a01:...::1";
  #   prefixLength = 64;
  # }];
  # networking.defaultGateway6 = {
  #   address = "fe80::1";
  #   interface = "enp1s0";
  # };

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

  # Admin user (joost) for management
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
    ];
  };

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
  users.users.desmond.shell = lib.mkForce pkgs.zsh;

  # Run dynamically linked binaries (AppImages, prebuilt tools) without patchelf
  programs.nix-ld.enable = true;

  # Load BBR TCP congestion control module
  boot.kernelModules = [ "tcp_bbr" ];

  # System limits and performance tuning
  boot.kernel.sysctl = {
    # Increase inotify limits for file watching (Claude Code, IDEs)
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;

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
  hardware.pulseaudio.enable = false;

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
