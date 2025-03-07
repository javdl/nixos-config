# Common system-level configuration for users
{ config, pkgs, lib, ... }:

{
  # Link necessary directories for fish shell completion
  environment.pathsToLink = [ "/share/fish" ];

  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  # Enable fish as system shell
  programs.fish.enable = true;

  # Enable experimental features for flakes support
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  # Common system packages
  environment.systemPackages = with pkgs; [
    # Core utilities
    curl
    wget
    git
    vim
    neovim
    htop
    
    # Basic development tools
    gnumake
    gcc
    
    # System tools
    acpi
    lm_sensors
    usbutils
    pciutils
  ];
  
  # Common system services
  services = {
    # Enable SSH server
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
    };
    
    # Time synchronization
    timesyncd.enable = true;
  };
  
  # Security settings
  security = {
    sudo.wheelNeedsPassword = true;
    
    # PAM settings
    pam = {
      services = {
        login.enableGnomeKeyring = true;
        gdm.enableGnomeKeyring = true;
      };
    };
  };
}