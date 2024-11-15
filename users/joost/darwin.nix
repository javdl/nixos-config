{ inputs, pkgs, ... }:

{
  nixpkgs.overlays = import ../../lib/overlays.nix ++ [
    (import ./vim.nix { inherit inputs; })

  ];

  homebrew = {
    enable = true;
    brews = [
      "aider"
      "jq"
      ];
    casks  = [
      # "bitwarden" Must be installed via Mac App Store for browser integration to work
      "calibre"
      "chromedriver"
      "cleanshot"
      "cursor"
      "darktable"
      "digikam"
      "dbeaver-community"
      "discord"
      # "docker"
      "dropbox"
      "element"
      "figma"
      "firefox"
      "gimp"
      # "github" # only Intel, arm64 must be downloaded from website
      "google-chrome"
      "google-cloud-sdk"
      "google-drive"
      "gpg-suite"
      "hammerspoon"
      "imageoptim"
      "inkscape"
      "istat-menus"
      "licecap"
      "librewolf"
      "libreoffice"
      "monodraw"
      "mx-power-gadget"
      "obs"
      "postman"
      "rapidapi"
      "raycast"
      "rectangle"
      "screenflow"
      "slack"
      "spotify"
      "sublime-text"
      "telegram"
      "thunderbird"
      "typora"
      "veracrypt"
      "visual-studio-code"
      "vlc"
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
