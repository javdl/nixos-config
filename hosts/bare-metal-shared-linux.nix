{ config, pkgs, lib, currentSystem, currentSystemName,... }:

let
#  my-python-packages = ps: with ps; [
#    poetry
#    pip
#    pandas
#    requests
    # other python packages
#  ];

in {

  imports = [
    ../modules/specialization/plasma.nix
    ../modules/specialization/i3.nix
    ../modules/cachix.nix
  ];

  # Be careful updating this.
  #boot.kernelPackages = pkgs.linuxPackages_latest;
  #boot.kernelPackages = pkgs.linuxKernel.packages.linux_6_6; # 6.10 gives problems with nvidia drivers, 6.6 is last LTS

  # Electron an Chromium under Wayland
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # OBS virtual camera
#  boot.extraModulePackages = with config.boot.kernelPackages; [
#    v4l2loopback
#  ];
#  boot.extraModprobeConfig = ''
#    options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
#  '';
  security.polkit.enable = true;

  # Thunderbolt. Devices might need to be enrolled:
  # https://nixos.wiki/wiki/Thunderbolt
  services.hardware.bolt.enable = true;

  system.autoUpgrade.enable = true;
  #system.autoUpgrade.allowReboot = true;

  nix = {
    # use unstable nix so we can access flakes
    package = pkgs.nixVersions.latest;
    extraOptions = ''
      experimental-features = nix-command flakes
      keep-outputs = true
      keep-derivations = true
    '';

    # Cache settings moved to ../modules/cachix.nix

    # Automate garbage collection / Make sure boot does not get full
    gc = {
      automatic = true;
      randomizedDelaySec = "14m";
      options = "--delete-older-than 120d";
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = _: true;

  nixpkgs.config.permittedInsecurePackages = [
    # Needed for k2pdfopt 2.53.
    "mupdf-1.17.0"
  ];

  # Enable virtualisation support
  virtualisation.libvirtd.enable = true;
  users.extraUsers.joost.extraGroups = [ "audio" "libvirtd" "docker" ];

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;

  systemd.network.wait-online.anyInterface = true; # block for no more than one interface, prevents waiting 90secs at boot for network adapters, as long as at least 1 is connected.
  systemd.services.NetworkManager-wait-online.enable = false; # https://github.com/NixOS/nixpkgs/issues/180175

  # Disable the GNOME3/GDM auto-suspend feature that cannot be disabled in GUI!
  # If no user is logged in, the machine will power down after 20 minutes.
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # Virtualization settings
  virtualisation.docker.enable = true;

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable tailscale. We manually authenticate when we want with
  # "sudo tailscale up". If you don't use tailscale, you should comment
  # out or delete all of this.
  services.tailscale.enable = true;
  services.resolved.enable = true;
  # Per Enabling HTTPS in the Tailscale documentation, run the following:
  # sudo tailscale cert ${MACHINE_NAME}.${TAILNET_NAME} # = full domain from tailscale web ui


  # Manage fonts. We pull these from a secret directory since most of these
  # fonts require a purchase.
  fonts = {
    fontDir.enable = true;

    packages = [
      pkgs.fira-code
      pkgs.jetbrains-mono
      pkgs.font-awesome # waybar icons
      pkgs.noto-fonts
      pkgs.noto-fonts-cjk-sans
      pkgs.noto-fonts-emoji
      pkgs.liberation_ttf
      pkgs.fira-code-symbols
      pkgs.mplus-outline-fonts.githubRelease
      pkgs.dina-font
      pkgs.proggyfonts
      pkgs.rubik
    ];
  };

  networking.extraHosts = ''
    0.0.0.0 telemetry.crewai.com
  '';

  # Looking at https://github.com/ollama/ollama/tree/main/llm
  # needs to update llama.cpp to a newer version that supports the
  # .#opencl version in the llama.cpp flake. Then hopefully provide
  # options to build with that. Otherwise look at the docker containers:
  #
  # ghcr.io/ggerganov/llama.cpp:light-intel-b3868
  # ghcr.io/ggerganov/llama.cpp:server-intel-b3868
  #
  # They have the binaries but not the libraries. I'd need both to link
  # with ollama
  services.ollama.enable = true;
  services.open-webui = {
    enable = true;
    port = 3001;
  };

  # TODO: try when not broken: services.private-gpt.enable = true;
  # TODO: try comfyanonymous/ComfyUI pkg?

  #python3SystemPackages = with pkgs.python3Packages; [
  #  # vllm
  #  instructor
  #  huggingface-hub
  #  llm
  #  local.llm-claude-3
  #  local.llm-ollama
  #];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [

    aichat
    aider-chat
    code-cursor
    fabric-ai
    #local.files-to-prompt
    lmstudio # to try, open-webui-like?
    #local.magic-cli
    mods # pipe command output to a question
    openai-whisper
    pandoc # Test html -> markdown
    #local.repopack # Testing
    shell-gpt # $ sgpt ...
    tgpt # $ tgpt question

    code-server # since vs code remote ssh doesnt work, use an alternative

    brave
    gnumake
    ghostty
    gimp
    nautilus
    killall
    python311
    python311Packages.pip
    # python311.withPackages my-python-packages
    # python311Packages.pip
    rxvt-unicode-unwrapped
    #spotify
    #thunderbird
    vlc
    # vscode-fhs
    # vscodium-fhs
    xclip

    argc
    jq

    # For hypervisors that support auto-resizing, this script forces it.
    # I've noticed not everyone listens to the udev events so this is a hack.
    (writeShellScriptBin "xrandr-auto" ''
      xrandr --output Virtual-1 --auto
    '')
  ] ++ lib.optionals (currentSystemName == "vm-aarch64") [
    # This is needed for the vmware user tools clipboard to work.
    # You can test if you don't need this by deleting this and seeing
    # if the clipboard sill works.
    gtkmm3
  ];

  # Our default non-specialised desktop environment.
  services.xserver = lib.mkIf (config.specialisation != {}) {
    enable = true;
    xkb.layout = "us";
    desktopManager.gnome.enable = true;
    displayManager.gdm.enable = true;
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
  services.openssh.settings.PermitRootLogin = "no";

  networking.firewall.enable = true;
}
