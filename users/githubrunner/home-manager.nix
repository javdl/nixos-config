{ config, lib, pkgs, ... }:

{
  # Basic home-manager configuration for GitHub runner on Ubuntu
  home = {
    username = "githubrunner";  # Use the actual user running this
    homeDirectory = "/home/githubrunner";
    stateVersion = "25.05";
  };

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  # Basic shell setup
  programs.bash = {
    enable = true;
    enableCompletion = true;
  };

  # Git configuration for the runner
  programs.git = {
    enable = true;
    userName = "GitHub Runner";
    userEmail = "runner@localhost";
    delta = {
      enable = true;
      options = {
        line-numbers = true;
        side-by-side = true;
      };
    };
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };

  # Basic development tools
  home.packages = with pkgs; [
    # Core utilities
    coreutils
    curl
    wget
    unzip
    zip

    # Build tools
    gnumake
    gcc
    cmake

    # Development tools
    nodejs_22
    python3
    docker
    docker-compose

    # GitHub Actions dependencies
    gh
    git
    git-lfs
    jq
    yq

    # Languages and runtimes
    temurin-bin-21  # Eclipse Temurin (Adoptium JDK)
    erlang
    mono
    R

    # Browsers
    chromium
    firefox
    # microsoft-edge # UNFREE

    # Databases
    mongodb-tools
    postgresql

    # Cloud tools
    google-cloud-sdk
    heroku

    # Monitoring
    htop
    ncdu

    # Text processing
    ripgrep
    fd
    bat
    delta           # Better git diffs
  ];

  # Environment variables
  home.sessionVariables = {
    EDITOR = "vim";
  };

  # Basic vim configuration
  programs.vim = {
    enable = true;
    settings = {
      number = true;
      relativenumber = true;
      expandtab = true;
      shiftwidth = 2;
      tabstop = 2;
    };
  };

  # SSH client configuration
  programs.ssh = {
    enable = true;
    compression = true;
    serverAliveInterval = 60;
    serverAliveCountMax = 3;
  };

  programs.helix = {
    enable = true;
    defaultEditor = false;

    settings = {
      editor = {
        line-number = "relative";
        cursorline = true;
        true-color = true;

        cursor-shape = {
          insert = "bar";
          normal = "block";
          select = "underline";
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
          };
          C-s = ":w";
        };
        insert = {
          C-s = ":w";
        };
      };
    };
  };

  # Direnv for automatic environment loading
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
