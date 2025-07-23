{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  # Import shared configuration
  shared = import ../shared-home-manager.nix {
    inherit isWSL inputs pkgs lib isDarwin isLinux;
  };

  # Use shared manpager
  manpager = shared.manpager;

in {
  home.stateVersion = "18.09";

  xdg.enable = true;

  home.packages = [
    pkgs.cachix
    pkgs.google-chrome
    pkgs.htop
    pkgs.neofetch
    pkgs.tailscale
    pkgs.vscodium # gives a blank screen on bare metal install > Electron apps with Nvidia card in Wayland will. Either switch to X11 or use Integrated GPU from AMD or Intel and it will load fine
  ] ++ (lib.optionals isDarwin [
    # This is automatically setup on Linux
    pkgs.cachix
    pkgs.tailscale
  ]) ++ (lib.optionals (isLinux && !isWSL) [
    pkgs.chromium
    pkgs.firefox-devedition
    pkgs.zathura
    pkgs.xfce.xfce4-terminal
    pkgs.libwacom
    pkgs.libinput
    pkgs.bitwarden-cli
    pkgs.bitwarden-menu # Dmenu/rofi frontend
    pkgs.tailscale-systray
  ]);

  home.sessionVariables = shared.sessionVariables;

  home.file.".gdbinit".source = ./gdbinit;
  home.file.".inputrc".source = ./inputrc;

  xdg.configFile = {
    "mpd/mpd.conf".text = builtins.readFile ./mpd/mpd.conf;
  };

  dconf.settings = shared.dconfSettings // {
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
  };

  programs.gpg.enable = !isDarwin;

  programs.bash = {
    enable = true;
    shellOptions = [];
    historyControl = [ "ignoredups" "ignorespace" ];
    initExtra = builtins.readFile ./bashrc;

    shellAliases = shared.shellAliases;
  };

  programs.direnv= {
    enable = true;
    enableBashIntegration = true; # see note on other shells below
    nix-direnv.enable = true;

    config = shared.direnvConfig;
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = lib.strings.concatStrings (lib.strings.intersperse "\n" ([
      (builtins.readFile ./config.fish)
      "set -g SHELL ${pkgs.fish}/bin/fish"
    ]));

    shellAliases = shared.shellAliases;

    plugins = shared.fishPlugins;
  };

  programs.kitty = {
    enable = !isWSL;
    extraConfig = builtins.readFile ./kitty;
  };

  xresources.extraConfig = builtins.readFile ./Xresources;

  home.pointerCursor = lib.mkIf (isLinux && !isWSL) {
    name = "Vanilla-DMZ";
    package = pkgs.vanilla-dmz;
    size = 128;
    x11.enable = true;
  };
}
