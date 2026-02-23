{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  # Import shared configuration
  shared = import ../shared-home-manager.nix {
    inherit isWSL inputs pkgs lib isDarwin isLinux;
  };
in {
  # Home-manager state version
  home.stateVersion = "25.11";

  xdg.enable = true;

  #---------------------------------------------------------------------
  # Packages - Minimal set for CI runner (CI tools come from system-level module)
  #---------------------------------------------------------------------

  home.packages = with pkgs; [
    bat
    curl
    fd
    fzf
    git
    htop
    jq
    ripgrep
    tmux
    tree
    unzip
    wget
    zip
  ];

  #---------------------------------------------------------------------
  # Programs
  #---------------------------------------------------------------------

  programs.bash = {
    enable = true;
    shellOptions = [];
    historyControl = [ "ignoredups" "ignorespace" ];
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = shared.shellAliases;
  };

  programs.git = {
    enable = true;
    userName = "GitHub Runner";
    userEmail = "runner@fuww.dev";
    extraConfig = {
      color.ui = true;
      core.askPass = "";
      push.default = "tracking";
      push.autoSetupRemote = true;
      init.defaultBranch = "main";
    };
  };

  programs.tmux = {
    enable = true;
    terminal = "xterm-256color";
    shortcut = "b";
    secureSocket = false;
    mouse = true;
  };

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    defaultEditor = true;
  };
}
