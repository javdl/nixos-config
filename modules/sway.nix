# Does not support NVIDIA proprietary drivers,
# use nouveau instead
# other sample https://gist.github.com/kborling/76805ade81ac5bfdd712df294208c878
# tested with nvidia open, still got the warning in sway.
# looks like you have to start it with --unsupported-gpu regardless of the driver
# you use or that the monitor is connected to the iGPU.

{ config, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    # the minimum
    grim # screenshot functionality
    slurp # screenshot functionality
    wl-clipboard # wl-copy and wl-paste for copy/paste from stdin / stdout
    cliphist # clipboard history manager for Wayland
    mako # notification system developed by swaywm maintainer
    # the rest
    swayidle # idle management
    swaylock # screen locker
    wf-recorder # screen recorder
    wofi # dmenu replacement
    # kanshi # display configuration -  allows you to define output profiles that are automatically enabled and disabled on hotplug. For instance, this can be used to turn a laptop's internal screen off when docked.
    # grim # screenshot utility
    # slurp # select region for screenshot
    # gtk3 # fixes issue where Kitty doesnt start after logging in to Hyprland.

  ];

  # Enable the gnome-keyring secrets vault.
  # Will be exposed through DBus to programs willing to store secrets.
  services.gnome.gnome-keyring.enable = true;

  # enable sway window manager
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraSessionCommands = ''
      export SDL_VIDEODRIVER=wayland
      export QT_QPA_PLATFORM=wayland
      export QT_WAYLAND_DISABLE_WINDOWDECORATION="1"
      export _JAVA_AWT_WM_NONREPARENTING=1
      export MOZ_ENABLE_WAYLAND=1
    '';
  };

  # Clipboard history manager (cliphist) - sway config drop-in
  # Default sway config includes /etc/sway/config.d/*
  environment.etc."sway/config.d/cliphist.conf".text = ''
    # Start clipboard listener on sway startup
    exec wl-paste --watch cliphist store

    # Super+V to browse clipboard history via wofi
    bindsym Mod4+v exec cliphist list | wofi --dmenu | cliphist decode | wl-copy

    # Super+Shift+V to delete an entry from clipboard history
    bindsym Mod4+Shift+v exec cliphist list | wofi --dmenu | cliphist delete
  '';

# older config, for ref:
#     programs.sway = {
#     enable = false;
#     wrapperFeatures.gtk = true; # so that gtk works properly
#     extraPackages = with pkgs; [
#       swaylock
#       swayidle
#       wl-clipboard
#       wf-recorder
#       mako # notification daemon
#       grim
#       #kanshi
#       slurp
#       #dmenu # Dmenu is the default in the config but i recommend wofi since its wayland native
#       wofi
#       gtk3 # fixes issue where Kitty doesnt start after logging in to Hyprland.
#     ];
#     extraSessionCommands = ''
#       export SDL_VIDEODRIVER=wayland
#       export QT_QPA_PLATFORM=wayland
#       export QT_WAYLAND_DISABLE_WINDOWDECORATION="1"
#       export _JAVA_AWT_WM_NONREPARENTING=1
#       export MOZ_ENABLE_WAYLAND=1
#     '';
#   };

}
