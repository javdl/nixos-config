{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in {
  # Home-manager state version
  home.stateVersion = "25.11";

  xdg.enable = true;

  #---------------------------------------------------------------------
  # Packages - Minimal set for remote development server
  #---------------------------------------------------------------------

  home.packages = with pkgs; [
    # Core CLI tools
    bat
    btop
    curl
    eza
    fd
    fzf
    gh
    git
    git-lfs
    htop
    httpie
    jq
    lazygit
    ripgrep
    rsync
    tmux
    tree
    unzip
    wget
    zip
    watch
    xh              # Modern HTTP client

    # Modern CLI replacements
    delta           # Better git diffs
    tokei           # Code statistics
    dust            # Disk usage analyzer
    procs           # Better ps

    # AI coding tools (claude-code installed via native installer in activation)
    aichat
    amp-cli
    claude-code-router
    codex
    gemini-cli
    opencode

    # Development
    gnumake
    gcc
    nodejs_22
    python3
    poetry
    uv
    rustup
    cargo-generate
    pre-commit

    # DevOps
    cachix
    chezmoi
    devcontainer
    docker-compose
    flyctl
    railway

    # Shell
    starship
    zoxide
  ];

  # Install Claude Code CLI using native installer (always gets latest version)
  home.activation.installClaudeCode = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ! command -v claude &> /dev/null; then
      $DRY_RUN_CMD bash -c "curl -fsSL https://claude.ai/install.sh | bash"
    fi
  '';

  # Sync dotfiles from chezmoi repo (auto-applies on each rebuild)
  home.activation.chezmoiSync = lib.hm.dag.entryAfter ["writeBoundary"] ''
    CHEZMOI_SOURCE="$HOME/.local/share/chezmoi"
    if [ -d "$CHEZMOI_SOURCE" ]; then
      echo "Syncing dotfiles from chezmoi repo..."
      $DRY_RUN_CMD ${pkgs.chezmoi}/bin/chezmoi update || true
    else
      echo "Chezmoi not initialized. Run: chezmoi init --apply https://github.com/javdl/dotfiles.git"
    fi
  '';

  #---------------------------------------------------------------------
  # Programs
  #---------------------------------------------------------------------

  programs.gpg.enable = true;

  programs.bash = {
    enable = true;
    shellOptions = [];
    historyControl = [ "ignoredups" "ignorespace" ];
    initExtra = ''
      # SSH agent: prefer forwarded agent, fall back to systemd agent
      if [[ -n "$SSH_AUTH_SOCK" && -S "$SSH_AUTH_SOCK" ]]; then
        mkdir -p ~/.ssh
        ln -sf "$SSH_AUTH_SOCK" ~/.ssh/ssh_auth_sock 2>/dev/null
      elif [[ -S "$XDG_RUNTIME_DIR/ssh-agent" ]]; then
        export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent"
      fi
    '';
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set -g fish_greeting ""
      starship init fish | source
      zoxide init fish | source

      # SSH agent: prefer forwarded agent, fall back to systemd agent
      if test -n "$SSH_AUTH_SOCK"; and test -S "$SSH_AUTH_SOCK"
        # Forwarded agent is valid, symlink it for tmux persistence
        mkdir -p ~/.ssh
        ln -sf "$SSH_AUTH_SOCK" ~/.ssh/ssh_auth_sock 2>/dev/null
      else if test -S "$XDG_RUNTIME_DIR/ssh-agent"
        set -gx SSH_AUTH_SOCK "$XDG_RUNTIME_DIR/ssh-agent"
      end
    '';
    shellAliases = {
      # Jujutsu aliases
      jd = "jj desc";
      jf = "jj git fetch";
      jn = "jj new";
      jp = "jj git push";
      js = "jj st";

      ll = "eza -la";
      ls = "eza";
      cat = "bat";
    };
  };

  programs.git = {
    enable = true;
    userName = "Joost van der Laan";
    userEmail = "j@jlnw.nl";
    signing = {
      key = "F4B9B085DAC0B0B1";
      signByDefault = false;
    };
    delta = {
      enable = true;
      options = {
        line-numbers = true;
        side-by-side = true;
      };
    };
    aliases = {
      prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(r) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
      root = "rev-parse --show-toplevel";
    };
    extraConfig = {
      branch.autosetuprebase = "always";
      color.ui = true;
      core.askPass = "";
      credential.helper = "store";
      github.user = "javdl";
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
    extraConfig = ''
      set -ga terminal-overrides ",*256col*:Tc"
      set -g status-bg black
      set -g status-fg white

      # OSC 52 clipboard: copies in tmux go to the connecting machine's clipboard over SSH
      set -s set-clipboard on
      set -ga terminal-overrides ",xterm-256color:Ms=\\E]52;c;%p2%s\\7"

      # Propagate SSH agent socket into new tmux sessions
      set -g update-environment "SSH_AUTH_SOCK SSH_CONNECTION DISPLAY"
      if-shell "test -S ~/.ssh/ssh_auth_sock" "set-environment -g SSH_AUTH_SOCK ~/.ssh/ssh_auth_sock"
    '';
  };

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    defaultEditor = true;
    plugins = with pkgs.vimPlugins; [
      claude-code-nvim
      plenary-nvim  # dependency
    ];
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    settings = builtins.fromTOML (builtins.readFile ./starship.toml);
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.jujutsu = {
    enable = true;
  };

  programs.atuin = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    settings = {
      show_tabs = false;
      style = "compact";
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    initContent = ''
      export GPG_TTY=$(tty)

      # SSH agent: prefer forwarded agent, fall back to systemd agent
      if [[ -n "$SSH_AUTH_SOCK" && -S "$SSH_AUTH_SOCK" ]]; then
        ln -sf "$SSH_AUTH_SOCK" ~/.ssh/ssh_auth_sock 2>/dev/null
      elif [[ -S "$XDG_RUNTIME_DIR/ssh-agent" ]]; then
        export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent"
      fi
    '';
  };

  #---------------------------------------------------------------------
  # Services (Linux only)
  #---------------------------------------------------------------------

  services.gpg-agent = lib.mkIf isLinux {
    enable = true;
    pinentryPackage = pkgs.pinentry-tty;
    defaultCacheTtl = 31536000;
    maxCacheTtl = 31536000;
  };

  # SSH agent - persistent local agent so keys survive disconnects/tmux
  # Disable built-in shell integrations — our custom fallback logic in
  # fish/zsh prefers the forwarded agent and falls back to this one.
  services.ssh-agent = lib.mkIf isLinux {
    enable = true;
    enableFishIntegration = false;
    enableZshIntegration = false;
    enableBashIntegration = false;
  };

  # Ensure ~/.ssh directory exists for agent socket symlink
  home.file.".ssh/.keep".text = "";
}
