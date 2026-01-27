{ config, pkgs, lib, ... }:

# Hetzner dedicated server for remote development with Claude Code + tmux
#
# Bootstrap process:
#   1. Boot Hetzner server into rescue mode (Linux 64-bit)
#   2. Run: make hetzner/bootstrap0 NIXADDR=<ip>
#   3. After reboot: make hetzner/bootstrap NIXADDR=<ip>
#   4. Connect: ssh hetzner-dev (uses ~/.ssh config)

{
  imports = [
    ./hardware/hetzner-dev.nix
    ../modules/cachix.nix
    ../modules/secrets.nix
    ../modules/automatic-nix-gc.nix
    ../modules/nixos-auto-update.nix
  ];

  # Latest kernel for best hardware support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use systemd-boot for UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Hostname
  networking.hostName = "hetzner-dev";

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
    minFreeGB = 50;          # Trigger GC during builds below 50GB
    maxFreeGB = 100;         # Target 100GB after build-time GC
    scheduledThresholdGB = 50; # Daily check: GC if below 50GB
    keepDays = 14;           # Keep generations from last 14 days
  };

  # Automatic NixOS updates from git repository
  services.nixosAutoUpdate = {
    enable = true;
    flake = "github:javdl/nixos-config#hetzner-dev";
    dates = "04:00";                # Check at 4 AM
    randomizedDelaySec = "30m";     # Random delay up to 30 min
    allowReboot = false;            # Don't auto-reboot
    # For private repos, configure sshKeySecret after setting up sops
    # sshKeySecret = "github-deploy-key";
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = _: true;

  # Networking - dual stack (IPv4 via DHCP + static IPv6)
  networking.useDHCP = true;
  networking.interfaces.enp1s0.ipv6.addresses = [{
    address = "2a01:4f8:1c1f:ad3c::1";
    prefixLength = 64;
  }];
  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = "enp1s0";
  };

  # Firewall - base config (Tailscale settings added below)
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];  # SSH on public IP

  # SSH daemon - key-only auth for security
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";  # Allow root with key for initial setup
      KbdInteractiveAuthentication = false;
    };
  };

  # Don't require password for sudo (convenient for remote dev)
  security.sudo.wheelNeedsPassword = false;

  # Immutable users (passwords managed via config)
  users.mutableUsers = false;

  # Docker for containerized development
  virtualisation.docker.enable = true;

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
    # Auth key file - create this file with your Tailscale auth key
    # Generate at: https://login.tailscale.com/admin/settings/keys
    # Use a reusable key with "Reusable" and optionally "Ephemeral" for servers
    authKeyFile = "/etc/tailscale/authkey";
    # Extra flags for tailscale up
    extraUpFlags = [
      "--ssh"                    # Enable Tailscale SSH
      "--accept-routes"          # Accept routes from other nodes
      "--accept-dns=false"       # Don't override DNS (use system DNS)
    ];
    # Use exit node if needed (uncomment and set to exit node hostname)
    # extraUpFlags = [ "--ssh" "--exit-node=<exit-node>" ];
  };

  # Allow Tailscale traffic through firewall
  networking.firewall = {
    # Trust Tailscale interface
    trustedInterfaces = [ "tailscale0" ];
    # Allow Tailscale UDP port
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  # This value determines the NixOS release
  system.stateVersion = "25.05";
}
