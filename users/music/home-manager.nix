# Home Manager configuration for music user
{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  sources = import ../../nix/sources.nix;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in {
  # Import common configurations
  imports = [
    ../common
  ];

  # Home-manager state version
  home.stateVersion = "18.09";

  #---------------------------------------------------------------------
  # User-specific packages
  #---------------------------------------------------------------------
  home.packages = [
    # Basic utilities
    pkgs.google-chrome
    pkgs.neofetch
    pkgs.vscodium 
    
    # Music-related packages could be added here
    pkgs.spotify
    pkgs.audacity
    pkgs.ardour
  ] 
  ++ (lib.optionals isDarwin [
    pkgs.cachix
    pkgs.tailscale
  ]) 
  ++ (lib.optionals (isLinux && !isWSL) [
    pkgs.chromium
    pkgs.firefox-devedition
    pkgs.zathura
    pkgs.xfce.xfce4-terminal
    pkgs.bitwarden-cli
    pkgs.bitwarden-menu
    pkgs.tailscale-systray
  ]);

  #---------------------------------------------------------------------
  # User-specific dotfiles
  #---------------------------------------------------------------------
  
  # MPD configuration
  xdg.configFile = {
    "mpd/mpd.conf".text = builtins.readFile ./mpd/mpd.conf;
  };

  #---------------------------------------------------------------------
  # User-specific GNOME settings
  #---------------------------------------------------------------------
  dconf.settings = {
    "org/gnome/shell" = {
      favorite-apps = [
        "spotify.desktop"
        "firefox.desktop"
        "kitty.desktop"
        "sublimetext4.desktop"
        "org.gnome.Terminal.desktop"
        "org.gnome.Nautilus.desktop"
      ];
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      enable-hot-corners = false;
      scaling-factor = lib.hm.gvariant.mkUint32 2;
    };
    "org/gnome/desktop/wm/preferences" = {
      workspace-names = [ "Main" ];
    };
    "org/gnome/settings-daemon/plugins/color" = {
      night-light-enabled = true;
      night-light-schedule-automatic = true;
    };
    "org/gnome/settings-daemon/plugins/power" = {
      sleep-inactive-ac-type = "nothing";
      power-button-action = "interactive";
    };
  };

  #---------------------------------------------------------------------
  # User-specific program configurations
  #---------------------------------------------------------------------
  
  # Fish shell customization
  programs.fish = {
    interactiveShellInit = lib.strings.concatStrings (lib.strings.intersperse "\n" ([
      "source ${sources.theme-bobthefish}/functions/fish_prompt.fish"
      "source ${sources.theme-bobthefish}/functions/fish_right_prompt.fish"
      "source ${sources.theme-bobthefish}/functions/fish_title.fish"
      (builtins.readFile ./config.fish)
      "set -g SHELL ${pkgs.fish}/bin/fish"
    ]));
    
    plugins = map (n: {
      name = n;
      src = sources.${n};
    }) [
      "fish-fzf"
      "fish-foreign-env"
      "theme-bobthefish"
    ];
  };
  
  # Kitty terminal specific configuration
  programs.kitty = {
    enable = !isWSL;
    extraConfig = builtins.readFile ./kitty;
  };
  
  # X resources
  xresources.extraConfig = builtins.readFile ./Xresources;
}
