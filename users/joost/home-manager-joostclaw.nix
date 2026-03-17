{ isWSL, inputs, ... }:

{ config, lib, pkgs, osConfig, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  openclawGatewayExec = pkgs.writeShellScript "openclaw-gateway-joostclaw" ''
    set -euo pipefail

    tokenFile="${osConfig.sops.secrets.openclaw-gateway-token.path}"
    anthropicKeyFile="${osConfig.sops.secrets.openclaw-anthropic-api-key.path}"
    if [ ! -f "$tokenFile" ]; then
      echo "Missing $tokenFile" >&2
      exit 1
    fi
    if [ ! -f "$anthropicKeyFile" ]; then
      echo "Missing $anthropicKeyFile" >&2
      exit 1
    fi

    export OPENCLAW_GATEWAY_TOKEN="$(${pkgs.coreutils}/bin/tr -d '\n' < "$tokenFile")"
    export ANTHROPIC_API_KEY="$(${pkgs.coreutils}/bin/tr -d '\n' < "$anthropicKeyFile")"
    exec ${pkgs.openclaw-gateway}/bin/openclaw gateway --port 18789
  '';
in {
  # Home-manager state version
  home.stateVersion = "25.11";

  xdg.enable = true;

  # Fixed SSH_AUTH_SOCK path
  home.sessionVariables = {
    SSH_AUTH_SOCK = "$HOME/.ssh/ssh_auth_sock";
  };

  #---------------------------------------------------------------------
  # Packages - Minimal set for OpenClaw gateway server
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
    htop
    jq
    ripgrep
    rsync
    tmux
    tree
    unzip
    wget
    zip

    # DevOps
    chezmoi
  ];

  #---------------------------------------------------------------------
  # OpenClaw (AI assistant gateway)
  #---------------------------------------------------------------------

  programs.openclaw = {
    enable = true;
    systemd.enable = true;
    reloadScript.enable = true;

    instances.default = {
      enable = true;
      package = pkgs.openclaw-gateway;
      systemd.enable = true;
      config = {
        gateway = {
          mode = "local";
          auth = {
            mode = "token";
            allowTailscale = true;
          };
        };
        channels.telegram = {
          tokenFile = osConfig.sops.secrets.openclaw-telegram-bot-token.path;
          allowFrom = [ "5654206852" ];
        };
      };
    };
  };

  systemd.user.services.openclaw-gateway = {
    Install.WantedBy = [ "default.target" ];
    Service.ExecStart = lib.mkForce "${openclawGatewayExec}";
  };

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
    };
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set -g fish_greeting ""
      starship init fish | source

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
      ll = "eza -la";
      ls = "eza";
      cat = "bat";
      fix-ssh = "_update_ssh_agent && ssh-add -l";
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

      # OSC 52 clipboard
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
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    settings = builtins.fromTOML (builtins.readFile ./starship.toml);
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      fix-ssh = "_update_ssh_agent && ssh-add -l";
    };
    initContent = ''
      export GPG_TTY=$(tty)

      _update_ssh_agent() {
        local sock best=""
        if [[ -d ~/.ssh/agent ]]; then
          for sock in ~/.ssh/agent/s.*(NOm); do
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

  services.ssh-agent = lib.mkIf isLinux {
    enable = true;
    enableFishIntegration = false;
    enableZshIntegration = false;
    enableBashIntegration = false;
  };

  # Ensure ~/.ssh directory exists for agent socket symlink
  home.file.".ssh/.keep".text = "";
}
