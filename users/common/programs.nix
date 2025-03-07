# Common program configurations
{ config, lib, pkgs, isDarwin, isLinux, isWSL, ... }:

{
  # Git configuration
  programs.git = {
    enable = true;
    delta.enable = true;
    lfs.enable = true;
    
    extraConfig = {
      pull.rebase = true;
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
    };
  };
  
  # Kitty terminal configuration
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "JetBrains Mono";
      font_size = 12;
      scrollback_lines = 10000;
      enable_audio_bell = false;
      update_check_interval = 0;
      confirm_os_window_close = 0;
    };
  };
  
  # Alacritty terminal configuration
  programs.alacritty = {
    enable = true;
  };
  
  # Neovim configuration
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };
  
  # XDG user directories configuration
  xdg = {
    enable = true;
    configFile = {
      "electron-flags.conf".source = ../joost/electron-flags.conf;
      "code-flags.conf".source = ../joost/code-flags.conf;
    };
  };
}