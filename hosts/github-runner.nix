{ config, pkgs, lib, ... }: {
  imports = [
    ./hardware/vm-intel.nix
    ../modules/base-config.nix
    ../modules/github-actions-runner.nix
    ../modules/cachix.nix
  ];

  # Enable the GitHub Actions runner packages module
  services.github-actions-runner.enable = true;

  # Be careful updating this.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  nix = {
    # use unstable nix so we can access flakes
    package = pkgs.nixVersions.latest;
    extraOptions = ''
      experimental-features = nix-command flakes
      keep-outputs = true
      keep-derivations = true
    '';

    # Automate garbage collection / Make sure boot does not get full
    gc = {
      automatic = true;
      randomizedDelaySec = "14m";
      options = "--delete-older-than 30d";
    };
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # VMware, Parallels both only support this being 0 otherwise you see
  # "error switching console mode" on boot.
  boot.loader.systemd-boot.consoleMode = "0";

  # Define your hostname.
  networking.hostName = "github-runner";

  # Set your time zone.
  time.timeZone = "UTC";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  networking.useDHCP = false;

  # Don't require password for sudo
  security.sudo.wheelNeedsPassword = false;

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Disable the firewall since we're in a VM and we want to make it
  # easy to visit stuff in here. We only use NAT networking anyways.
  networking.firewall.enable = false;

  # Define a user account.
  users.mutableUsers = false;

  # GitHub Actions specific optimizations
  boot.kernel.sysctl = {
    # Increase inotify limits for file watching
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;
    
    # Increase file descriptor limits
    "fs.file-max" = 2097152;
    
    # Network optimizations
    "net.core.somaxconn" = 65535;
    "net.ipv4.tcp_max_syn_backlog" = 65535;
  };

  # System limits for runners
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

  # Disable unnecessary services for a runner
  services.xserver.enable = false;
  services.printing.enable = false;
  sound.enable = false;
  
  # Enable useful services for CI/CD
  services.nscd.enable = true;
  services.dbus.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  system.stateVersion = "25.05";
}