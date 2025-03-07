{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  sources = import ../../nix/sources.nix;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  
  # Get unstable packages
  pkgsUnstable = import inputs.nixpkgs-unstable {
    inherit (pkgs) system;
    inherit (pkgs.config) allowUnfree;
    config = {
      allowUnfree = true;
      allowUnsupportedSystem = true;
    };
  };
  
  # Google Cloud SDK with selected components
  gdk = pkgs.google-cloud-sdk.withExtraComponents( with pkgs.google-cloud-sdk.components; [
    gke-gcloud-auth-plugin
    alpha
    app-engine-go
    beta
    gsutil
    kubectl
    minikube
    skaffold
    terraform-tools
  ]);

in {
  # Import common configurations
  imports = [
    ../common
  ];
  
  # Home-manager 22.11 requires this be set. We never set it so we have
  # to use the old state version.
  home.stateVersion = "18.09";

  #---------------------------------------------------------------------
  # User-specific packages
  #---------------------------------------------------------------------
  home.packages = [
    # Development tools
    pkgs.asciinema
    pkgs.air # Live reload for Go
    pkgs.dasht # Search API docs offline
    pkgs.devenv
    gdk
    pkgs.kubernetes-helm
    pkgs.libGL # ML
    pkgs.libGLU # ML
    pkgs.libheif
    pkgs.watch
    
    # Rust tools
    pkgs.rustup
    pkgs.cargo-generate
    pkgs.pre-commit
    pkgs.wasm-pack
    pkgsUnstable.fermyon-spin  # Use unstable version
    
    # Python
    pkgs.python3
    pkgs.poetry
    
    # Applications
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
    
    # Fonts
    pkgs.font-awesome # waybar icons
    pkgs.fira-code
    pkgs.fira-code-symbols
    pkgs.ibm-plex
    pkgs.liberation_ttf
    pkgs.mplus-outline-fonts.githubRelease
    pkgs.nerdfonts
    pkgs.noto-fonts
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-emoji
    pkgs.rubik
    pkgs.proggyfonts
    
    # Utilities
    pkgs.bashmount # Easily mount drives
    pkgs.flyctl
    pkgs.git-crypt
    pkgs.glab
    pkgs.k9s # Kubernetes CLI
    pkgs.neofetch
    pkgs.nixd # Nix language server
    pkgs.pocketbase
    pkgs.transmission_4
    pkgs.yubikey-manager
    
    # Node.js and packages
    pkgs.nodejs
    pkgs.nodePackages.firebase-tools
  ] 
  ++ (lib.optionals isDarwin [
    pkgs.cachix
    pkgs.tailscale
    pkgs.raycast # only for MacOS
    pkgs.pinentry_mac
  ]) 
  ++ (lib.optionals (isLinux && !isWSL) [
    pkgs.chromium
    pkgs.firefox-devedition
    pkgs.rofi
    pkgs.zathura
    pkgs.xfce.xfce4-terminal
    pkgs.libwacom
    pkgs.libinput
    pkgs.bitwarden-cli
    pkgs.bitwarden-menu
    pkgs.geekbench
    pkgs.nextcloud-client
    pkgs.obsidian
    pkgs.rpi-imager
    pkgs.tailscale-systray
    pkgs.windsurf
    pkgs.baobab # Disk usage analyzer
  ]);

  #---------------------------------------------------------------------
  # Fonts
  #---------------------------------------------------------------------
  fonts.fontconfig.enable = true;
  
  #---------------------------------------------------------------------
  # User-specific dotfiles
  #---------------------------------------------------------------------
  home.file = {
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
    "wallpapers/04167_unreachable_3840x2160.png".source = ./wallpapers/04167_unreachable_3840x2160.png;
    "i3/config".text = builtins.readFile ./i3;
    "rofi/config.rasi".text = builtins.readFile ./rofi;
  } // (if isDarwin then {
    "rectangle/RectangleConfig.json".text = builtins.readFile ./RectangleConfig.json;
  } else {}) // (if isLinux then {
    "ghostty/config".text = builtins.readFile ./ghostty.linux;
    "jj/config.toml".source = ./jujutsu.toml;
  } else {});

  #---------------------------------------------------------------------
  # User-specific GNOME settings
  #---------------------------------------------------------------------
  dconf.settings = {
    "org/gnome/shell" = {
      favorite-apps = [
        "firefox.desktop"
        "com.mitchellh.ghostty.desktop"
        "kitty.desktop"
        "windsurf.desktop"
        "org.gnome.Terminal.desktop"
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
  # User-specific program configurations
  #---------------------------------------------------------------------
  
  # Fish shell customization
  programs.fish = {
    interactiveShellInit = lib.strings.concatStrings (lib.strings.intersperse "\n" ([
      "source ${sources.theme-bobthefish}/functions/fish_prompt.fish"
      "source ${sources.theme-bobthefish}/functions/fish_right_prompt.fish"
      "source ${sources.theme-bobthefish}/functions/fish_title.fish"
      (builtins.readFile ./config.fish)
      "set -g SHELL ${pkgs.fish}/bin/fish"
    ]));
    
    plugins = map (n: {
      name = n;
      src = sources.${n};
    }) [
      "fish-fzf"
      "fish-foreign-env"
      "theme-bobthefish"
    ];
  };
  
  # Git config for this user
  programs.git = {
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
      core.askPass = ""; # needs to be empty to use terminal for ask pass
      credential.helper = "store";
      github.user = "javdl";
      
      "filter \"lfs\"" = {
        clean = "${pkgs.git-lfs}/bin/git-lfs clean -- %f";
        smudge = "${pkgs.git-lfs}/bin/git-lfs smudge --skip -- %f";
        required = true;
      };
    };
  };
  
  # Go configuration
  programs.go = {
    enable = true;
    goPath = "code/go";
    goPrivate = [ "github.com/javdl" "github.com/fuww" ];
  };
  
  # Jujutsu configuration
  programs.jujutsu.enable = true;
  
  # Tmux configuration
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
  
  # Alacritty configuration
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
  
  # Kitty configuration
  programs.kitty = {
    enable = !isWSL;
    extraConfig = builtins.readFile ./kitty;
  };
  
  # i3status configuration
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
  
  # Neovim with custom plugins
  programs.neovim = {
    package = inputs.neovim-nightly-overlay.packages.${pkgs.system}.default;
    
    withPython3 = true;
    extraPython3Packages = (p: with p; [
      jupyter-client
      cairosvg
      plotly
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
      customVim.pigeon
      customVim.AfterColors
      
      customVim.vim-nord
      customVim.nvim-comment
      customVim.nvim-lspconfig
      customVim.nvim-plenary
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
      customVim.vim-devicons
    ]);
    
    extraConfig = (import ./vim-config.nix) { inherit sources; };
  };
  
  # X resources
  xresources.extraConfig = builtins.readFile ./Xresources;
}
