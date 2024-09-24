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

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernel.sysctl."net.ipv4.ip_forward" = true;
  virtualisation.docker.enable = true;

  networking.hostName = "fu137-4090-ML"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

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

  # # Enable the X11 windowing system.
  # services.xserver.enable = true;

  # # Enable the GNOME Desktop Environment.
  # services.xserver.displayManager.gdm.enable = true;
  # services.xserver.desktopManager.gnome.enable = true;

  # # Configure keymap in X11
  # services.xserver = {
  #   layout = "us";
  #   xkbVariant = "";
  # };

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

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = _: true;

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

  es.gitlab-runner = {
        enable = true;
            services= {
                  # runner for building in docker via host's nix-daemon
                        # nix store will be readable in runner, might be insecure
                              nix = with lib;{
                                      # File should contain at least these two variables:
                                              # `CI_SERVER_URL`
                                                      # `REGISTRATION_TOKEN`
                                                              registrationConfigFile = toString ./path/to/ci-env; # 2
                                                                      dockerImage = "alpine";
                                                                              dockerVolumes = [
                                                                                        "/nix/store:/nix/store:ro"
                                                                                                  "/nix/var/nix/db:/nix/var/nix/db:ro"
                                                                                                            "/nix/var/nix/daemon-socket:/nix/var/nix/daemon-socket:ro"
                                                                                                                    ];
                                                                                                                            dockerDisableCache = true;
                                                                                                                                    preBuildScript = pkgs.writeScript "setup-container" ''
                                                                                                                                              mkdir -p -m 0755 /nix/var/log/nix/drvs
                                                                                                                                                        mkdir -p -m 0755 /nix/var/nix/gcroots
                                                                                                                                                                  mkdir -p -m 0755 /nix/var/nix/profiles
                                                                                                                                                                            mkdir -p -m 0755 /nix/var/nix/temproots
                                                                                                                                                                                      mkdir -p -m 0755 /nix/var/nix/userpool
                                                                                                                                                                                                mkdir -p -m 1777 /nix/var/nix/gcroots/per-user
                                                                                                                                                                                                          mkdir -p -m 1777 /nix/var/nix/profiles/per-user
                                                                                                                                                                                                                    mkdir -p -m 0755 /nix/var/nix/profiles/per-user/root
                                                                                                                                                                                                                              mkdir -p -m 0700 "$HOME/.nix-defexpr"
                                                                                                                                                                                                                                        . ${pkgs.nix}/etc/profile.d/nix-daemon.sh
                                                                                                                                                                                                                                                  ${pkgs.nix}/bin/nix-channel --add https://nixos.org/channels/nixos-20.09 nixpkgs # 3
                                                                                                                                                                                                                                                            ${pkgs.nix}/bin/nix-channel --update nixpkgs
                                                                                                                                                                                                                                                                      ${pkgs.nix}/bin/nix-env -i ${concatStringsSep " " (with pkgs; [ nix cacert git openssh ])}
                                                                                                                                                                                                                                                                              '';
                                                                                                                                                                                                                                                                                      environmentVariables = {
                                                                                                                                                                                                                                                                                                ENV = "/etc/profile";
                                                                                                                                                                                                                                                                                                          USER = "root";
                                                                                                                                                                                                                                                                                                                    NIX_REMOTE = "daemon";
                                                                                                                                                                                                                                                                                                                              PATH = "/nix/var/nix/profiles/default/bin:/nix/var/nix/profiles/default/sbin:/bin:/sbin:/usr/bin:/usr/sbin";
                                                                                                                                                                                                                                                                                                                                        NIX_SSL_CERT_FILE = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt";
                                                                                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                                                                                                        tagList = [ "nix" ];
                                                                                                                                                                                                                                                                                                                                                              };
                                                                                                                                                                                                                                                                                                                                                                  };
                                                                                                                                                                                                                                                                                                                                                                    };
  }

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?

}
