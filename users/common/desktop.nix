# Common desktop environment configuration
{ config, lib, pkgs, isDarwin, isLinux, isWSL, ... }:

let
  # Default GNOME dconf settings
  defaultGnomeSettings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      enable-hot-corners = false;
    };

    "org/gnome/desktop/wm/preferences" = {
      button-layout = "appmenu:minimize,maximize,close";
    };

    "org/gnome/shell" = {
      disable-user-extensions = false;
      enabled-extensions = [
        "user-theme@gnome-shell-extensions.gcampax.github.com"
        "dash-to-dock@micxgx.gmail.com"
      ];
    };
  };

in {
  # Enable both settings only on Linux desktop (not WSL)
  config = lib.mkIf (isLinux && !isWSL) {
    # Dconf settings
    dconf.settings = defaultGnomeSettings;

    # GNOME extensions
    home.packages = with pkgs.gnomeExtensions; [
      user-themes
      dash-to-dock
    ];
  };
}