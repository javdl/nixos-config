{ config, lib, ... }:

{
  # Allow unfree packages globally
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = _: true;

  # NixOS-specific settings (not applicable to Darwin)
  # Only apply timezone and locale settings on Linux systems
  time = lib.mkIf (config.nixpkgs.hostPlatform.isLinux or false) {
    timeZone = "Europe/Amsterdam";
  };

  i18n = lib.mkIf (config.nixpkgs.hostPlatform.isLinux or false) {
    defaultLocale = "en_US.UTF-8";

    extraLocaleSettings = {
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
  };
}
