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
