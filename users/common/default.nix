# Common configuration shared between users
{ config, lib, pkgs, ... }:

{
  imports = [
    ./platform.nix      # Platform detection must be imported first
    ./shell.nix         # Shell configuration
    ./packages.nix      # Common packages
    ./programs.nix      # Common program settings
    ./desktop.nix       # Desktop environment settings
    ./vim.nix           # Vim/Neovim configuration
    # ./system.nix is imported directly by the nixos.nix files
  ];
}