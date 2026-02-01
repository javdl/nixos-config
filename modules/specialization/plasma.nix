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
      desktopManager.plasma6.enable = true;
    };
    
    # Force KDE's ssh-askpass over Seahorse's
    programs.ssh.askPassword = lib.mkForce "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";
  };
}
