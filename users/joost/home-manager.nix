{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  # Import shared configuration
  shared = import ../shared-home-manager.nix {
    inherit isWSL inputs pkgs lib isDarwin isLinux;
  };

  # Get unstable packages
  pkgsUnstable = import inputs.nixpkgs-unstable {
    inherit (pkgs) system;
    inherit (pkgs.config) allowUnfree;
    config = {
      allowUnfree = true;
      allowUnsupportedSystem = true;
    };
  };

  # Use shared manpager
  manpager = shared.manpager;

  gdk = pkgs.google-cloud-sdk.withExtraComponents( with pkgs.google-cloud-sdk.components; [
    gke-gcloud-auth-plugin
    alpha
    app-engine-go
    # app-engine-python
    beta
    # bq

    gsutil
    kubectl
    minikube
    # pubsub-emulator
    skaffold
    terraform-tools

    # google-cloud-cli-skaffold
    # google-cloud-cli-cloud-run-proxy
    #
    # should not be enabled for darwin:
    # cloud-build-local
  ]);

in {
  # Home-manager 22.11 requires this be set. We never set it so we have
  # to use the old state version.
  home.stateVersion = "18.09";

  # We manage our own Nushell config via Chezmoi
  home.shell.enableNushellIntegration = false;

  xdg.enable = true;

  #---------------------------------------------------------------------
  # Packages
  #---------------------------------------------------------------------

  # Packages I always want installed. Most packages I install using
  # per-project flakes sourced with direnv and nix-shell, so this is
  # not a huge list.
  fonts.fontconfig.enable = true;

  home.packages =  with pkgs; [
    asciinema
    air # Live reload for Go
    alacritty
    btop
    chezmoi
    kitty
    lazydocker
    lazygit
    bat
    cachix
    # code-cursor-fhs
    dasht # Search API docs offline, in terminal or browser
    devenv
    docker
    docker-compose
    # podman
    # podman-tui
    # colima # orbstack moet betere performance hebben
    eza # Modern replacement for ls
    fastfetch
    fd
    # ffmpeg_5 # libgl, needed for ML
    ffmpeg
    fzf
    gemini-cli
    gh
    # ghostty
    git-lfs
    gdk
    # google-cloud-sdk # See above, gdk with components list
    htop
    httpie
    imagemagick
    jq
    # kubernetes-helm
    # libGL # ML
    # libGLU # ML
    # libheif
    lmstudio # Run local LLMs
    # ollama
    opencode
    railway
    ripgrep
    tree
    watch
    xh # for sending HTTP requests (like HTTPie)
    zellij # Terminal workspace with batteries included
    zoxide # Fast cd command that learns your habits

    amp-cli
    codex
    grepai # Semantic code search for AI coding assistants

    # Rust should be in flake.nix for each project. However, those configs do need an initial Cargo.lock.Therefore, to create new projects we want Rust globally installed.
    rustup # rust-analyzer, cargo # installed by rustup
    cargo-generate # create project from git template
    # rust-script
    # rustc
    pre-commit
    wasm-pack
    # pkgsUnstable.fermyon-spin  # Use unstable version

    python3
    poetry
    uv

    aichat
    # aider-chat  # Temporarily disabled due to python3.12-setproctitle build failure on macOS
    crush
    darktable
    dbeaver-bin
    devcontainer
    discord
    # element-web  # Temporarily disabled due to nodejs build failures
    # gimp
    google-chrome
    inkscape
    postman
    slack
    # spotify
    # telegram-desktop

    # Fonts
    font-awesome # waybar icons
    fira-code
    fira-code-symbols
    ibm-plex
    jetbrains-mono
    liberation_ttf
    mplus-outline-fonts.githubRelease
    nerd-fonts.caskaydia-mono # Cascadia Code with Nerd Font patches
    # nerdfonts # Changed: nerdfonts separated into individual packages
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    rubik
    proggyfonts

    bashmount # Easily mount (encrypted/usb) drives
    flyctl
    git-crypt
    glab
    k9s # Kuberenetes CLI
    neofetch
    nixd # Nix language server, used by Zed
    # obs-studio
    python3
    pocketbase
    # surrealdb # Builds from src
    # tailscale # install via Brew to prevent system extension problems on macos
    transmission_4
    yubikey-manager
    bitwarden-cli

    # Modern CLI tools
    delta         # Better git diff
    tokei         # Code statistics
    dust          # Disk usage analyzer
    procs         # Better ps
    lazygit       # Git TUI

    # zed # Broken

    # Node is required for Copilot.vim
    nodejs_22
    nodePackages.firebase-tools
  ] ++ (lib.optionals isDarwin [
    aerospace
    # This is automatically setup on Linux
    cachix
    pinentry_mac
    raycast
    sketchybar
    sketchybar-app-font
    skhd # hotkeys for yabai
    # tailscale # do not add here, it will recompile each time
    yabai # tiling window manager
  ]) ++ (lib.optionals (isLinux && !isWSL) [
    chromium
    firefox-devedition
    # brave
    rofi
    zathura
    xfce.xfce4-terminal
    libwacom
    libinput
    # bitwarden
    bitwarden-cli
    bitwarden-menu # Dmenu/rofi frontend
    geekbench
    nextcloud-client
    obsidian
    podman-desktop
    rpi-imager
    # sublime4 # do not install, needs old openssl?
    signal-desktop
    tailscale-systray
    # windsurf  # Replaced with VS Code
    baobab # Disk usage, gnome only
  ]);

  #---------------------------------------------------------------------
  # Env vars and dotfiles
  #---------------------------------------------------------------------

  home.sessionVariables = shared.sessionVariables // {
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    PATH = "$HOME/.local/bin:$HOME/go/bin:$HOME/.npm-global/bin:$PATH";
    EDITOR = "hx";
    VISUAL = "hx";
    BROWSER = "chromium";
    PAGER = "less -R";
    LANG = "en_US.UTF-8";
  } // lib.optionalAttrs isDarwin {
    # Bitwarden SSH agent socket
    SSH_AUTH_SOCK = "$HOME/.bitwarden-ssh-agent.sock";

    # Rose Pine theme for fzf
    # FZF_DEFAULT_OPTS = ''
    #   --color=fg:#e0def4,bg:#191724,hl:#c4a7e7
    #   --color=fg+:#e0def4,bg+:#26233a,hl+:#c4a7e7
    #   --color=info:#9ccfd8,prompt:#eb6f92,pointer:#f6c177
    #   --color=marker:#ebbcba,spinner:#f6c177,header:#9ccfd8
    #   --color=border:#403d52,label:#6e6a86,query:#e0def4
    #   --border="rounded" --border-label="" --preview-window="border-rounded" --prompt="> "
    # '';
  };

  # Install Claude Code CLI if not present
  home.activation.installClaudeCode = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ! command -v claude &> /dev/null; then
      $DRY_RUN_CMD bash -c "curl -fsSL https://claude.ai/install.sh | bash"
    fi
  '';

  # Sync dotfiles from chezmoi repo (auto-applies, warns on conflicts)
  home.activation.chezmoiSync = lib.hm.dag.entryAfter ["writeBoundary"] ''
    CHEZMOI_SOURCE="$HOME/.local/share/chezmoi"
    if [ -d "$CHEZMOI_SOURCE" ]; then
      echo "Syncing dotfiles from chezmoi repo..."
      $DRY_RUN_CMD ${pkgs.chezmoi}/bin/chezmoi update || true
    else
      echo "Chezmoi not initialized. Run: chezmoi init --apply git@github.com:javdl/dotfiles.git"
    fi
  '';

  home.file = {
    ".gdbinit".source = ./gdbinit;
    ".inputrc".source = ./inputrc;
    ".gitignore".text = ''
      # macOS
      .DS_Store
      .AppleDouble
      .LSOverride
      ._*

      # GPG
      secring.*

      # Editor backups and swap files
      *.swp
      *.swo
      *~
      \#*\#
      .*.sw[a-z]

      # VS Code
      .vscode/*
      !.vscode/settings.json
      !.vscode/tasks.json
      !.vscode/launch.json
      !.vscode/extensions.json
      !.vscode/*.code-snippets
      !*.code-workspace

      # Built Visual Studio Code Extensions
      *.vsix

      # Covers JetBrains IDEs: IntelliJ, GoLand, RubyMine, PhpStorm, AppCode, PyCharm, CLion, Android Studio, WebStorm and Rider
      # Reference: https://intellij-support.jetbrains.com/hc/en-us/articles/206544839

      # User-specific stuff
      .idea/**/workspace.xml
      .idea/**/tasks.xml
      .idea/**/usage.statistics.xml
      .idea/**/dictionaries
      .idea/**/shelf

      # AWS User-specific
      .idea/**/aws.xml

      # Generated files
      .idea/**/contentModel.xml

      # Sensitive or high-churn files
      .idea/**/dataSources/
      .idea/**/dataSources.ids
      .idea/**/dataSources.local.xml
      .idea/**/sqlDataSources.xml
      .idea/**/dynamic.xml
      .idea/**/uiDesigner.xml
      .idea/**/dbnavigator.xml

      # Gradle
      .idea/**/gradle.xml
      .idea/**/libraries

      # Gradle and Maven with auto-import
      # When using Gradle or Maven with auto-import, you should exclude module files,
      # since they will be recreated, and may cause churn.  Uncomment if using
      # auto-import.
      # .idea/artifacts
      # .idea/compiler.xml
      # .idea/jarRepositories.xml
      # .idea/modules.xml
      # .idea/*.iml
      # .idea/modules
      # *.iml
      # *.ipr

      # CMake
      cmake-build-*/

      # Mongo Explorer plugin
      .idea/**/mongoSettings.xml

      # File-based project format
      *.iws

      # IntelliJ
      out/

      # mpeltonen/sbt-idea plugin
      .idea_modules/

      # JIRA plugin
      atlassian-ide-plugin.xml

      # Cursive Clojure plugin
      .idea/replstate.xml

      # SonarLint plugin
      .idea/sonarlint/
      .idea/sonarlint.xml

      # Crashlytics plugin (for Android Studio and IntelliJ)
      com_crashlytics_export_strings.xml
      crashlytics.properties
      crashlytics-build.properties
      fabric.properties

      # Editor-based HTTP Client
      .idea/httpRequests
      http-client.private.env.json

      # Android studio 3.1+ serialized cache file
      .idea/caches/build_file_checksums.ser

      # Apifox Helper cache
      .idea/.cache/.Apifox_Helper
      .idea/ApifoxUploaderProjectSetting.xml

      # Environment files (often contain secrets)
      .env
      .env.local
      .env.*.local

      # Logs
      *.log
      npm-debug.log*
      yarn-debug.log*
      yarn-error.log*

      # Dependencies (project-specific should be in project .gitignore)
      node_modules/

      # Build outputs (project-specific should be in project .gitignore)
      dist/
      build/
      target/

      # Temporary files
      *.tmp
      *.temp
      .cache/

      # OS thumbnails
      Thumbs.db

      # Direnv
      .direnv/
      .envrc.local

      # https://lefthook.dev/configuration/#config-file-name
      /.lefthook-local.json
      /.lefthook-local.toml
      /.lefthook-local.yaml
      /.lefthook-local.yml
      /lefthook-local.json
      /lefthook-local.toml
      /lefthook-local.yaml
      /lefthook-local.yml
      /.config/lefthook-local.json
      /.config/lefthook-local.toml
      /.config/lefthook-local.yaml
      /.config/lefthook-local.yml

      # https://lefthook.dev/configuration/source_dir_local.html
      /.lefthook-local/
    '';

  } // (if isDarwin then {
    "Library/Application Support/Sublime Text/Packages/User/Preferences.sublime-settings".text = builtins.readFile ./sublime-preferences.json;
    "Library/Application Support/Sublime Text/Packages/User/Package Control.sublime-settings".text = builtins.readFile ./sublime-package-control.json;
    ".gnupg/gpg-agent.conf".text = ''
      pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
      default-cache-ttl 600
      max-cache-ttl 7200
    '';
  } else {});

  xdg.configFile = {
    # Linux only
#    "hypr/hyprland.conf".text = builtins.readFile ./hypr/hyprland.conf;
#    "hypr/hyprlock.conf".text = builtins.readFile ./hypr/hyprlock.conf;
#    "hypr/hypridle.conf".text = builtins.readFile ./hypr/hypridle.conf;
#    "hypr/hyprpaper.conf".text = builtins.readFile ./hypr/hyprpaper.conf;
#    "wofi/config".text = builtins.readFile ./wofi/config;
#    "waybar/config".text = builtins.readFile ./waybar/config;
#    "waybar/modules".text = builtins.readFile ./waybar/modules;
#    "waybar/style.css".text = builtins.readFile ./waybar/style.css;
#    "mpd/mpd.conf".text = builtins.readFile ./mpd/mpd.conf;
#    "electron-flags.conf".text = builtins.readFile ./electron-flags.conf;
#    "electron-flags28.conf".source  = ./electron-flags.conf;
#    "code-flags.conf".text = builtins.readFile ./code-flags.conf;
#    "btop/btop.conf".text = builtins.readFile ./btop.conf;
#
#    "wallpapers/04167_unreachable_3840x2160.png".source = ./wallpapers/04167_unreachable_3840x2160.png;
#
#    "i3/config".text = builtins.readFile ./i3;
#    "rofi/config.rasi".text = builtins.readFile ./rofi;
  } // (if isDarwin then {
    "ghostty/config".text = builtins.readFile ./ghostty.conf;
    "skhd/skhdrc".text = builtins.readFile ./skhdrc;
    "aerospace/aerospace.toml".text = builtins.readFile ./aerospace.toml;
    "sketchybar/sketchybarrc" = {
      source = ./sketchybar/sketchybarrc;
      executable = true;
    };
    "sketchybar/colors.sh".text = builtins.readFile ./sketchybar/colors.sh;
    "sketchybar/icons.sh".text = builtins.readFile ./sketchybar/icons.sh;
    "sketchybar/plugins" = {
          source = ./sketchybar/plugins;
          recursive = true;
          executable = true;
        };
    "sketchybar/items" = {
          source = ./sketchybar/items;
          recursive = true;
          executable = true;
        };
    "sketchybar/helper" = {
          source = ./sketchybar/helper;
          recursive = true;
          executable = true;
        };
  } else {}) // (if isLinux then {
    "ghostty/config".text = builtins.readFile ./ghostty.linux;
    "sublime-text/Packages/User/Preferences.sublime-settings".text = builtins.readFile ./sublime-preferences.json;
    "sublime-text/Packages/User/Package Control.sublime-settings".text = builtins.readFile ./sublime-package-control.json;
  } else {});

  # Gnome settings
  # Use `dconf watch /` to track stateful changes you are doing, then set them here.
  dconf.settings = shared.dconfSettings // {
    "org/gnome/shell" = {
      favorite-apps = [
          "firefox.desktop"
          "com.mitchellh.ghostty.desktop"
          "code.desktop"
          # "kitty.desktop"
        # "kgx.desktop" # Should be Gnome console. kgx in terminal to start it does work.
        #"vscode.desktop"
        # "codium.desktop"
        "org.gnome.Terminal.desktop"
        #"spotify.desktop"
        #"virt-manager.desktop"
        "org.gnome.Nautilus.desktop"
      ];
    };
    #"org/gnome/desktop/background" = {
    #  picture-uri = "file:///run/current-system/sw/share/backgrounds/gnome/vnc-l.png";
    #  picture-uri-dark = "file:///run/current-system/sw/share/backgrounds/gnome/vnc-d.png";
    #};
    #"org/gnome/desktop/screensaver" = {
    #  picture-uri = "file:///run/current-system/sw/share/backgrounds/gnome/vnc-d.png";
    #  primary-color = "#3465a4";
    #  secondary-color = "#000000";
    #};
  };

  #---------------------------------------------------------------------
  # Programs
  #---------------------------------------------------------------------

  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        bbenoist.nix
        eamodio.gitlens
        github.codespaces
        github.copilot
        github.copilot-chat
        ms-python.python
        ms-azuretools.vscode-docker
        ms-toolsai.jupyter
        ms-vscode-remote.remote-ssh
        vscode-icons-team.vscode-icons
        mvllow.rose-pine  # Rose Pine theme
      ];

      userSettings = {
        "workbench.colorTheme" = "Rosé Pine";
        "editor.fontFamily" = "CaskaydiaMono Nerd Font";
        "editor.fontSize" = 14;
        "editor.fontLigatures" = true;
        "terminal.integrated.fontFamily" = "CaskaydiaMono Nerd Font";
        "terminal.integrated.fontSize" = 14;
      };
    };
  };

  programs.gpg.enable = !isDarwin;

  programs.bash = {
    enable = true;
    shellOptions = [];
    historyControl = [ "ignoredups" "ignorespace" ];
    initExtra = ''
      ${builtins.readFile ./bashrc}
      export GPG_TTY=$(tty)

      # Claude with bash shell
      claude() {
        SHELL=/bin/bash command claude "$@"
      }
    '';

    shellAliases = shared.shellAliases;
  };

  programs.direnv= {
      enable = true;
      nix-direnv.enable = true; # faster
      enableNushellIntegration = false; # broken?

      config = {
        whitelist = {
          prefix= [
            "$HOME/code/go/src/github.com/fuww"
            "$HOME/code/go/src/github.com/javdl"
            "$HOME/git/fuww"
            "$HOME/git/javdl"
          ];

          exact = ["$HOME/.envrc"];
        };
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

      # Force block cursor (escape sequence)
      # \e[2 q = steady block, \e[1 q = blinking block
      echo -ne '\e[2 q'

      # Reset cursor to block on each new prompt
      preexec() { echo -ne '\e[2 q' }
      precmd() { echo -ne '\e[2 q' }

      # Fix insecure completion files
      autoload -Uz compinit
      # Only run compinit once a day
      if [[ -n "$(find "$HOME/.zcompdump" -mtime +1 2>/dev/null)" ]]; then
        compinit
      else
        compinit -C
      fi

      # Fix permissions on completion directory
      zstyle ':completion:*' use-cache on
      zstyle ':completion:*' cache-path "$HOME/.zcompcache"

      # Skip the not really helpful global compinit
      skip_global_compinit=1

      # Rose Pine colors for zsh
      export ROSE_PINE_BASE="#191724"
      export ROSE_PINE_SURFACE="#1f1d2e"
      export ROSE_PINE_OVERLAY="#26233a"
      export ROSE_PINE_MUTED="#6e6a86"
      export ROSE_PINE_SUBTLE="#908caa"
      export ROSE_PINE_TEXT="#e0def4"
      export ROSE_PINE_LOVE="#eb6f92"
      export ROSE_PINE_GOLD="#f6c177"
      export ROSE_PINE_ROSE="#ebbcba"
      export ROSE_PINE_PINE="#31748f"
      export ROSE_PINE_FOAM="#9ccfd8"
      export ROSE_PINE_IRIS="#c4a7e7"
      export ROSE_PINE_HL_LOW="#21202e"
      export ROSE_PINE_HL_MED="#403d52"
      export ROSE_PINE_HL_HIGH="#524f67"

      # Apply Rose Pine colors to zsh syntax highlighting
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
      ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[assign]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[redirection]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[named-fd]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[numeric-fd]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[arg0]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[default]="fg=#e0def4"
      ZSH_HIGHLIGHT_STYLES[unknown-token]="fg=#eb6f92,bold"

      # Zellij Claude Fix
      alias cc="SHELL=/bin/bash VSCODE_PID= VSCODE_CWD= TERM_PROGRAM= command claude"

      claude() {
        SHELL=/bin/bash VSCODE_PID= VSCODE_CWD= TERM_PROGRAM= command claude "$@"
      }
    '';

    # This ensures proper sourcing of home-manager environment variables
    envExtra = ''
      # Make sure home-manager variables are sourced
      if [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
      fi
    '';
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = lib.strings.concatStrings (lib.strings.intersperse "\n" ([
      (builtins.readFile ./config.fish)
      "set -g SHELL ${pkgs.fish}/bin/fish"
      "set -gx GPG_TTY (tty)"
    ]));

    shellAliases = shared.shellAliases;

    plugins = shared.fishPlugins;
  };

  programs.git = {
    enable = true;
    signing = {
      key = "ACAFA950";
      signByDefault = true;
    };
    settings = {
      user.name = "Joost van der Laan";
      user.email = "j@jlnw.nl";
      delta = {
        enable = true;
        options = {
          line-numbers = true;
          side-by-side = true;
        };
      };
      branch.autosetuprebase = "always";
      color.ui = true;
      core.askPass = ""; # needs to be empty to use terminal for ask pass
      core.excludesFile = "~/.gitignore";
      # https://github.com/github/gitignore/tree/main/Global
      credential.helper = "store"; # want to make this more secure
      github.user = "javdl";
      push.default = "tracking";
      push.autoSetupRemote = true;
      init.defaultBranch = "main";
      aliases = {
        cleanup = "!git branch --merged | grep  -v '\\*\\|master\\|develop' | xargs -n 1 -r git branch -d";
        prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(r) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
        root = "rev-parse --show-toplevel";
      };

      "filter \"lfs\"" = {
          clean = "${pkgs.git-lfs}/bin/git-lfs clean -- %f";
          smudge = "${pkgs.git-lfs}/bin/git-lfs smudge --skip -- %f";
          required = true;
        };

    };
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks = {
      "*" = {
        compression = true;
        serverAliveInterval = 60;
        serverAliveCountMax = 3;
      };

      "hetzner-work" = {
        hostname = "2a01:4f8:1c1f:ad3c::1";
        user = "root";
        identityFile = "~/.ssh/id_ed25519_hetzner_work";
        identitiesOnly = true;
      };

      # Hetzner remote dev server via Tailscale SSH
      # Tailscale handles auth - no SSH keys needed
      "hetzner-dev" = {
        hostname = "100.120.8.90";  # Tailscale IP
        user = "joost";
        forwardAgent = true;  # Forward SSH agent for git operations
        extraOptions = {
          RequestTTY = "yes";
          RemoteCommand = "tmux new-session -A -s main";
        };
      };
      # Direct access via public IPv6 (fallback if Tailscale is down)
      "hetzner-dev-public" = {
        hostname = "2a01:4f8:1c1f:ad3c::1";  # IPv6
        user = "joost";
        forwardAgent = true;
        extraOptions = {
          RequestTTY = "yes";
          RemoteCommand = "tmux new-session -A -s main";
        };
      };
    };
  };

  programs.go = {
    enable = true;
    env = {
      GOPATH = "${config.home.homeDirectory}/go";
      GOPRIVATE = [ "github.com/javdl" "github.com/fuww"  ];
    };
  };

  programs.jujutsu = {
    enable = true;

    # I don't use "settings" because the path is wrong on macOS at
    # the time of writing this.
  };

  # this should be disabled for darwin
  # programs.obs-studio = {
  #   enable = true;
  #   plugins = with pkgs.obs-studio-plugins; [
  #     # wlrobs # nix install error
  #     obs-backgroundremoval
  #     obs-pipewire-audio-capture
  #   ];
  # };

  programs.tmux = {
    enable = true;
    terminal = "xterm-256color";
    shortcut = "l";
    secureSocket = false;

    extraConfig = ''
      # Run shell as login shell to source Nix profiles (needed for gt/claude in spawned sessions)
      set-option -g default-command "$SHELL -l"

      set -ga terminal-overrides ",*256col*:Tc"

      # Rose Pine theme
      set -g mode-style "fg=#e0def4,bg=#403d52"

      set -g message-style "fg=#e0def4,bg=#26233a"
      set -g message-command-style "fg=#e0def4,bg=#26233a"

      set -g pane-border-style "fg=#403d52"
      set -g pane-active-border-style "fg=#c4a7e7"

      set -g status "on"
      set -g status-justify "left"

      set -g status-style "fg=#e0def4,bg=#191724"

      set -g status-left-length "100"
      set -g status-right-length "100"

      set -g status-left-style NONE
      set -g status-right-style NONE

      set -g status-left "#[fg=#26233a,bg=#ebbcba,bold] #S #[fg=#ebbcba,bg=#191724,nobold,nounderscore,noitalics]"
      set -g status-right "#[fg=#191724,bg=#191724,nobold,nounderscore,noitalics]#[fg=#ebbcba,bg=#191724] #{prefix_highlight} #[fg=#403d52,bg=#191724,nobold,nounderscore,noitalics]#[fg=#e0def4,bg=#403d52] %Y-%m-%d  %I:%M %p #[fg=#c4a7e7,bg=#403d52,nobold,nounderscore,noitalics]#[fg=#26233a,bg=#c4a7e7,bold] #h "

      setw -g window-status-activity-style "underscore,fg=#6e6a86,bg=#191724"
      setw -g window-status-separator ""
      setw -g window-status-style "NONE,fg=#6e6a86,bg=#191724"
      setw -g window-status-format "#[fg=#191724,bg=#191724,nobold,nounderscore,noitalics]#[default] #I  #W #F #[fg=#191724,bg=#191724,nobold,nounderscore,noitalics]"
      setw -g window-status-current-format "#[fg=#191724,bg=#403d52,nobold,nounderscore,noitalics]#[fg=#e0def4,bg=#403d52,bold] #I  #W #F #[fg=#403d52,bg=#191724,nobold,nounderscore,noitalics]"

      bind -n C-k send-keys "clear"\; send-keys "Enter"
    '';
  };

  programs.alacritty = {
    enable = !isWSL;

    settings = {
      env.TERM = "xterm-256color";

      cursor = {
        style = {
          shape = "Block";
          blinking = "On";
        };
        blink_interval = 500;
      };

      font = {
        normal = {
          family = "CaskaydiaMono Nerd Font";
          style = "Regular";
        };
        bold = {
          family = "CaskaydiaMono Nerd Font";
          style = "Bold";
        };
        italic = {
          family = "CaskaydiaMono Nerd Font";
          style = "Italic";
        };
        bold_italic = {
          family = "CaskaydiaMono Nerd Font";
          style = "Bold Italic";
        };
        size = 14.0;
      };

      key_bindings = [
        { key = "K"; mods = "Command"; chars = "ClearHistory"; }
        { key = "V"; mods = "Command"; action = "Paste"; }
        { key = "C"; mods = "Command"; action = "Copy"; }
        { key = "Key0"; mods = "Command"; action = "ResetFontSize"; }
        { key = "Equals"; mods = "Command"; action = "IncreaseFontSize"; }
        { key = "Minus"; mods = "Command"; action = "DecreaseFontSize"; }
      ];

      # Rose Pine theme colors
      colors = {
        primary = {
          background = "#191724";
          foreground = "#e0def4";
        };

        cursor = {
          text = "#191724";
          cursor = "#f6c177";
        };

        vi_mode_cursor = {
          text = "#191724";
          cursor = "#f6c177";
        };

        selection = {
          text = "#e0def4";
          background = "#403d52";
        };

        normal = {
          black = "#26233a";
          red = "#eb6f92";
          green = "#31748f";
          yellow = "#f6c177";
          blue = "#9ccfd8";
          magenta = "#c4a7e7";
          cyan = "#ebbcba";
          white = "#e0def4";
        };

        bright = {
          black = "#6e6a86";
          red = "#eb6f92";
          green = "#31748f";
          yellow = "#f6c177";
          blue = "#9ccfd8";
          magenta = "#c4a7e7";
          cyan = "#ebbcba";
          white = "#e0def4";
        };
      };
    };
  };

  programs.kitty = {
    enable = !isWSL;
    extraConfig = builtins.readFile ./kitty;
  };

  programs.i3status = {
    enable = isLinux && !isWSL;

    general = {
      colors = true;
      color_good = "#8C9440";
      color_bad = "#A54242";
      color_degraded = "#DE935F";
    };

    modules = {
      ipv6.enable = false;
      "wireless _first_".enable = false;
      "battery all".enable = false;
    };
  };

  programs.neovim = {
    enable = true;
    package = inputs.neovim-nightly-overlay.packages.${pkgs.stdenv.hostPlatform.system}.default;

    withPython3 = true;
    extraPython3Packages = (p: with p; [
      # For nvim-magma
      jupyter-client
      cairosvg
      plotly
      #pnglatex
      #kaleido
    ]);

    extraLuaConfig = ''
      -- Setup Rose Pine theme
      require("rose-pine").setup({
        variant = "main",
        dark_variant = "main",
      })

      -- Set colorscheme
      vim.cmd("colorscheme rose-pine")
    '';

    plugins = with pkgs; [

      # Themes
      vimPlugins.rose-pine  # Default theme
      vimPlugins.tokyonight-nvim
      vimPlugins.catppuccin-nvim
      vimPlugins.nord-nvim
      vimPlugins.everforest
      vimPlugins.gruvbox-nvim
      vimPlugins.kanagawa-nvim

      # Standard vim plugins from nixpkgs
      vimPlugins.telescope-nvim
      vimPlugins.plenary-nvim # required for telescope
      vimPlugins.nvim-lspconfig
      vimPlugins.gitsigns-nvim
      vimPlugins.lazy-nvim
      vimPlugins.lualine-nvim
      vimPlugins.conform-nvim
      vimPlugins.dressing-nvim
      vimPlugins.nui-nvim
      vimPlugins.rust-vim
      vimPlugins.nvim-treesitter-context
      vimPlugins.nvim-web-devicons
      vimPlugins.vim-eunuch
      vimPlugins.vim-gitgutter
      vimPlugins.vim-markdown
      vimPlugins.vim-nix
      vimPlugins.typescript-vim
      vimPlugins.nvim-treesitter-parsers.elixir
      vimPlugins.nvim-treesitter
      vimPlugins.nvim-treesitter.withAllGrammars
    ];

    extraConfig = ''
      " Set font for GUI Neovim
      if has('gui_running') || exists('g:neovide')
        set guifont=CaskaydiaMono\ Nerd\ Font:h14
      endif

      set background=dark

      " Theme switching shortcuts
      nnoremap <leader>t1 :colorscheme rose-pine<CR>
      nnoremap <leader>t2 :colorscheme tokyonight<CR>
      nnoremap <leader>t3 :colorscheme catppuccin<CR>
      nnoremap <leader>t4 :colorscheme nord<CR>
      nnoremap <leader>t5 :colorscheme everforest<CR>
      nnoremap <leader>t6 :colorscheme gruvbox<CR>
      nnoremap <leader>t7 :colorscheme kanagawa<CR>

      " Quick theme list
      nnoremap <leader>tt :echo "Themes: 1=Rose Pine, 2=Tokyo Night, 3=Catppuccin, 4=Nord, 5=Everforest, 6=Gruvbox, 7=Kanagawa"<CR>
    '';
  };

  programs.atuin = {
    enable = true;
    enableFishIntegration = true;
    enableNushellIntegration = false;
    settings = {
      show_tabs = false;
      style = "compact";
    };
  };

  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
    enableNushellIntegration = true;
    options = [
      "--cmd cd" # Make 'cd' command use zoxide
    ];
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
      language-server = {
        rust-analyzer = {
          config = {
            checkOnSave.command = "clippy";
          };
        };
      };

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

  programs.nushell = {
    enable = true;
    # configFile.source = ./config.nu;
    # # shellAliases = shellAliases;
    # shellAliases = shared.shellAliases;
    # extraConfig = ''
    #   # Rose Pine theme colors for nushell
    #   let rose_pine_theme = {
    #     # Special
    #     background: '#191724'
    #     foreground: '#e0def4'

    #     # Colors
    #     black: '#26233a'
    #     red: '#eb6f92'
    #     green: '#31748f'
    #     yellow: '#f6c177'
    #     blue: '#9ccfd8'
    #     magenta: '#c4a7e7'
    #     cyan: '#ebbcba'
    #     white: '#e0def4'

    #     # Bright colors
    #     bright_black: '#6e6a86'
    #     bright_red: '#eb6f92'
    #     bright_green: '#31748f'
    #     bright_yellow: '#f6c177'
    #     bright_blue: '#9ccfd8'
    #     bright_magenta: '#c4a7e7'
    #     bright_cyan: '#ebbcba'
    #     bright_white: '#e0def4'
    #   }

    #   # Set the theme
    #   $env.config = ($env.config | default {})
    #   $env.config.color_config = $rose_pine_theme
    # '';
  };


  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
    enableNushellIntegration = true;
    settings = builtins.fromTOML (builtins.readFile ./starship.toml);
  };

  programs.zellij = {
    enable = true;
    settings = {
      default_shell = "zsh";
      theme = "rose-pine";
      themes = {
        rose-pine = {
          text_unselected = {
            base = [224 222 244];
            background = [33 32 46];
            emphasis_0 = [235 188 186];
            emphasis_1 = [156 207 216];
            emphasis_2 = [49 116 143];
            emphasis_3 = [196 167 231];
          };
          text_selected = {
            base = [224 222 244];
            background = [64 61 82];
            emphasis_0 = [235 188 186];
            emphasis_1 = [156 207 216];
            emphasis_2 = [49 116 143];
            emphasis_3 = [196 167 231];
          };
          ribbon_selected = {
            base = [33 32 46];
            background = [49 116 143];
            emphasis_0 = [246 193 119];
            emphasis_1 = [235 188 186];
            emphasis_2 = [196 167 231];
            emphasis_3 = [156 207 216];
          };
          ribbon_unselected = {
            base = [25 23 36];
            background = [224 222 244];
            emphasis_0 = [246 193 119];
            emphasis_1 = [235 188 186];
            emphasis_2 = [196 167 231];
            emphasis_3 = [156 207 216];
          };
          table_title = {
            base = [49 116 143];
            background = [0 0 0];
            emphasis_0 = [235 188 186];
            emphasis_1 = [156 207 216];
            emphasis_2 = [49 116 143];
            emphasis_3 = [196 167 231];
          };
          table_cell_selected = {
            base = [224 222 244];
            background = [64 61 82];
            emphasis_0 = [235 188 186];
            emphasis_1 = [156 207 216];
            emphasis_2 = [49 116 143];
            emphasis_3 = [196 167 231];
          };
          table_cell_unselected = {
            base = [224 222 244];
            background = [33 32 46];
            emphasis_0 = [235 188 186];
            emphasis_1 = [156 207 216];
            emphasis_2 = [49 116 143];
            emphasis_3 = [196 167 231];
          };
          list_selected = {
            base = [224 222 244];
            background = [64 61 82];
            emphasis_0 = [235 188 186];
            emphasis_1 = [156 207 216];
            emphasis_2 = [49 116 143];
            emphasis_3 = [196 167 231];
          };
          list_unselected = {
            base = [224 222 244];
            background = [33 32 46];
            emphasis_0 = [235 188 186];
            emphasis_1 = [156 207 216];
            emphasis_2 = [49 116 143];
            emphasis_3 = [196 167 231];
          };
          frame_selected = {
            base = [49 116 143];
            background = [0 0 0];
            emphasis_0 = [235 188 186];
            emphasis_1 = [156 207 216];
            emphasis_2 = [196 167 231];
            emphasis_3 = [0 0 0];
          };
          frame_highlight = {
            base = [235 188 186];
            background = [0 0 0];
            emphasis_0 = [235 188 186];
            emphasis_1 = [235 188 186];
            emphasis_2 = [235 188 186];
            emphasis_3 = [235 188 186];
          };
          exit_code_success = {
            base = [49 116 143];
            background = [0 0 0];
            emphasis_0 = [156 207 216];
            emphasis_1 = [33 32 46];
            emphasis_2 = [196 167 231];
            emphasis_3 = [49 116 143];
          };
          exit_code_error = {
            base = [235 111 146];
            background = [0 0 0];
            emphasis_0 = [246 193 119];
            emphasis_1 = [0 0 0];
            emphasis_2 = [0 0 0];
            emphasis_3 = [0 0 0];
          };
          multiplayer_user_colors = {
            player_1 = [196 167 231];
            player_2 = [49 116 143];
            player_3 = [235 188 186];
            player_4 = [246 193 119];
            player_5 = [156 207 216];
            player_6 = [235 111 146];
            player_7 = [0 0 0];
            player_8 = [0 0 0];
            player_9 = [0 0 0];
            player_10 = [0 0 0];
          };
        };
      };
    };
  };

  services.gpg-agent = {
    enable = isLinux;
    pinentry.package = pkgs.pinentry-tty;

    # cache the keys forever so we don't get asked for a password
    defaultCacheTtl = 31536000;
    maxCacheTtl = 31536000;
  };

  xresources.extraConfig = builtins.readFile ./Xresources;

  # Make cursor not tiny on HiDPI screens
  home.pointerCursor = lib.mkIf (isLinux && !isWSL) {
    name = "Vanilla-DMZ";
    package = pkgs.vanilla-dmz;
    size = 128;
    x11.enable = true;
  };

}
