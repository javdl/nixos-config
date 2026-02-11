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
    zed-editor        # Remote dev server for local Zed connections via SSH

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
    userName = "Jeevan";
    userEmail = "jeevan@fashionunited.com";
    signing = {
      key = null;  # TODO: Add GPG key if using signing
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
      github.user = "jeevanfu";
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
    settings = builtins.fromTOML (builtins.readFile ../joost/starship.toml);
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

    shellAliases = shared.shellAliases;

    initContent = ''
      export GPG_TTY=$(tty)

      # Force block cursor
      echo -ne '\e[2 q'
      preexec() { echo -ne '\e[2 q' }
      precmd() { echo -ne '\e[2 q' }

      # Fix insecure completion files
      autoload -Uz compinit
      if [[ -n "$(find "$HOME/.zcompdump" -mtime +1 2>/dev/null)" ]]; then
        compinit
      else
        compinit -C
      fi
      zstyle ':completion:*' use-cache on
      zstyle ':completion:*' cache-path "$HOME/.zcompcache"
      skip_global_compinit=1

      # SSH agent: prefer forwarded agent, fall back to systemd agent
      if [[ -n "$SSH_AUTH_SOCK" && -S "$SSH_AUTH_SOCK" ]]; then
        ln -sf "$SSH_AUTH_SOCK" ~/.ssh/ssh_auth_sock 2>/dev/null
      elif [[ -S "$XDG_RUNTIME_DIR/ssh-agent" ]]; then
        export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent"
      fi

      # Rose Pine colors for zsh syntax highlighting
      typeset -gA ZSH_HIGHLIGHT_STYLES
      ZSH_HIGHLIGHT_STYLES[comment]="fg=#6e6a86"
      ZSH_HIGHLIGHT_STYLES[alias]="fg=#9ccfd8"
      ZSH_HIGHLIGHT_STYLES[suffix-alias]="fg=#9ccfd8"
      ZSH_HIGHLIGHT_STYLES[global-alias]="fg=#9ccfd8"
      ZSH_HIGHLIGHT_STYLES[function]="fg=#ebbcba"
      ZSH_HIGHLIGHT_STYLES[command]="fg=#9ccfd8"
      ZSH_HIGHLIGHT_STYLES[precommand]="fg=#9ccfd8,italic"
      ZSH_HIGHLIGHT_STYLES[autodirectory]="fg=#f6c177,italic"
      ZSH_HIGHLIGHT_STYLES[single-hyphen-option]="fg=#f6c177"
      ZSH_HIGHLIGHT_STYLES[double-hyphen-option]="fg=#f6c177"
      ZSH_HIGHLIGHT_STYLES[back-quoted-argument]="fg=#c4a7e7"
      ZSH_HIGHLIGHT_STYLES[builtin]="fg=#ebbcba"
      ZSH_HIGHLIGHT_STYLES[reserved-word]="fg=#ebbcba"
      ZSH_HIGHLIGHT_STYLES[hashed-command]="fg=#ebbcba"
      ZSH_HIGHLIGHT_STYLES[commandseparator]="fg=#eb6f92"
      ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter-unquoted]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[process-substitution-delimiter]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[back-quoted-argument-delimiter]="fg=#eb6f92"
      ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]="fg=#eb6f92"
      ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]="fg=#eb6f92"
      ZSH_HIGHLIGHT_STYLES[quoted-argument]="fg=#f6c177"
      ZSH_HIGHLIGHT_STYLES[single-quoted-argument]="fg=#f6c177"
      ZSH_HIGHLIGHT_STYLES[double-quoted-argument]="fg=#f6c177"
      ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]="fg=#f6c177"
      ZSH_HIGHLIGHT_STYLES[rc-quote]="fg=#f6c177"
      ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[assign]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[redirection]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[named-fd]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[numeric-fd]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[arg0]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[default]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[unknown-token]="fg=#eb6f92,bold"

      # Claude alias fix for Zellij
      alias cc="SHELL=/bin/bash VSCODE_PID= VSCODE_CWD= TERM_PROGRAM= command claude"
      claude() {
        SHELL=/bin/bash VSCODE_PID= VSCODE_CWD= TERM_PROGRAM= command claude "$@"
      }
    '';

    envExtra = ''
      if [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
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
  services.ssh-agent = lib.mkIf isLinux {
    enable = true;
    enableFishIntegration = false;
    enableZshIntegration = false;
    enableBashIntegration = false;
  };

  # Ensure ~/.ssh directory exists for agent socket symlink
  home.file.".ssh/.keep".text = "";
}
