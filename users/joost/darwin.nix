{ inputs, pkgs, ... }:

{
  nixpkgs.overlays = import ../../lib/overlays.nix ++ [
    (import ./vim.nix { inherit inputs; })
  ];

  homebrew = {
    enable = true;
    taps = [
      "bearcove/tap"
    ];
    brews = [
      "bearcove/tap/home"
    ];
    casks  = [
      # "bitwarden" Must be installed via Mac App Store for browser integration to work
      "affinity-designer"
      "affinity-photo"
      "calibre"
      "chatgpt"
      "claude"
      "chromedriver"
      "cleanshot"
      "cursor"
      "digikam"
      "dbeaver-community" # dbeaver-bin doesnt work on MacOS?
      # "docker" # liever Colima # when really need Docker, liever alleen CLI. geeft ook compaudit error bij elke shell-open vanwege de docker-completions. Installeren met `brew install docker --cask`, als docker eerder handmatig is geinstalleerd soms nodig om met rm eea te verwijderen.
      "dropbox"
      "figma"
      "firefox"
      # "github" # only Intel, arm64 must be downloaded from website
      # "google-cloud-sdk" # see gdk
      "geekbench"
      "geekbench-ai"
      "ghostty" # broken in nixpkgs
      "github" # desktop
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
      "obsidian"
      "ollama"
      "orbstack"
      "rapidapi"
      "raycast" # for searching nix GUI apps (nix doesnt put bin in Applications folder so macos search doesnt work)
      "screenflow"
      "signal"
      # "screenpipe" outdated on brew
      "sublime-text"
      "superwhisper"
      "tailscale" # GUI apps via Brew
      "thunderbird"
      "veracrypt"
      "visual-studio-code"
      "vlc"
      # "vmware-fusion" # Disabled because you need a Broadcom profile. Login & Download here: https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware%20Fusion&freeDownloads=true What a shitshow!
      "wacom-tablet"
      "zed"
    ];
    masApps = { # to find ID, App Store > Share > Copy link
      # masApps reinstall or do a slow check on each run. Manual install is the best option I guess.
      # "Bitwarden" = 1352778147;
      # # "Kiwix" = 997079563;
      # "Tacx Training" = 892366151;
    };
  };

  # The user should already exist, but we need to set this up so Nix knows
  # what our home directory is (https://github.com/LnL7/nix-darwin/issues/423).
  users.users.joost = {
    home = "/Users/joost";
    shell = pkgs.fish;
  };

  # Required for some settings like homebrew to know what user to apply to.
  system.primaryUser = "joost";
}
