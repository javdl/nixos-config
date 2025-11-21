# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
     # <nixos-hardware/common/cpu/amd/raphael/igpu>
      ./hardware/fu137.nix
      ../modules/nvidia-drivers-535.nix
      ../modules/amd-drivers.nix # IGPU
      ../modules/common-pc-ssd.nix
      ../modules/hyprland.nix
      ../modules/sway.nix
      ./bare-metal-shared-linux.nix
    ];

  boot.kernelPackages = pkgs.linuxPackages_latest;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernel.sysctl."net.ipv4.ip_forward" = true; # Docker
  virtualisation.docker.enable = true;

  networking.hostName = "fu137-4090-ML"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.joost = {
    isNormalUser = true;
    description = "joost";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
    #  thunderbird
    gnumake
    ];
  };

  # Install firefox.
  programs.firefox.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
   vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
   wget
   chromium
   glib
    #github-runner
    gitlab-runner
    #  wget

    # Hyprland
    xdg-desktop-portal-hyprland
    # xwayland Crashes in Sway and i3?
    # must have
    libnotify # for notify-send
    mako
    pipewire
    wireplumber
    libsForQt5.polkit-kde-agent # not sure if this is correct
    # qt5-wayland
    libsForQt5.qt5.qtwayland
    libsForQt5.qt5ct
    # qt6-wayland
    qt6.qtwayland
    # useful
    waybar
    font-awesome # waybar icons
    wofi
    hyprpaper # wallpaper
    hyprpicker # color picker
    # hyprlock # lockscreen Not in nixos pkgs
    # hypridle # idle behaviour Not in nixos pkgs
    mpd # best music player in the world
    libglvnd
    lmstudio
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  services = {
    github-runners = {
      runner = {
        enable = true;
        name = "fu137-AMD-RTX4090-runner";
        # We suggest using the fine-grained PATs https://search.nixos.org/options?channel=24.05&show=services.github-runners.%3Cname%3E.tokenFile&from=0&size=50&sort=relevance&type=packages&query=services.github-runner
        # The file should contain exactly one line with the token without any newline.
        # https://github.com/settings/personal-access-tokens/new
        # echo -n 'token' > /home/joost/.fuww-github-runner-token
        # Give it “Read and Write access to organization/repository self hosted runners”, depending on whether it is organization wide or per-repository.
        # JL: op personal account heb je die niet, daar een ouderwetse access token maken met manage_runners:org access.
        tokenFile = "/home/joost/.fuww-github-runner-token";
        url = "https://github.com/fuww";
      };
    };
  };
  #       Th   is value determines the NixOS release from which the default
  #       se   ttings for stateful data, like file locations and database versions
  # on    your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?

}
