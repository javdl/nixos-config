{ config, lib, pkgs, ... }:

{
  # Allow unfree packages globally
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = _: true;

  # NixOS-specific settings (not applicable to Darwin)
  # Only apply timezone and locale settings on Linux systems
  time.timeZone = lib.mkIf pkgs.stdenv.isLinux "Europe/Amsterdam";

  i18n = lib.mkIf pkgs.stdenv.isLinux {
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
