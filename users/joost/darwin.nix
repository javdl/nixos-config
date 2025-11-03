{ inputs, pkgs, ... }:

{

  homebrew = {
    enable = true;
    taps = [
      "bearcove/tap"
      "workos/tap"
    ];
    brews = [
      "bearcove/tap/home"
      "codex"
      "gifski" # Highest-quality GIF encoder
      "mcp-toolbox"
      "podman"
      "protobuf"
      "tailscale"
      "vercel-cli"
      "workos/tap/workos-cli"
    ];
    casks  = [
      # handmatig installeren:
      # ableton-live 12
      # davinci-resolve
      # most plugins fabfilter
      # shure update utility
      # dirac live processor
      #
      # "bitwarden" Must be installed via Mac App Store for browser integration to work
      "audio-hijack"
      # "advanced-renamer" # download fails
      "airfoil"
      "affinity-designer"
      "affinity-photo"
      "affinity-publisher"
      # "arturia-software-center" # broken or breaks existing installation
      "balenaetcher"
      "brave-browser"
      "companion" # Bitfocus companion, Streamdeck extension and emulation software
      # "conductor" Manual install, doesnt work via brew. https://conductor.build/
      "calibre"
      "chatgpt"
      "claude"
      "chromedriver"
      "cleanshot"
      "conductor"
      "cursor"
      "datagrip"
      "dataspell"
      "digikam"
      "dbeaver-community" # dbeaver-bin doesnt work on MacOS?
      # "docker" # liever Colima # when really need Docker, liever alleen CLI. geeft ook compaudit error bij elke shell-open vanwege de docker-completions. Installeren met `brew install docker --cask`, als docker eerder handmatig is geinstalleerd soms nodig om met rm eea te verwijderen.
      "dropbox"
      "ente"
      "ente-auth"
      "fabfilter-pro-c"
      "fabfilter-pro-ds"
      "fabfilter-pro-g"
      "figma"
      "firefox"
      "imazing-profile-editor"
      "jetbrains-gateway"
      "jetbrains-toolbox"
      # "github" # only Intel, arm64 must be downloaded from website
      # "google-cloud-sdk" # see gdk
      "geekbench"
      "geekbench-ai"
      "ghostty" # broken in nixpkgs
      "github" # desktop
      "google-drive"
      "gpg-suite"
      "hammerspoon"
      "ilok-license-manager"
      "imageoptim"
      "istat-menus"
      "izotope-product-portal"
      "kobo"
      "licecap"
      "librewolf"
      "libreoffice"
      "loopback" # Rogue Amoeba
      "macfuse"
      "mixxx" # open traktor
      "monodraw"
      "mx-power-gadget"
      "native-access"
      "obs"
      "obsidian"
      "ollama-app"
      # "orbstack" # Use open source podman instead
      "pycharm"
      "podman-desktop"
      "reaper"
      "rapidapi"
      "raycast" # for searching nix GUI apps (nix doesnt put bin in Applications folder so macos search doesnt work)
      "rode-central" #c(firmware update)
      "rustrover"
      "screenflow"
      "signal"
      "softube-central" # ua connect NA
      # "soundtoys" broken / needs check
      "soundsource" # Rogue Amoeba, allows headphone EQ presets
      # "screenpipe" outdated on brew
      "spitfire-audio"
      "sublime-text"
      "superwhisper"
      "superhuman"
      "tailscale-app" # GUI apps via Brew
      "tdr-kotelnikov"
      "tdr-molotok"
      "tdr-nova"
      "tdr-prism"
      "tdr-vos-slickeq"
      "thunderbird"
      "veracrypt"
      "visual-studio-code"
      "vlc"
      # "vmware-fusion" # Disabled because you need a Broadcom profile. Login & Download here: https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware%20Fusion&freeDownloads=true What a shitshow!
      "wacom-tablet"
      "warp"
      "waves-central"
      "webstorm"
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
    shell = pkgs.zsh;
  };

  # Required for some settings like homebrew to know what user to apply to.
  system.primaryUser = "joost";
}
