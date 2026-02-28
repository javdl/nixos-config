{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in {
  # Home-manager state version
  home.stateVersion = "25.11";

  xdg.enable = true;
  xdg.configFile."wezterm/wezterm.lua".text = ''
    local wezterm = require 'wezterm'
    local config = wezterm.config_builder()
    config.scrollback_lines = 50000
    return config
  '';

  # Fixed SSH_AUTH_SOCK path — symlink updated by shell init on each new shell.
  # Because SSH resolves symlinks on every operation, updating the target
  # fixes all shells (including already-running zellij panes).
  home.sessionVariables = {
    SSH_AUTH_SOCK = "$HOME/.ssh/ssh_auth_sock";
  };

  # Cargo-installed binaries (caut, etc.)
  home.sessionPath = [ "$HOME/.cargo/bin" ];

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
    beads-rust        # fast Rust port of beads (br command, aliased as bd)
    beads-viewer      # TUI for beads issue tracking (bv command)
    caam              # Instant auth switching for AI coding subscriptions
    claude-code-router
    codex
    gemini-cli
    destructive-command-guard # Safety hook for AI agents (dcg command)
    grepai            # Semantic code search for AI coding assistants
    ntm               # Named Tmux Manager for AI agent coordination
    opencode
    repo-updater      # GitHub repo sync tool (ru command)
    ubs               # AI-native code quality scanner
    # frankenterm (ft): installed via cargo nightly in activation script below
    # frankensqlite: install via `cargo +nightly install --git https://github.com/Dicklesworthstone/frankensqlite` (requires nightly)
    # frankentui: install via `git clone ... && cargo run -p ftui-demo-showcase` (no Cargo.lock)
  ] ++ (lib.optional (pkgs.cass != null) pkgs.cass) ++ (lib.optional (pkgs.cass-memory != null) pkgs.cass-memory) ++ [

    # Development
    bun
    gnumake
    gcc
    go
    nixd              # Nix language server (for Zed remote dev)
    nodejs_22
    python3
    poetry
    uv
    rustup
    cargo-generate
    pre-commit

    # DevOps
    bitwarden-cli
    cachix
    chezmoi
    cosign
    devcontainer
    docker-compose
    flyctl
    git-crypt
    lazydocker
    railway

    # Shell
    starship
    wezterm
    zellij
    zoxide
  ];

  # Install Claude Code CLI using native installer (always gets latest version)
  home.activation.installClaudeCode = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -f "$HOME/.local/bin/claude" ]; then
      $DRY_RUN_CMD bash -c "curl -fsSL https://claude.ai/install.sh | bash"
    fi
  '';

  # Initialize Rust stable toolchain so cargo/rustc are immediately available
  home.activation.rustupInit = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ! $HOME/.rustup/toolchains/stable-*/bin/cargo --version &>/dev/null 2>&1; then
      $DRY_RUN_CMD rustup default stable
    fi
  '';

  # Install caut (coding agent usage tracker) via cargo nightly
  home.activation.installCaut = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ! $HOME/.cargo/bin/caut --version &>/dev/null; then
      echo "Installing caut (coding agent usage tracker)..."
      $DRY_RUN_CMD bash -c "PKG_CONFIG_PATH='${pkgs.sqlite.dev}/lib/pkgconfig' LIBRARY_PATH='${pkgs.sqlite.out}/lib' rustup run nightly cargo install --git https://github.com/Dicklesworthstone/coding_agent_usage_tracker" || echo "caut install failed (requires rustup nightly + sqlite)"
    fi
  '';

  # Clone Dicklesworthstone repos and install frankenterm (ft)
  # frankenterm workspace has path deps on frankenredis + frankentui as siblings
  home.activation.installFrankenterm = lib.hm.dag.entryAfter ["writeBoundary"] ''
    DW="$HOME/code/Dicklesworthstone"
    $DRY_RUN_CMD mkdir -p "$DW"
    for repo in frankenterm frankenredis frankentui; do
      [ -d "$DW/$repo" ] || $DRY_RUN_CMD ${pkgs.git}/bin/git clone --depth 1 "https://github.com/Dicklesworthstone/$repo" "$DW/$repo"
    done
    if ! $HOME/.cargo/bin/ft --version &>/dev/null; then
      echo "Installing frankenterm (ft)..."
      $DRY_RUN_CMD bash -c '
        PKG_CONFIG_PATH='"'"'${pkgs.openssl.dev}/lib/pkgconfig'"'"' \
        OPENSSL_DIR='"'"'${pkgs.openssl.dev}'"'"' \
        OPENSSL_LIB_DIR='"'"'${pkgs.openssl.out}/lib'"'"' \
        rustup run nightly cargo install --path "'"$DW"'/frankenterm/crates/frankenterm"
      ' || echo "frankenterm install failed (requires rustup nightly + openssl)"
    fi
  '';

  # Set up Agent Mail (MCP agent coordination layer)
  home.activation.setupAgentMail = lib.hm.dag.entryAfter ["writeBoundary"] ''
    AGENT_MAIL_DIR="$HOME/mcp_agent_mail"
    if [ ! -d "$AGENT_MAIL_DIR" ]; then
      echo "Cloning mcp_agent_mail..."
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone --depth 1 \
        https://github.com/Dicklesworthstone/mcp_agent_mail "$AGENT_MAIL_DIR" || echo "agent-mail clone failed"
    fi
    if [ -d "$AGENT_MAIL_DIR" ] && [ ! -d "$AGENT_MAIL_DIR/.venv" ]; then
      echo "Setting up agent-mail venv..."
      $DRY_RUN_CMD bash -c "cd $AGENT_MAIL_DIR && ${pkgs.uv}/bin/uv venv -p 3.13 && ${pkgs.uv}/bin/uv sync" || echo "agent-mail venv setup failed"
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

  # Rebuild cass search index so ntm health checks pass
  home.activation.cassIndex = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if command -v cass &>/dev/null; then
      echo "Rebuilding cass search index..."
      $DRY_RUN_CMD cass index --full || echo "cass index failed (non-fatal)"
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
      _update_ssh_agent() {
        local sock best=""
        if [[ -d ~/.ssh/agent ]]; then
          for sock in $(ls -t ~/.ssh/agent/s.* 2>/dev/null); do
            if [[ -S "$sock" ]]; then
              SSH_AUTH_SOCK="$sock" ssh-add -l >/dev/null 2>&1; [[ $? -ne 2 ]] && best="$sock" && break
            fi
          done
        fi
        if [[ -z "$best" && -S "''${XDG_RUNTIME_DIR}/ssh-agent" ]]; then
          SSH_AUTH_SOCK="''${XDG_RUNTIME_DIR}/ssh-agent" ssh-add -l >/dev/null 2>&1; [[ $? -ne 2 ]] && best="''${XDG_RUNTIME_DIR}/ssh-agent"
        fi
        [[ -n "$best" ]] && ln -sf "$best" ~/.ssh/ssh_auth_sock 2>/dev/null
      }
      _update_ssh_agent
    '';
    shellAliases = {
      fix-ssh = "_update_ssh_agent && ssh-add -l";
      bd = "br";
      am = "systemctl --user status agent-mail";
    };
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set -g fish_greeting ""
      starship init fish | source
      zoxide init fish | source

      function _update_ssh_agent
        set -l best ""
        if test -d ~/.ssh/agent
          for sock in (ls -t ~/.ssh/agent/s.* 2>/dev/null)
            if test -S "$sock"
              if SSH_AUTH_SOCK="$sock" command ssh-add -l >/dev/null 2>&1; or test $status -eq 1
                set best "$sock"
                break
              end
            end
          end
        end
        if test -z "$best"; and test -S "$XDG_RUNTIME_DIR/ssh-agent"
          if SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent" command ssh-add -l >/dev/null 2>&1; or test $status -eq 1
            set best "$XDG_RUNTIME_DIR/ssh-agent"
          end
        end
        if test -n "$best"
          ln -sf "$best" ~/.ssh/ssh_auth_sock 2>/dev/null
        end
      end
      _update_ssh_agent
    '';
    shellAliases = {
      fix-ssh = "_update_ssh_agent && ssh-add -l";

      # Jujutsu aliases
      jd = "jj desc";
      jf = "jj git fetch";
      jn = "jj new";
      jp = "jj git push";
      js = "jj st";

      ll = "eza -la";
      ls = "eza";
      cat = "bat";
      bd = "br";
      am = "systemctl --user status agent-mail";
    };
  };

  programs.git = {
    enable = true;
    signing = {
      key = "4E5C82C103A1D32E";
      signByDefault = true;
    };
    settings = {
      user.name = "Joost van der Laan";
      user.email = "j@jlnw.nl";
      alias = {
        prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(r) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
        root = "rev-parse --show-toplevel";
      };
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

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      line-numbers = true;
      side-by-side = true;
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

  programs.helix = {
    enable = true;
    defaultEditor = false;  # Keep nvim as EDITOR

    settings = {
      theme = "rose_pine";

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
    shellAliases = {
      fix-ssh = "_update_ssh_agent && ssh-add -l";
      bd = "br";
      am = "systemctl --user status agent-mail";
    };
    initContent = ''
      export GPG_TTY=$(tty)

      # SSH agent: find best working agent and update symlink
      _update_ssh_agent() {
        local sock best=""
        # Tailscale forwarded agents (newest first)
        if [[ -d ~/.ssh/agent ]]; then
          for sock in ~/.ssh/agent/s.*(NOm); do
            if [[ -S "$sock" ]]; then
              SSH_AUTH_SOCK="$sock" ssh-add -l >/dev/null 2>&1; [[ $? -ne 2 ]] && best="$sock" && break
            fi
          done
        fi
        # Systemd agent fallback
        if [[ -z "$best" && -S "''${XDG_RUNTIME_DIR}/ssh-agent" ]]; then
          SSH_AUTH_SOCK="''${XDG_RUNTIME_DIR}/ssh-agent" ssh-add -l >/dev/null 2>&1; [[ $? -ne 2 ]] && best="''${XDG_RUNTIME_DIR}/ssh-agent"
        fi
        [[ -n "$best" ]] && ln -sf "$best" ~/.ssh/ssh_auth_sock 2>/dev/null
      }
      _update_ssh_agent
    '';
  };

  #---------------------------------------------------------------------
  # Services (Linux only)
  #---------------------------------------------------------------------

  services.gpg-agent = lib.mkIf isLinux {
    enable = true;
    pinentry.package = pkgs.pinentry-tty;
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

  # Agent Mail - MCP HTTP server for async agent coordination
  systemd.user.services.agent-mail = lib.mkIf isLinux {
    Unit = {
      Description = "MCP Agent Mail HTTP Server";
      After = [ "network.target" ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = "%h/mcp_agent_mail";
      ExecStart = "%h/mcp_agent_mail/.venv/bin/python -m mcp_agent_mail.cli serve-http";
      Restart = "on-failure";
      RestartSec = 5;
      Environment = "PATH=%h/mcp_agent_mail/.venv/bin:/run/current-system/sw/bin";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Zellij layout for fuww projects
  home.file.".config/zellij/layouts/work.kdl".source = ./zellij-work.kdl;
  home.file.".config/zellij/layouts/fun.kdl".source = ./zellij-fun.kdl;
  home.file.".config/zellij/layouts/frontend.kdl".source = ../zellij-frontend-fuww.kdl;
  home.file.".config/zellij/layouts/backend.kdl".source = ../zellij-backend-fuww.kdl;
  home.file.".config/zellij/layouts/devops.kdl".source = ../zellij-monitor-runners.kdl;

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
