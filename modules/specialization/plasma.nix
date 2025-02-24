# KDE Plasma (Wayland)
{ pkgs, lib, ... }: {
  specialisation.plasma.configuration = {
    services.xserver.enable = true;
    services.displayManager = {
      gdm.enable = lib.mkForce false;
      sddm.enable = lib.mkForce true;
      sddm.wayland.enable = true;
    };
    services.desktopManager.plasma6.enable = true;
  };
}
