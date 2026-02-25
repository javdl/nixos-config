{ isWSL, inputs, pkgs, lib, isDarwin, isLinux }:

let
  # For our MANPAGER env var
  # https://github.com/sharkdp/bat/issues/1145
  manpager = (pkgs.writeShellScriptBin "manpager" (if isDarwin then ''
    sh -c 'col -bx | bat -l man -p'
    '' else ''
    cat "$1" | col -bx | bat --language man --style plain
  ''));
in {
  # Common shell aliases for both users
  shellAliases = {
    # Jujutsu aliases
    jd = "jj desc";
    jf = "jj git fetch";
    jn = "jj new";
    jp = "jj git push";
    js = "jj st";

    # Omakub-style shell tool aliases
    ff = "fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"; # Fuzzy find with preview
    ls = "eza --icons --group-directories-first"; # Better ls with icons
    lsa = "eza --icons --group-directories-first -a"; # ls including hidden files
    lt = "eza --icons --group-directories-first --tree --level=2"; # Tree view 2 levels deep
    lta = "eza --icons --group-directories-first --tree --level=2 -a"; # Tree view with hidden files

    # Omakub-style TUI aliases
    lzg = "lazygit"; # Launch lazygit
    lzd = "lazydocker"; # Launch lazydocker

    # Zellij shortcuts
    z = "zellij"; # Start zellij
    za = "zellij attach -c"; # Attach or create new session

    # AI coding agent aliases
    cc = "claude";
    cod = "codex";
    gmi = "gemini";

    # Beads (issue tracker) - use Rust version (br) as default
    bd = "br";
  } // (if isLinux then {
    # Two decades of using a Mac has made this such a strong memory
    # that I'm just going to keep it consistent.
    pbcopy = "xclip";
    pbpaste = "xclip -o";
  } else {});

  # Expose the manpager for use in home-manager configs
  manpager = manpager;

  # Common session variables
  sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    EDITOR = "nvim";
    PAGER = "less -FirSwX";
    MANPAGER = "${manpager}/bin/manpager";
  };

  # Common fish plugins - removed with niv
  fishPlugins = [
    # Fish plugins were previously managed by niv
    # "fish-fzf"
    # "fish-foreign-env"
    # "theme-bobthefish"
  ];

  # Common direnv configuration
  direnvConfig = {
    whitelist = {
      prefix = [
        "$HOME/code/go/src/github.com/fuww"
        "$HOME/code/go/src/github.com/javdl"
      ];

      exact = ["$HOME/.envrc"];
    };
  };

  # Common Gnome settings
  dconfSettings = {
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
}
