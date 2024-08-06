# Hyprland does not play nice with virtual machines, do not use it in a VM.
{pkgs, ...}: let
  flake-compat = builtins.fetchTarball {
    # url = "https://github.com/edolstra/flake-compat/archive/master.tar.gz";
    # sha256 = "0m9grvfsbwmvgwaxvdzv6cmyvjnlww004gfxjvcl806ndqaxzy4j";
    url = "https://github.com/edolstra/flake-compat/archive/12c64ca55c1014cdc1b16ed5a804aa8576601ff2.tar.gz";
    sha256 = "0jm6nzb83wa6ai17ly9fzpqc40wg1viib8klq8lby54agpl213w5";
    };

  hyprland = (import flake-compat {
    # we're not using pkgs.fetchgit as that requires a hash to be provided
    src = builtins.fetchGit {
      url = "https://github.com/hyprwm/Hyprland.git";
      submodules = true;
    };
  }).defaultNix;
in {
  programs.hyprland = {
    enable = true;
    package = hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
  };
}