# Platform detection and configuration
{ config, lib, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  isDarwin = builtins.match ".*darwin" system != null;
  isLinux = builtins.match ".*linux" system != null;
  isWSL = if isLinux then builtins.pathExists /proc/sys/fs/binfmt_misc/WSLInterop else false;
in {
  # Export these variables for other modules to use
  _module.args = {
    inherit isDarwin isLinux isWSL;
  };

  # Session variables that depend on platform
  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    EDITOR = "vim";
    PAGER = "less -FirSwX";
    MANPAGER = "sh -c 'col -bx | ${pkgs.bat}/bin/bat -l man -p'";
  };

  # Platform-specific settings
  config = lib.mkMerge [
    (lib.mkIf isLinux {
      # Linux-specific settings
      home.pointerCursor = {
        x11.enable = true;
        gtk.enable = true;
        size = 16;
        package = pkgs.gnome.adwaita-icon-theme;
        name = "Adwaita";
      };
    })

    (lib.mkIf (isLinux && !isWSL) {
      # Linux desktop settings (non-WSL)
      services.gpg-agent = {
        enable = true;
        enableSshSupport = true;
        defaultCacheTtl = 1800;
      };
    })
  ];
}