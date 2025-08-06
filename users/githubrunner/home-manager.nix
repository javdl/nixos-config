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
    microsoft-edge

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

  # Direnv for automatic environment loading
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
