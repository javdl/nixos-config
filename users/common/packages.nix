# Common packages for all users
{ config, lib, pkgs, isDarwin, isLinux, isWSL, ... }:

let
  # Define package groups by category
  developmentPackages = with pkgs; [
    git
    neovim
    vim
    jq
    ripgrep
    fd
    fzf
    bat
    gnumake
    gnupg
    tmux
    tree
  ];
  
  utilityPackages = with pkgs; [
    wget
    curl
    htop
    unzip
    zip
  ];
  
  # Platform-specific packages
  darwinPackages = with pkgs; lib.optionals isDarwin [
    m-cli
    terminal-notifier
  ];
  
  linuxPackages = with pkgs; lib.optionals isLinux [
    xclip
    libnotify
    lsof
  ];
  
  linuxDesktopPackages = with pkgs; lib.optionals (isLinux && !isWSL) [
    firefox
    gnome.gnome-terminal
    gnome.nautilus
    gnome.file-roller
  ];
  
in {
  # Combine package groups into a single home.packages
  home.packages = 
    developmentPackages ++
    utilityPackages ++
    darwinPackages ++
    linuxPackages ++
    linuxDesktopPackages;
}