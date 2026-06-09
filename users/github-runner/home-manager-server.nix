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
    initExtra = ''
      ${shared.ntmShellInit.bash}
    '';
  };

  programs.zsh = {
    enable = true;
    dotDir = config.home.homeDirectory; # 26.05: pin legacy ~/.zshrc location
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = shared.shellAliases;

    initContent = ''
      ${shared.ntmShellInit.zsh}
    '';
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      ${shared.ntmShellInit.fish}
    '';
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "GitHub Runner";
      user.email = "runner@fuww.dev";
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
    withRuby = false; # 26.05: adopt new default (no ruby provider)
    withPython3 = false;
    viAlias = true;
    vimAlias = true;
    defaultEditor = true;
  };
}
