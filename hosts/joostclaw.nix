{ config, pkgs, lib, inputs, ... }:

# Hetzner Cloud server for OpenClaw (AI assistant gateway)
#
# IP: 91.99.10.155
# IPv6: 2a01:4f8:c012:9be6::/64
#
# Provisioned with: make hetzner/provision NIXADDR=91.99.10.155 NIXNAME=joostclaw
#
# Post-provisioning OpenClaw setup:
#   1. SSH in: ssh joost@91.99.10.155
#   2. Create secrets dir: mkdir -p ~/.secrets
#   3. Create Telegram bot via @BotFather, save token: echo "BOT_TOKEN" > ~/.secrets/telegram-bot-token
#   4. Get your Telegram user ID from @userinfobot
#   5. Generate gateway token: openssl rand -hex 32 > ~/.secrets/openclaw-gateway-token
#   6. Update this file: set allowFrom, enable openclaw, rebuild

{
  imports = [
    ../modules/hetzner-cloud-hardware.nix
    ../modules/disko-hetzner-cloud.nix
    ../modules/cachix.nix
    ../modules/secrets.nix
    ../modules/automatic-nix-gc.nix
    ../modules/nixos-auto-update.nix
    ../modules/security-audit.nix
    ../modules/podman.nix
    ../modules/repo-updater.nix
    ../modules/ghostty-terminfo.nix
    ../modules/mosh.nix
  ];

  # Latest kernel for best hardware support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use systemd-boot for UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Hostname
  networking.hostName = "joostclaw";

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

  # Disk-based garbage collection — smaller disk (76GB), trigger earlier
  services.automaticNixGC = {
    enable = true;
    minFreeGB = 10;
    maxFreeGB = 20;
    scheduledThresholdGB = 10;
    keepDays = 7;
  };

  # Automatic NixOS updates from git repository
  services.nixosAutoUpdate = {
    enable = true;
    flake = "github:javdl/nixos-config#joostclaw";
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
  networking.interfaces.enp1s0.ipv6.addresses = [{
    address = "2a01:4f8:c012:9be6::1";
    prefixLength = 64;
  }];
  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = "enp1s0";
  };

  # Firewall
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

  # Docker for containerized development
  virtualisation.docker.enable = true;

  # Podman for rootless containers
  virtualisation.podmanConfig = {
    enable = true;
    dockerCompat = false;
    autoPrune = true;
  };

  # System packages
  environment.systemPackages = with pkgs; [
    git gnumake htop btop tmux
    curl wget rsync
    gcc neovim
    jq ripgrep fd tree unzip zip
    molly-guard
  ];

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";

  # Use zsh as default shell
  programs.zsh.enable = true;
  users.users.joost.shell = lib.mkForce pkgs.zsh;

  # Run dynamically linked binaries without patchelf
  programs.nix-ld.enable = true;

  # TCP BBR congestion control
  boot.kernelModules = [ "tcp_bbr" ];

  # System limits and performance tuning
  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;
    "fs.file-max" = 2097152;
    "kernel.pid_max" = 4194303;
    "net.core.somaxconn" = 65535;
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq";
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_rmem" = "4096 87380 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";
    "net.ipv6.conf.all.forwarding" = true;
  };

  # PAM limits
  security.pam.loginLimits = [
    { domain = "*"; type = "soft"; item = "nofile"; value = "65536"; }
    { domain = "*"; type = "hard"; item = "nofile"; value = "65536"; }
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
