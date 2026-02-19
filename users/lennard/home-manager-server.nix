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
    userName = "Lennard Minderhoud";
    userEmail = "lennard@minderhoud.nl";
    signing = {
      key = null;
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
      github.user = "lminderhoud";
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
      # Rose Pine Dawn
      set -g status-bg "#faf4ed"
      set -g status-fg "#575279"

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

  programs.helix = {
    enable = true;
    defaultEditor = false;  # Keep nvim as EDITOR

    settings = {
      theme = "rose_pine_dawn";

      editor = {
        line-number = "relative";
        cursorline = true;
        color-modes = true;
        true-color = true;
        bufferline = "multiple";
        gutters = ["diagnostics" "spacer" "line-numbers" "spacer" "diff"];

        cursor-shape = {
          insert = "bar";
          normal = "block";
          select = "underline";
        };

        file-picker = {
          hidden = false;
        };

        statusline = {
          left = ["mode" "spinner" "file-name" "file-modification-indicator"];
          center = [];
          right = ["diagnostics" "selections" "register" "position" "file-encoding"];
          separator = "│";
        };

        indent-guides = {
          render = true;
          character = "│";
        };

        lsp = {
          display-messages = true;
          display-inlay-hints = true;
        };

        soft-wrap = {
          enable = true;
        };
      };

      keys = {
        normal = {
          space = {
            f = "file_picker";
            b = "buffer_picker";
            s = "symbol_picker";
            "/" = "global_search";
          };
          C-s = ":w";
        };
        insert = {
          C-s = ":w";
        };
      };
    };

    languages = {
      language = [
        {
          name = "nix";
          auto-format = true;
          formatter.command = "nixfmt";
        }
        {
          name = "rust";
          auto-format = true;
        }
        {
          name = "elixir";
          auto-format = true;
        }
        {
          name = "python";
          auto-format = true;
        }
        {
          name = "typescript";
          auto-format = true;
        }
        {
          name = "javascript";
          auto-format = true;
        }
        {
          name = "go";
          auto-format = true;
        }
      ];
    };
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

      # Rose Pine Dawn colors for zsh syntax highlighting
      typeset -gA ZSH_HIGHLIGHT_STYLES
      ZSH_HIGHLIGHT_STYLES[comment]="fg=#9893a5"
      ZSH_HIGHLIGHT_STYLES[alias]="fg=#56949f"
      ZSH_HIGHLIGHT_STYLES[suffix-alias]="fg=#56949f"
      ZSH_HIGHLIGHT_STYLES[global-alias]="fg=#56949f"
      ZSH_HIGHLIGHT_STYLES[function]="fg=#d7827e"
      ZSH_HIGHLIGHT_STYLES[command]="fg=#56949f"
      ZSH_HIGHLIGHT_STYLES[precommand]="fg=#56949f,italic"
      ZSH_HIGHLIGHT_STYLES[autodirectory]="fg=#ea9d34,italic"
      ZSH_HIGHLIGHT_STYLES[single-hyphen-option]="fg=#ea9d34"
      ZSH_HIGHLIGHT_STYLES[double-hyphen-option]="fg=#ea9d34"
      ZSH_HIGHLIGHT_STYLES[back-quoted-argument]="fg=#907aa9"
      ZSH_HIGHLIGHT_STYLES[builtin]="fg=#d7827e"
      ZSH_HIGHLIGHT_STYLES[reserved-word]="fg=#d7827e"
      ZSH_HIGHLIGHT_STYLES[hashed-command]="fg=#d7827e"
      ZSH_HIGHLIGHT_STYLES[commandseparator]="fg=#b4637a"
      ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter]="fg=#575279"
      ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter-unquoted]="fg=#575279"
      ZSH_HIGHLIGHT_STYLES[process-substitution-delimiter]="fg=#575279"
      ZSH_HIGHLIGHT_STYLES[back-quoted-argument-delimiter]="fg=#b4637a"
      ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]="fg=#b4637a"
      ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]="fg=#b4637a"
      ZSH_HIGHLIGHT_STYLES[quoted-argument]="fg=#ea9d34"
      ZSH_HIGHLIGHT_STYLES[single-quoted-argument]="fg=#ea9d34"
      ZSH_HIGHLIGHT_STYLES[double-quoted-argument]="fg=#ea9d34"
      ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]="fg=#ea9d34"
      ZSH_HIGHLIGHT_STYLES[rc-quote]="fg=#ea9d34"
      ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]="fg=#575279"
      ZSH_HIGHLIGHT_STYLES[assign]="fg=#575279"
      ZSH_HIGHLIGHT_STYLES[redirection]="fg=#575279"
      ZSH_HIGHLIGHT_STYLES[named-fd]="fg=#575279"
      ZSH_HIGHLIGHT_STYLES[numeric-fd]="fg=#575279"
      ZSH_HIGHLIGHT_STYLES[arg0]="fg=#575279"
      ZSH_HIGHLIGHT_STYLES[default]="fg=#575279"
      ZSH_HIGHLIGHT_STYLES[unknown-token]="fg=#b4637a,bold"

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

  # Claude Code statusline (Rose Pine themed)
  home.file.".claude/statusline-command.sh" = {
    source = ../claude-statusline.sh;
    executable = true;
  };

  # Set up Claude Code statusline in settings.json (merges, doesn't overwrite)
  home.activation.claudeStatusline = lib.hm.dag.entryAfter ["writeBoundary"] ''
    SETTINGS_FILE="$HOME/.claude/settings.json"
    $DRY_RUN_CMD mkdir -p "$HOME/.claude"
    if [ -f "$SETTINGS_FILE" ]; then
      $DRY_RUN_CMD ${pkgs.jq}/bin/jq '.statusLine = {"type": "command", "command": "bash ~/.claude/statusline-command.sh"}' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    else
      echo '{"statusLine": {"type": "command", "command": "bash ~/.claude/statusline-command.sh"}}' > "$SETTINGS_FILE"
    fi
  '';

  # Ensure ~/.ssh directory exists for agent socket symlink
  home.file.".ssh/.keep".text = "";
}
