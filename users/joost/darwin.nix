{ inputs, pkgs, ... }:

{
  nixpkgs.overlays = import ../../lib/overlays.nix ++ [
    (import ./vim.nix { inherit inputs; })

  ];

  homebrew = {
    enable = true;
    taps = [
    ];
    brews = [
      "jq"
      "baobab"
      ];
    casks  = [
      # "bitwarden" Must be installed via Mac App Store for browser integration to work
      "affinity-designer"
      "affinity-photo"
      "calibre"
      "chromedriver"
      "cleanshot"
      "cursor"
      "digikam"
      "dbeaver-community" # dbeaver-bin doesnt work on MacOS?
      # "docker" #liever alleen CLI. geeft ook compaudit error bij elke shell-open vanwege de docker-completions. Installeren met `brew install docker --cask`, als docker eerder handmatig is geinstalleerd soms nodig om met rm eea te verwijderen.
      "dropbox"
      "figma"
      "firefox"
      # "github" # only Intel, arm64 must be downloaded from website
      # "google-cloud-sdk" # see gdk
      "geekbench"
      "geekbench-ai"
      "ghostty" # broken in nixpkgs
      "google-drive"
      "gpg-suite"
      "hammerspoon"
      "imageoptim"
      "istat-menus"
      "licecap"
      "librewolf"
      "libreoffice"
      "macfuse"
      "monodraw"
      "mx-power-gadget"
      "obs"
      "piwix" # offline wikipedia<D-s>
      "obsidian"
      "rapidapi"
      "screenflow"
      "sublime-text"
      "thunderbird"
      "veracrypt"
      "visual-studio-code"
      "vlc"
      "wacom-tablet"
      "zed"
    ];
  };

  # The user should already exist, but we need to set this up so Nix knows
  # what our home directory is (https://github.com/LnL7/nix-darwin/issues/423).
  users.users.joost = {
    home = "/Users/joost";
    shell = pkgs.fish;
  };
}
