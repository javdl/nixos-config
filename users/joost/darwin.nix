{ inputs, pkgs, ... }:

{
  nixpkgs.overlays = import ../../lib/overlays.nix ++ [
    (import ./vim.nix { inherit inputs; })

  ];

  homebrew = {
    enable = true;
    casks  = [
      "bitwarden"
      "calibre"
      "chromedriver"
      "cleanshot"
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
