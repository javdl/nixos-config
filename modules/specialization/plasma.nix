# KDE Plasma (Wayland)
{ pkgs, lib, ... }: {
  specialisation.plasma.configuration = {
    services.xserver = {
      enable = true;
      displayManager = {
        gdm.enable = lib.mkForce false;
        sddm = {
          enable = lib.mkForce true;
          wayland.enable = true;
        };
      };
    };
    services.desktopManager.plasma6.enable = true;
  };
}
