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

  xdg.enable = true;

  #---------------------------------------------------------------------
  # Packages
  #---------------------------------------------------------------------

  # Packages I always want installed. Most packages I install using
  # per-project flakes sourced with direnv and nix-shell, so this is
  # not a huge list.
  fonts.fontconfig.enable = true;

  home.packages = [
    pkgs.asciinema
    pkgs.air # Live reload for Go
    pkgs.alacritty
    pkgs.kitty
    pkgs.bat
    pkgs.bottom
    pkgs.cachix
    pkgs.dasht # Search API docs offline, in terminal or browser
    pkgs.devenv
    pkgs.docker
    pkgs.docker-compose
    # pkgs.podman
    # pkgs.podman-tui
    # pkgs.colima # orbstack moet betere performance hebben
    pkgs.eza # Modern replacement for ls
    pkgs.fd
    # pkgs.ffmpeg_5 # libgl, needed for ML
    pkgs.ffmpeg
    pkgs.fzf
    pkgs.gh
    # pkgs.ghostty
    pkgs.git-lfs
    gdk
    # pkgs.google-cloud-sdk # See above, gdk with components list
    pkgs.htop
    pkgs.httpie
    pkgs.imagemagick
    pkgs.jq
    # pkgs.kubernetes-helm
    # pkgs.libGL # ML
    # pkgs.libGLU # ML
    # pkgs.libheif
    # pkgs.ollama # outdated, use brew
    pkgs.ripgrep
    pkgs.tree
    pkgs.watch
    pkgs.xh # for sending HTTP requests (like HTTPie)
    pkgs.zellij # Terminal workspace with batteries included
    pkgs.zoxide # Fast cd command that learns your habits

    # Rust should be in flake.nix for each project. However, those configs do need an initial Cargo.lock.Therefore, to create new projects we want Rust globally installed.
    pkgs.rustup # rust-analyzer, cargo # installed by rustup
    pkgs.cargo-generate # create project from git template
    # pkgs.rust-script
    # pkgs.rustc
    pkgs.pre-commit
    pkgs.wasm-pack
    # pkgsUnstable.fermyon-spin  # Use unstable version

    pkgs.python3
    pkgs.poetry
    pkgs.uv

    pkgs.aichat
    pkgs.aider-chat
    pkgs.darktable
    pkgs.dbeaver-bin
    pkgs.discord
    # pkgs.element-web  # Temporarily disabled due to nodejs build failures
    pkgs.gimp
    pkgs.google-chrome
    pkgs.inkscape
    pkgs.postman
    pkgs.slack
    pkgs.spotify
    # pkgs.telegram-desktop

    # Fonts
    pkgs.font-awesome # waybar icons
    pkgs.fira-code
    pkgs.fira-code-symbols
    pkgs.ibm-plex
    pkgs.jetbrains-mono
    pkgs.liberation_ttf
    pkgs.mplus-outline-fonts.githubRelease
    pkgs.nerd-fonts.caskaydia-mono # Cascadia Code with Nerd Font patches
    # pkgs.nerdfonts # Changed: nerdfonts separated into individual packages
    pkgs.noto-fonts
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-emoji
    pkgs.rubik
    pkgs.proggyfonts

    pkgs.bashmount # Easily mount (encrypted/usb) drives
    pkgs.flyctl
    pkgs.git-crypt
    pkgs.glab
    pkgs.k9s # Kuberenetes CLI
    pkgs.neofetch
    pkgs.nixd # Nix language server, used by Zed
    # pkgs.obs-studio
    pkgs.python3
    pkgs.pocketbase
    # pkgs.surrealdb # Builds from src
    pkgs.tailscale
    pkgs.transmission_4
    pkgs.yubikey-manager

    # pkgs.zed # Broken

    # Node is required for Copilot.vim
    pkgs.nodejs_22
    pkgs.nodePackages.firebase-tools
  ] ++ (lib.optionals isDarwin [
    pkgs.aerospace
    # This is automatically setup on Linux
    pkgs.cachix
    pkgs.pinentry_mac
    pkgs.raycast
    pkgs.sketchybar
    pkgs.sketchybar-app-font
    pkgs.skhd # hotkeys for yabai
    pkgs.tailscale
    pkgs.yabai # tiling window manager
  ]) ++ (lib.optionals (isLinux && !isWSL) [
    pkgs.chromium
    pkgs.firefox-devedition
    # pkgs.brave
    pkgs.rofi
    pkgs.zathura
    pkgs.xfce.xfce4-terminal
    pkgs.libwacom
    pkgs.libinput
    # pkgs.bitwarden
    pkgs.bitwarden-cli
    pkgs.bitwarden-menu # Dmenu/rofi frontend
    pkgs.geekbench
    pkgs.nextcloud-client
    pkgs.obsidian
    pkgs.podman-desktop
    pkgs.rpi-imager
    # pkgs.sublime4 # needs old openssl?
    pkgs.signal-desktop
    pkgs.tailscale-systray
    pkgs.windsurf
    pkgs.baobab # Disk usage, gnome only
  ]);

  #---------------------------------------------------------------------
  # Env vars and dotfiles
  #---------------------------------------------------------------------

  home.sessionVariables = shared.sessionVariables // {
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    PATH = "$HOME/.npm-global/bin:$PATH";
  };

  home.file = {
    ".gdbinit".source = ./gdbinit;
    ".inputrc".source = ./inputrc;
  } // (if isDarwin then {
    "Library/Application Support/jj/config.toml".source = ./jujutsu.toml;
    ".gnupg/gpg-agent.conf".text = ''
      pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
      default-cache-ttl 600
      max-cache-ttl 7200
    '';
  } else {});

  xdg.configFile = {
    "hypr/hyprland.conf".text = builtins.readFile ./hypr/hyprland.conf;
    "hypr/hyprlock.conf".text = builtins.readFile ./hypr/hyprlock.conf;
    "hypr/hypridle.conf".text = builtins.readFile ./hypr/hypridle.conf;
    "hypr/hyprpaper.conf".text = builtins.readFile ./hypr/hyprpaper.conf;
    "wofi/config".text = builtins.readFile ./wofi/config;
    "waybar/config".text = builtins.readFile ./waybar/config;
    "waybar/modules".text = builtins.readFile ./waybar/modules;
    "waybar/style.css".text = builtins.readFile ./waybar/style.css;
    "mpd/mpd.conf".text = builtins.readFile ./mpd/mpd.conf;
    "electron-flags.conf".text = builtins.readFile ./electron-flags.conf;
    "electron-flags28.conf".source  = ./electron-flags.conf;
    "code-flags.conf".text = builtins.readFile ./code-flags.conf;

    "wallpapers/04167_unreachable_3840x2160.png".source = ./wallpapers/04167_unreachable_3840x2160.png;

    "i3/config".text = builtins.readFile ./i3;
    "rofi/config.rasi".text = builtins.readFile ./rofi;
    "zed/settings.json".text = builtins.readFile ./zed.json;

    # tree-sitter parsers
    # "nvim/parser/proto.so".source = "${pkgs.tree-sitter-proto}/parser";
    # "nvim/queries/proto/folds.scm".source =
    #   "${sources.tree-sitter-proto}/queries/folds.scm";
    # "nvim/queries/proto/highlights.scm".source =
    #   "${sources.tree-sitter-proto}/queries/highlights.scm";
    # "nvim/queries/proto/textobjects.scm".source =
    #   ./textobjects.scm;

  } // (if isDarwin then {
    # Rectangle.app. This has to be imported manually using the app.
    # "rectangle/RectangleConfig.json".text = builtins.readFile ./RectangleConfig.json;
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
    "jj/config.toml".source = ./jujutsu.toml;
  } else {});

  # Gnome settings
  # Use `dconf watch /` to track stateful changes you are doing, then set them here.
  dconf.settings = shared.dconfSettings // {
    "org/gnome/shell" = {
      favorite-apps = [
          "firefox.desktop"
          "com.mitchellh.ghostty.desktop"
          "kitty.desktop"
          "windsurf.desktop"
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

  # disabled to prevent collision with Windsurf
  # programs.vscode = {
  #   enable = true;
  #   package = pkgs.vscode;
  #   extensions = with pkgs.vscode-extensions; [
  #     bbenoist.nix
  #     eamodio.gitlens
  #     github.codespaces
  #     github.copilot
  #     ms-python.python
  #     ms-azuretools.vscode-docker
  #     ms-toolsai.jupyter
  #     ms-vscode-remote.remote-ssh
  #     vscode-icons-team.vscode-icons
  #   ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
  #     {
  #       name = "remote-ssh-edit";
  #       publisher = "ms-vscode-remote";
  #       version = "0.117.2025012415";
  #       sha256 = "1hp6gjh4xp2m1xlm1jsdzxw9d8frkiidhph6nvl24d0h8z34w49g";
  #     }
  #     {
  #       name = "claude-dev";
  #       publisher = "saoudrizwan";
  #       version = "3.2.5";
  #       sha256 = "sha256-aJnN5zjF6tvUSMqVklNgCgpsfBNi1vw0i66BBFgHB1o=";
  #     }
  #   ];
  # };

  programs.gpg.enable = !isDarwin;

  programs.bash = {
    enable = true;
    shellOptions = [];
    historyControl = [ "ignoredups" "ignorespace" ];
    initExtra = ''
      ${builtins.readFile ./bashrc}
      export GPG_TTY=$(tty)
    '';

    shellAliases = shared.shellAliases;
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true; # see note on other shells below
    enableZshIntegration = true;
    enableNushellIntegration = true;
    nix-direnv.enable = true;

    config = shared.direnvConfig;
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

     shellAliases = shared.shellAliases;

    initContent = ''
      export GPG_TTY=$(tty)

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
    userName = "Joost van der Laan";
    userEmail = "joostvanderlaan@gmail.com";
    signing = {
      key = "ACAFA950";
      signByDefault = true;
    };
    aliases = {
      cleanup = "!git branch --merged | grep  -v '\\*\\|master\\|develop' | xargs -n 1 -r git branch -d";
      prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(r) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
      root = "rev-parse --show-toplevel";
    };
    extraConfig = {
      branch.autosetuprebase = "always";
      color.ui = true;
      core.askPass = ""; # needs to be empty to use terminal for ask pass
      credential.helper = "store"; # want to make this more secure
      github.user = "javdl";
      push.default = "tracking";
      push.autoSetupRemote = true;
      init.defaultBranch = "main";

      "filter \"lfs\"" = {
          clean = "${pkgs.git-lfs}/bin/git-lfs clean -- %f";
          smudge = "${pkgs.git-lfs}/bin/git-lfs smudge --skip -- %f";
          required = true;
        };
    };
  };

  programs.go = {
    enable = true;
    goPath = "code/go";
    goPrivate = [ "github.com/javdl" "github.com/fuww" ];
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
      set -ga terminal-overrides ",*256col*:Tc"

      set -g @dracula-show-battery false
      set -g @dracula-show-network false
      set -g @dracula-show-weather false

      bind -n C-k send-keys "clear"\; send-keys "Enter"
    '';
  };

  programs.alacritty = {
    enable = !isWSL;

    settings = {
      env.TERM = "xterm-256color";

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
    package = inputs.neovim-nightly-overlay.packages.${pkgs.system}.default;

    withPython3 = true;
    extraPython3Packages = (p: with p; [
      # For nvim-magma
      jupyter-client
      cairosvg
      plotly
      #pnglatex
      #kaleido
    ]);

    plugins = with pkgs; [
      # Custom vim plugins from flake inputs
      customVim.vim-copilot

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

      " Enable Rose Pine theme (default)
      colorscheme rose-pine
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
    enableNushellIntegration = true;
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

  programs.nushell = {
    enable = true;
    configFile.source = ./config.nu;
    # shellAliases = shellAliases;
    shellAliases = shared.shellAliases;
    extraConfig = ''
      # Rose Pine theme colors for nushell
      let rose_pine_theme = {
        # Special
        background: '#191724'
        foreground: '#e0def4'

        # Colors
        black: '#26233a'
        red: '#eb6f92'
        green: '#31748f'
        yellow: '#f6c177'
        blue: '#9ccfd8'
        magenta: '#c4a7e7'
        cyan: '#ebbcba'
        white: '#e0def4'

        # Bright colors
        bright_black: '#6e6a86'
        bright_red: '#eb6f92'
        bright_green: '#31748f'
        bright_yellow: '#f6c177'
        bright_blue: '#9ccfd8'
        bright_magenta: '#c4a7e7'
        bright_cyan: '#ebbcba'
        bright_white: '#e0def4'
      }

      # Set the theme
      $env.config = ($env.config | default {})
      $env.config.color_config = $rose_pine_theme
    '';
  };

  programs.oh-my-posh = {
    enable = true;
    enableNushellIntegration = true;
    settings = builtins.fromJSON (builtins.readFile ./omp.json);
  };

  programs.zellij = {
    enable = true;
    settings = {
      default_shell = "nu";
      theme = "rose-pine";
      themes = {
        rose-pine = {
          fg = "#e0def4";
          bg = "#191724";
          black = "#26233a";
          red = "#eb6f92";
          green = "#31748f";
          yellow = "#f6c177";
          blue = "#9ccfd8";
          magenta = "#c4a7e7";
          cyan = "#ebbcba";
          white = "#e0def4";
          orange = "#f6c177";
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
