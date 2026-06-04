{ inputs, pkgs, currentSystemName, lib, ... }:

let
  # Machines that get a minimal set of casks (scraping/browsing focus, or
  # headless macOS servers that should stay lean — see serversMacos below).
  isMinimal = builtins.elem currentSystemName [ "fu146" "argon" "radon" ];

  # Per-host extra casks layered on top of the base set.
  extraCasks = lib.optionals (currentSystemName == "radon") [ "rouvy" ];

  # Machines without audio production tools
  noAudio = builtins.elem currentSystemName [ "macbook-air-m4" ];

  # Minimal casks for scraping-focused machines (fu146)
  minimalCasks = [
    "bitwarden"
    # Browsers
    "brave-browser"
    "firefox"
    "firefox@developer-edition"
    "google-chrome"
    # "librewolf"
    "zen"
    # Essential tools
    "codexbar" # steipete/tap - Codex menu bar app
    "companion" # Bitfocus companion, Streamdeck extension and emulation software
    "google-drive"
    "insync"
    "istat-menus"
    "libreoffice"
    "linear"
    "obsidian"
    "podman-desktop"
    "raycast" # for searching nix GUI apps
    "tailscale-app"
    "zed"
  ];

  # servers-macos: Mac hardware used as headless/always-on servers.
  # These hosts run tailscaled as a root launchd daemon instead of the GUI
  # cask, so we strip "tailscale-app" from their cask set.
  serversMacos = [ "argon" "radon" ];
  withoutServerCasks = casks:
    if builtins.elem currentSystemName serversMacos
    then builtins.filter (cask: cask != "tailscale-app") casks
    else casks;

  # Core casks installed on all non-minimal machines
  coreCasks = [
    # "bitwarden" Must be installed via Mac App Store for browser integration to work
    # However, non-App Store version is required for SSH agent to work
    "bitwarden"
    "airfoil"
    "beeper"
    "caffeine"
    "brave-browser"
    "chatgpt"
    "claude"
    "cleanshot"
    "codex-app" # OpenAI Codex desktop app
    "codexbar" # steipete/tap - Codex menu bar app
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
    "granola"
    "hammerspoon"
    "imageoptim"
    "insync"
    "istat-menus"
    "jetbrains-gateway"
    "jetbrains-toolbox"
    # "librewolf"
    "linear"
    "legcord"
    "lm-studio"
    "libreoffice"
    # "logitech-g-hub" # Disabled - errors on each make switch
    "macwhisper"
    "obsidian"
    # "ollama-app"
"pycharm"
    "podman-desktop"
    "rapidapi"
    "raycast" # for searching nix GUI apps (nix doesnt put bin in Applications folder so macos search doesnt work)
    "rustdesk"
    "rustrover"
    "signal"
    "stats" # macOS system monitor in menu bar
    "sublime-text"
    "superwhisper"
    "tailscale-app" # GUI apps via Brew
    "telegram-desktop"
    "termius"
    "thunderbird"
    "veracrypt"
    "vlc"
    "warp"
    "webstorm"
    "zed"
  ];

  # Creative and personal casks (skip on minimal machines)
  personalCasks = [
    "adobe-dng-converter"
    # Unified Affinity app (v3) — replaces the discontinued affinity-{designer,photo,publisher} casks
    "affinity"
    # "arturia-software-center" # broken or breaks existing installation
    "audio-hijack"
    # "advanced-renamer" # download fails
    "balenaetcher"
    "calibre"
    "imazing-profile-editor"
    "kobo"
    "lm-studio"
    "licecap"
    "loopback" # Rogue Amoeba
    "macfuse"
    "monodraw"
    "obs"
    "paper-design"
    "reaper"
    "screenflow"
    # "screenpipe" outdated on brew
    "soundsource" # Rogue Amoeba, allows headphone EQ presets
    "transmission"
    # "vmware-fusion" # Disabled because you need a Broadcom profile
    "wacom-tablet"
  ];

  # Audio production casks (only on studio/production machines)
  audioCasks = [
    # handmatig installeren:
    # ableton-live 12
    # davinci-resolve
    # most plugins fabfilter
    # shure update utility
    # dirac live processor
    "fabfilter-pro-c"
    "fabfilter-pro-ds"
    "fabfilter-pro-g"
    "ilok-license-manager"
    "izotope-product-portal"
    "mixxx" # open traktor
    "native-access"
    "rode-central" # firmware update
    "softube-central" # ua connect NA
    # "soundtoys" broken / needs check
    "spitfire-audio"
    "tdr-kotelnikov"
    "tdr-molotok"
    "tdr-nova"
    "tdr-prism"
    "waves-central"
  ];
in
{

  homebrew = {
    enable = true;
    taps = [
      "bearcove/tap"
      "dicklesworthstone/tap"
      "steipete/tap"
      "workos/tap"
    ];
    brews = [
      "bearcove/tap/home"
      "dicklesworthstone/tap/bv" # beads_viewer - view BAML beads files
      "dicklesworthstone/tap/caam" # coding agent account manager - auth switching
      # "dicklesworthstone/tap/cass"  # Now built from source via Nix overlay
      "dicklesworthstone/tap/cm" # CASS Memory - procedural memory system for AI agents
      "gifski" # Highest-quality GIF encoder
      "mole" # Deep clean and optimize your Mac (github.com/tw93/Mole)
      "pake" # Turn any webpage into a desktop app with Rust (github.com/tw93/Pake)
      "podman"
      "protobuf"
      "tailscale"
      "vercel-cli"
      "workos/tap/workos-cli"
    ];
    casks = withoutServerCasks ((if isMinimal then minimalCasks
      else coreCasks
        ++ personalCasks
        ++ lib.optionals (!noAudio) audioCasks)
      ++ extraCasks);
    masApps = { # to find ID, App Store > Share > Copy link
      # masApps reinstall or do a slow check on each run. Manual install is the best option I guess.
      # "Bitwarden" = 1352778147; # Use brew/dmg version for SSH agent to work
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
    # Set Zed as the best-effort default for stable text/source UTIs.
    if [ -d /Applications/Zed.app ]; then
      "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" -f /Applications/Zed.app >/dev/null 2>&1 || true

      # Intentionally excludes public.html so HTML files (and URL clicks
      # resolved via the html handler) open in the system default browser.
      zedDutiFailed=0
      for uti in \
        public.plain-text \
        public.text \
        public.source-code \
        public.shell-script \
        public.json \
        public.xml \
        public.css; do
        ${pkgs.duti}/bin/duti -s dev.zed.Zed "$uti" all >/dev/null 2>&1 || zedDutiFailed=1
      done

      if [ "$zedDutiFailed" -ne 0 ]; then
        echo "Some Zed default-app associations could not be applied; continuing."
      fi
    else
      echo "Skipping Zed default-app associations: /Applications/Zed.app not found"
    fi

    # Pin Brave Browser as the default for HTML files and http(s) URL clicks.
    if [ -d "/Applications/Brave Browser.app" ]; then
      braveDutiFailed=0
      for handler in \
        public.html \
        public.url-scheme.http \
        public.url-scheme.https; do
        ${pkgs.duti}/bin/duti -s com.brave.Browser "$handler" all >/dev/null 2>&1 || braveDutiFailed=1
      done

      if [ "$braveDutiFailed" -ne 0 ]; then
        echo "Some Brave default-handler associations could not be applied; continuing."
      fi
    else
      echo "Skipping Brave default-handler associations: /Applications/Brave Browser.app not found"
    fi
  '';
}
