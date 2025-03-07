# Common shell configuration
{ config, lib, pkgs, isDarwin, isLinux, isWSL, ... }:

{
  # Common shell aliases
  programs.bash = {
    enable = true;
    shellAliases = {
      ga = "git add";
      gc = "git commit";
      gco = "git checkout";
      gd = "git diff";
      gs = "git status";
      gp = "git push";
      gpl = "git pull";
      gl = "git log";
      vim = "nvim";
      vi = "nvim";
      ls = "ls --color=auto";
      ll = "ls -l";
      la = "ls -la";
      grep = "grep --color=auto";
    };
  };
  
  # Fish shell configuration
  programs.fish = {
    enable = true;
    shellAliases = {
      ga = "git add";
      gc = "git commit";
      gco = "git checkout";
      gd = "git diff";
      gs = "git status";
      gp = "git push";
      gpl = "git pull";
      gl = "git log";
      vim = "nvim";
      vi = "nvim";
      ls = "ls --color=auto";
      ll = "ls -l";
      la = "ls -la";
      grep = "grep --color=auto";
    };
    
    plugins = [
      {
        name = "z";
        src = pkgs.fetchFromGitHub {
          owner = "jethrokuan";
          repo = "z";
          rev = "ddeb28a7b6a1f0ec6dae40c636e5ca4908ad160a";
          sha256 = "0c5i7sdrsp0q3vbziqzdyqn4fmp235ax4mn4zslrswvn8g3fvdyh";
        };
      }
      {
        name = "fish-ssh-agent";
        src = pkgs.fetchFromGitHub {
          owner = "danhper";
          repo = "fish-ssh-agent";
          rev = "fd70a2afdd03caf9bf609746bf6b993b9e83be57";
          sha256 = "1fvl23y9lylj4nz6k7yfja6v9jlsg8jffs2m5mq0ql4ja5vi5pkv";
        };
      }
    ];
    
    interactiveShellInit = ''
      set -g theme_color_scheme terminal
      fish_vi_key_bindings
    '';
  };
  
  # Direnv configuration
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    nix-direnv.enable = true;
    stdlib = ''
      use_flake() {
        watch_file flake.nix
        watch_file flake.lock
        watch_file shell.nix
        eval "$(nix print-dev-env --profile "$(direnv_layout_dir)/flake-profile")"
      }
    '';
  };
  
  # Dotfiles for shell environments
  home.file = {
    ".inputrc".source = ../joost/inputrc;
    ".gdbinit".source = ../joost/gdbinit;
  };
}