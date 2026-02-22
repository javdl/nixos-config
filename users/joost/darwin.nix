{ inputs, pkgs, currentSystemName, lib, ... }:

let
  # Machines that only get core casks (no creative/personal apps)
  isOffice = builtins.elem currentSystemName [ "fu146" ];

  # Core casks installed on all machines
  coreCasks = [
    # "bitwarden" Must be installed via Mac App Store for browser integration to work
    # However, non-App Store version is required for SSH agent to work
    "bitwarden"
    "airfoil"
    "beeper"
    "brave-browser"
    "chatgpt"
    "claude"
    "chromedriver"
    "cleanshot"
    "codex"
    "codex-app"
    "companion" # Bitfocus companion, Streamdeck extension and emulation software
    "datagrip"
    "dataspell"
    "dbeaver-community" # dbeaver-bin doesnt work on MacOS?
    # "docker" # liever Colima # when really need Docker, liever alleen CLI
    "dropbox"
    "ente"
    "ente-auth"
    "figma"
    "firefox"
    "geekbench"
    "geekbench-ai"
    "ghostty" # broken in nixpkgs
    "github" # desktop
    "google-chrome"
    "google-drive"
    "gpg-suite"
    "hammerspoon"
    "imageoptim"
    "insync"
    "istat-menus"
    "jetbrains-gateway"
    "jetbrains-toolbox"
    "librewolf"
    "libreoffice"
    # "logitech-g-hub" # Disabled - errors on each make switch
    "macwhisper"
    "obsidian"
    # "ollama-app"
"pycharm"
    "podman-desktop"
    "rapidapi"
    "raycast" # for searching nix GUI apps (nix doesnt put bin in Applications folder so macos search doesnt work)
    "rustrover"
    "signal"
    "stats" # macOS system monitor in menu bar
    "sublime-text"
    "superwhisper"
    "tailscale-app" # GUI apps via Brew
    "termius"
    "thunderbird"
    "veracrypt"
    "vlc"
    "warp"
    "webstorm"
    "zed"
  ];

  # Creative, audio production, and personal casks (skip on office machines)
  personalCasks = [
    # handmatig installeren:
    # ableton-live 12
    # davinci-resolve
    # most plugins fabfilter
    # shure update utility
    # dirac live processor
    "adobe-dng-converter"
    "affinity-designer"
    "affinity-photo"
    "affinity-publisher"
    # "arturia-software-center" # broken or breaks existing installation
    "audio-hijack"
    # "advanced-renamer" # download fails
    "balenaetcher"
    "calibre"
    "digikam"
    "fabfilter-pro-c"
    "fabfilter-pro-ds"
    "fabfilter-pro-g"
    "ilok-license-manager"
    "imazing-profile-editor"
    "izotope-product-portal"
    "kobo"
    "licecap"
    "loopback" # Rogue Amoeba
    "macfuse"
    "mixxx" # open traktor
    "monodraw"
    "native-access"
    "obs"
    "reaper"
    "rode-central" # firmware update
    "screenflow"
    "softube-central" # ua connect NA
    # "soundtoys" broken / needs check
    "soundsource" # Rogue Amoeba, allows headphone EQ presets
    # "screenpipe" outdated on brew
    "spitfire-audio"
    "tdr-kotelnikov"
    "tdr-molotok"
    "tdr-nova"
    "tdr-prism"
    "transmission"
    # "vmware-fusion" # Disabled because you need a Broadcom profile
    "wacom-tablet"
    "waves-central"
  ];
in
{

  homebrew = {
    enable = true;
    taps = [
      "bearcove/tap"
      "dicklesworthstone/tap"
      "workos/tap"
    ];
    brews = [
      "bearcove/tap/home"
      "dicklesworthstone/tap/bv" # beads_viewer - view BAML beads files
      "dicklesworthstone/tap/caam" # coding agent account manager - auth switching
      # "dicklesworthstone/tap/cass"  # Now built from source via Nix overlay
      "dicklesworthstone/tap/cm" # CASS Memory - procedural memory system for AI agents
      "gifski" # Highest-quality GIF encoder
      "podman"
      "protobuf"
      "tailscale"
      "vercel-cli"
      "workos/tap/workos-cli"
    ];
    casks = coreCasks ++ lib.optionals (!isOffice) personalCasks;
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

  # Set default applications for file types using duti
  environment.systemPackages = [ pkgs.duti ];

  system.activationScripts.postActivation.text = ''
    # Set RustRover as default editor for dev files
    # Using || true to ignore errors for file types the app doesn't declare support for
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .json all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .md all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .yaml all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .yml all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .toml all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .rs all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .py all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .js all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .ts all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .tsx all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .jsx all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .css all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .scss all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .nix all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .sh all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .txt all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .xml all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .sql all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .go all || true
    ${pkgs.duti}/bin/duti -s com.jetbrains.rustrover .lua all || true
  '';
}
