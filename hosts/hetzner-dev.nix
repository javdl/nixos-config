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

    # Garbage collection
    gc = {
      automatic = true;
      randomizedDelaySec = "14m";
      options = "--delete-older-than 30d";
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = _: true;

  # Networking - Hetzner typically uses static IP or DHCP on main interface
  networking.useDHCP = false;
  networking.interfaces.eth0.useDHCP = true;  # Adjust interface name as needed

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];  # SSH only by default
    # Add more ports as needed: 80 443 for web, etc.
  };

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
  ];

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";

  # System limits for development workloads
  boot.kernel.sysctl = {
    # Increase inotify limits for file watching (Claude Code, IDEs)
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;

    # Increase file descriptor limits
    "fs.file-max" = 2097152;

    # Network optimizations
    "net.core.somaxconn" = 65535;
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

  # Tailscale for easy secure access (optional - enable with tailscale up)
  services.tailscale.enable = true;

  # This value determines the NixOS release
  system.stateVersion = "25.05";
}
