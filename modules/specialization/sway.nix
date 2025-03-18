# Sway (Wayland Compositor)
{ pkgs, lib, ... }: {
  specialisation.sway.configuration = {
    # We need an XDG portal for various applications to work properly
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
      config.common.default = "*";
    };

    # Enable Sway window manager
    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true; # so that gtk works properly
      extraPackages = with pkgs; [
        swaylock
        swayidle
        wl-clipboard
        mako # notification daemon
        alacritty # terminal
        wofi # application launcher
        waybar # status bar
      ];
    };

    # Configure display manager
    services.xserver = {
      enable = true;
      displayManager = {
        gdm = {
          enable = lib.mkForce true;
          wayland = true;
        };
        defaultSession = "sway";
      };
    };

    # Set environment variables for better Wayland compatibility
    environment.sessionVariables = {
      # Hint electron apps to use Wayland
      NIXOS_OZONE_WL = "1";
      # Toolkit-specific
      GDK_BACKEND = "wayland";
      QT_QPA_PLATFORM = "wayland";
      SDL_VIDEODRIVER = "wayland";
      # For Java applications
      _JAVA_AWT_WM_NONREPARENTING = "1";
    };
  };
}
