{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  sources = import ../../nix/sources.nix;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  # For our MANPAGER env var
  # https://github.com/sharkdp/bat/issues/1145
  manpager = (pkgs.writeShellScriptBin "manpager" (if isDarwin then ''
    sh -c 'col -bx | bat -l man -p'
    '' else ''
    cat "$1" | col -bx | bat --language man --style plain
  ''));

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
    pkgs.kubernetes-helm
    pkgs.libGL # ML
    pkgs.libGLU # ML
    pkgs.libheif
    pkgs.ripgrep
    pkgs.tree
    pkgs.watch
    pkgs.xh # for sending HTTP requests (like HTTPie)

    # Rust should be in flake.nix for each project. However, those configs do need an initial Cargo.lock.Therefore, to create new projects we want Rust globally installed.
    pkgs.rustup # rust-analyzer, cargo # installed by rustup
    # pkgs.rust-script
    # pkgs.rustc
    pkgs.pre-commit
    pkgs.wasm-pack
    pkgs.fermyon-spin

    pkgs.python3
    pkgs.poetry

    pkgs.aichat
    pkgs.aider-chat
    pkgs.darktable
    pkgs.dbeaver-bin
    pkgs.discord
    pkgs.element-web
    pkgs.gimp
    pkgs.google-chrome
    pkgs.inkscape
    pkgs.postman
    pkgs.slack
    pkgs.spotify
    pkgs.telegram-desktop

    pkgs.font-awesome # waybar icons
    pkgs.fira-code
    pkgs.fira-code-symbols
    pkgs.ibm-plex
    pkgs.jetbrains-mono
    pkgs.liberation_ttf
    pkgs.mplus-outline-fonts.githubRelease
    pkgs.nerdfonts
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
    pkgs.tailscale
    pkgs.transmission_4
    pkgs.yubikey-manager

    # pkgs.zed # Broken

    # Node is required for Copilot.vim
    pkgs.nodejs
    pkgs.nodePackages.firebase-tools
  ] ++ (lib.optionals isDarwin [
    # This is automatically setup on Linux
    pkgs.cachix
    pkgs.tailscale
    pkgs.raycast # only for MacOS
    pkgs.pinentry_mac
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
    pkgs.nextcloud-client
    pkgs.obsidian
    pkgs.rpi-imager
    # pkgs.sublime4 # needs old openssl?
    pkgs.tailscale-systray
    pkgs.baobab # Disk usage, gnome only
  ]);

  #---------------------------------------------------------------------
  # Env vars and dotfiles
  #---------------------------------------------------------------------

  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    EDITOR = "nvim";
    PAGER = "less -FirSwX";
    MANPAGER = "${manpager}/bin/manpager";
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
    # "zed/settings.json".text = builtins.readFile ./zed.json; # breaks Zed; i.e. changing llm

    # tree-sitter parsers
    "nvim/parser/proto.so".source = "${pkgs.tree-sitter-proto}/parser";
    "nvim/queries/proto/folds.scm".source =
      "${sources.tree-sitter-proto}/queries/folds.scm";
    "nvim/queries/proto/highlights.scm".source =
      "${sources.tree-sitter-proto}/queries/highlights.scm";
    "nvim/queries/proto/textobjects.scm".source =
      ./textobjects.scm;
  } // (if isDarwin then {
    # Rectangle.app. This has to be imported manually using the app.
    "rectangle/RectangleConfig.json".text = builtins.readFile ./RectangleConfig.json;
  } else {}) // (if isLinux then {
    "ghostty/config".text = builtins.readFile ./ghostty.linux;
    "jj/config.toml".source = ./jujutsu.toml;
  } else {});

  # Gnome settings
  # Use `dconf watch /` to track stateful changes you are doing, then set them here.
  dconf.settings = {
    "org/gnome/shell" = {
      favorite-apps = [
          "firefox.desktop"
          "ghostty.desktop"
          "kitty.desktop"
          "sublimetext4.desktop"
        # "kgx.desktop" # Should be Gnome console. kgx in terminal to start it does work.
        #"vscode.desktop"
        # "codium.desktop"
        "org.gnome.Terminal.desktop"
        #"spotify.desktop"
        #"virt-manager.desktop"
        "org.gnome.Nautilus.desktop"
      ];
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      enable-hot-corners = false;
      scaling-factor = lib.hm.gvariant.mkUint32 2;
    };
    "org/gnome/desktop/wm/preferences" = {
      workspace-names = [ "Main" ];
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
    "org/gnome/settings-daemon/plugins/color" = {
      night-light-enabled = true;
      night-light-schedule-automatic = true;
    };
    "org/gnome/settings-daemon/plugins/power" = {
      sleep-inactive-ac-type = "nothing";
      power-button-action = "interactive";
    };
  };

  #---------------------------------------------------------------------
  # Programs
  #---------------------------------------------------------------------

  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    extensions = with pkgs.vscode-extensions; [
      bbenoist.nix
      eamodio.gitlens
      github.codespaces
      github.copilot
      ms-python.python
      ms-azuretools.vscode-docker
      ms-toolsai.jupyter
      ms-vscode-remote.remote-ssh
      vscode-icons-team.vscode-icons
    ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
      {
        name = "remote-ssh-edit";
        publisher = "ms-vscode-remote";
        version = "0.117.2025012415";
        sha256 = "1hp6gjh4xp2m1xlm1jsdzxw9d8frkiidhph6nvl24d0h8z34w49g";
      }
      {
        name = "claude-dev";
        publisher = "saoudrizwan";
        version = "3.2.5";
        sha256 = "sha256-aJnN5zjF6tvUSMqVklNgCgpsfBNi1vw0i66BBFgHB1o=";
      }
    ];
  };

  programs.gpg.enable = !isDarwin;

  programs.bash = {
    enable = true;
    shellOptions = [];
    historyControl = [ "ignoredups" "ignorespace" ];
    initExtra = ''
      ${builtins.readFile ./bashrc}
      export GPG_TTY=$(tty)
    '';

    shellAliases = {
      ga = "git add";
      gc = "git commit";
      gco = "git checkout";
      gcp = "git cherry-pick";
      gdiff = "git diff";
      gl = "git prettylog";
      gp = "git push";
      gs = "git status";
      gt = "git tag";
    };
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true; # see note on other shells below
    nix-direnv.enable = true;

    config = {
      whitelist = {
        prefix = [
          "$HOME/code/go/src/github.com/fuww"
          "$HOME/code/go/src/github.com/javdl"
        ];

        exact = ["$HOME/.envrc"];
      };
    };
  };

  programs.zsh = {
    enable = true;
    initExtra = ''
      export GPG_TTY=$(tty)
    '';
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = lib.strings.concatStrings (lib.strings.intersperse "\n" ([
      "source ${sources.theme-bobthefish}/functions/fish_prompt.fish"
      "source ${sources.theme-bobthefish}/functions/fish_right_prompt.fish"
      "source ${sources.theme-bobthefish}/functions/fish_title.fish"
      (builtins.readFile ./config.fish)
      "set -g SHELL ${pkgs.fish}/bin/fish"
      "set -gx GPG_TTY (tty)"
    ]));

    shellAliases = {
      ga = "git add";
      gc = "git commit";
      gco = "git checkout";
      gcp = "git cherry-pick";
      gdiff = "git diff";
      gl = "git prettylog";
      gp = "git push";
      gs = "git status";
      gt = "git tag";
    } // (if isLinux then {
      # Two decades of using a Mac has made this such a strong memory
      # that I'm just going to keep it consistent.
      pbcopy = "xclip";
      pbpaste = "xclip -o";
    } else {});

    plugins = map (n: {
      name = n;
      src  = sources.${n};
    }) [
      "fish-fzf"
      "fish-foreign-env"
      "theme-bobthefish"
    ];
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

      run-shell ${sources.tmux-pain-control}/pain_control.tmux
      run-shell ${sources.tmux-dracula}/dracula.tmux
    '';
  };

  programs.alacritty = {
    enable = !isWSL;

    settings = {
      env.TERM = "xterm-256color";

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
      customVim.vim-copilot
      customVim.vim-cue
      customVim.vim-fish
      customVim.vim-fugitive
      customVim.vim-glsl
      customVim.vim-misc
      customVim.vim-pgsql
      customVim.vim-tla
      # customVim.vim-zig
      customVim.pigeon
      customVim.AfterColors

      customVim.vim-nord
      customVim.nvim-comment
      customVim.nvim-lspconfig
      customVim.nvim-plenary # required for telescope
      customVim.nvim-telescope
      customVim.nvim-treesitter
      customVim.nvim-treesitter-playground
      customVim.nvim-treesitter-textobjects

      vimPlugins.vim-airline
      vimPlugins.vim-airline-themes

      vimPlugins.vim-eunuch
      vimPlugins.vim-gitgutter
      vimPlugins.vim-markdown
      vimPlugins.vim-nix
      vimPlugins.typescript-vim
      vimPlugins.nvim-treesitter-parsers.elixir
    ] ++ (lib.optionals (!isWSL) [
      # This is causing a segfaulting while building our installer
      # for WSL so just disable it for now. This is a pretty
      # unimportant plugin anyway.
      customVim.vim-devicons
    ]);

    extraConfig = (import ./vim-config.nix) { inherit sources; };
  };

  services.gpg-agent = {
    enable = isLinux;
    pinentryPackage = pkgs.pinentry-tty;

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
