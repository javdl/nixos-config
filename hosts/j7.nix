# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware/j7.nix
      #../modules/nvidia-drivers.nix
      ../modules/amd-drivers.nix # IGPU
      ../modules/common-pc-ssd.nix
      #../modules/hyprland.nix
      #../modules/sway.nix
      # ../modules/programs.nix https://github.com/gpskwlkr/nixos-hyprland-flake/tree/main
      ./bare-metal-shared-linux.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Setup keyfile
  boot.initrd.secrets = {
    "/crypto_keyfile.bin" = null;
  };

  # Enable swap on luks
  boot.initrd.luks.devices."luks-0d8223a5-7ee5-4d19-86e1-f7a9aa5b89f8".device = "/dev/disk/by-uuid/0d8223a5-7ee5-4d19-86e1-f7a9aa5b89f8";
  boot.initrd.luks.devices."luks-0d8223a5-7ee5-4d19-86e1-f7a9aa5b89f8".keyFile = "/crypto_keyfile.bin";

  boot.extraModprobeConfig = ''
    options kvm_intel nested=1
    options kvm_intel emulate_invalid_guest_state=0
    options kvm ignore_msrs=1
  '';


  networking.hostName = "j7"; # Define your hostname.

  # Interfaces are these on my AMD X670E >> Do not use DHCP, use network-manager instead

  # networking.interfaces.enp9s0.useDHCP = true;
  # networking.interfaces.enp10s0.useDHCP = true;
  # networking.interfaces.wlp8s0.useDHCP = true;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  systemd.network.wait-online.anyInterface = true; # block for no more than one interface
  networking.dhcpcd.wait = "background";
  
  # Set your time zone.
  time.timeZone = "Europe/Amsterdam";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "nl_NL.UTF-8";
    LC_IDENTIFICATION = "nl_NL.UTF-8";
    LC_MEASUREMENT = "nl_NL.UTF-8";
    LC_MONETARY = "nl_NL.UTF-8";
    LC_NAME = "nl_NL.UTF-8";
    LC_NUMERIC = "nl_NL.UTF-8";
    LC_PAPER = "nl_NL.UTF-8";
    LC_TELEPHONE = "nl_NL.UTF-8";
    LC_TIME = "nl_NL.UTF-8";
  };

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
    description = "Joost van der Laan";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [
      firefox-devedition
      gnumake
      pavucontrol
    ];
  };

  # enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # # Allow unfree packages
  # nixpkgs.config.allowUnfree = true;
  # nixpkgs.config.allowUnfreePredicate = _: true;

  nixpkgs.config.permittedInsecurePackages = [
            #"openssl-1.1.1w" # For Sublimetext4, REMOVE WHEN OPENSSL 1.1 DOES NOT GET SECURITY UPDATES ANYMORE
            #"electron-25.9.0"
              ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    firefox
    #github-runner
    gitlab-runner
    #  wget

    # Hyprland
    xdg-desktop-portal-hyprland
    # xwayland Crashes in Sway and i3 when running chromium?
    # must have
    libdisplay-info
    libnotify # for notify-send
    glib
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
    hyprlock # lockscreen Not in nixos pkgs
    hypridle # idle behaviour Not in nixos pkgs
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
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

    services = {
    github-runners = {
      # We suggest using the fine-grained PATs 
        # https://search.nixos.org/options?channel=24.05&show=services.github-runners.%3Cname%3E.tokenFile&from=0&size=50&sort=relevance&type=packages&query=services.github-runner
        # The file should contain exactly one line with the token without any newline.
        # https://github.com/settings/personal-access-tokens/new
        # echo -n 'token' > /home/joost/.github-runner-token
        # Give it “Read and Write access to organization/repository self hosted runners”, depending on whether it is organization wide or per-repository.
        # JL: op personal account heb je die niet, daar een classic PAT maken met `manage_runners:org` AND `repo` access.
        # For classic PATs:
        # Make sure the PAT has a scope of admin:org for organization-wide registrations or a scope of repo for a single repository.
        # voor een personal account beide geven. Daar kun je nl. alleen per repo
        # een url instellen, niet voor je hele username. https://github.com/javdl
        # werkt dus niet.
      runner1 = {
        enable = true;
        name = "j7-runner";
        tokenFile = "/home/joost/.github-runner-token";
        url = "https://github.com/javdl/nixos-config";
      };
      runner2 = {
        enable = true;
        name = "j7-runner";
        tokenFile = "/home/joost/.github-runner-token";
        url = "https://github.com/javdl/top200-rs";
      };
      runner99fuww = { # will show in systemctl as github-runner-runner2fuww.service
        enable = true;
        name = "j7-fuww-runner";
        tokenFile = "/home/joost/.fuww-github-runner-token";
        url = "https://github.com/fuww";
      };
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?

}
