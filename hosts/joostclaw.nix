{ config, pkgs, lib, inputs, ... }:

# Hetzner Cloud server for OpenClaw (AI assistant gateway)
#
# IP: 91.99.10.155
# IPv6: 2a01:4f8:c012:9be6::/64
#
# Provisioned with: make hetzner/provision NIXADDR=91.99.10.155 NIXNAME=joostclaw
#
{
  imports = [
    ../modules/hetzner-cloud-hardware.nix
    ../modules/disko-hetzner-cloud.nix
    ../modules/cachix.nix
    ../modules/secrets.nix
    ../modules/automatic-nix-gc.nix
    ../modules/nixos-auto-update.nix
    ../modules/security-audit.nix
    ../modules/podman.nix
    ../modules/openclaw-oci.nix
    ../modules/ironclaw-oci.nix
    ../modules/repo-updater.nix
    ../modules/ghostty-terminfo.nix
    ../modules/mosh.nix
  ];

  # Latest kernel for best hardware support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use systemd-boot for UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Hostname
  networking.hostName = "joostclaw";

  # Timezone (UTC for servers)
  time.timeZone = "UTC";

  # Nix configuration
  nix = {
    package = pkgs.nixVersions.latest;
    extraOptions = ''
      experimental-features = nix-command flakes
      keep-outputs = true
      keep-derivations = true
    '';
  };

  # Disk-based garbage collection — smaller disk (76GB), trigger earlier
  services.automaticNixGC = {
    enable = true;
    minFreeGB = 10;
    maxFreeGB = 20;
    scheduledThresholdGB = 10;
    keepDays = 7;
  };

  # Automatic NixOS updates from git repository
  services.nixosAutoUpdate = {
    enable = true;
    flake = "github:javdl/nixos-config#joostclaw";
    dates = "04:00";
    randomizedDelaySec = "30m";
    allowReboot = false;
  };

  # Repo updater - periodic git sync for development repos
  services.repoUpdater = {
    enable = true;
    user = "joost";
    projectsDir = "/home/joost/code";
    timerInterval = "6h";
    repos = [
      "fuww/developer"
    ];
  };

  # Security auditing with auditd
  services.securityAudit = {
    enable = true;
    failureMode = "printk";
    maxLogFile = 50;
    numLogs = 10;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = _: true;

  # Networking - dual stack (IPv4 via DHCP + static IPv6)
  networking.useDHCP = true;
  networking.interfaces.enp1s0.ipv6.addresses = [{
    address = "2a01:4f8:c012:9be6::1";
    prefixLength = 64;
  }];
  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = "enp1s0";
  };

  # Firewall
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # SSH daemon - key-only auth for security
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
      KbdInteractiveAuthentication = false;
    };
  };

  # Don't require password for sudo
  security.sudo.wheelNeedsPassword = false;

  # Immutable users (passwords managed via config)
  users.mutableUsers = false;

  # Docker for containerized development
  virtualisation.docker.enable = true;

  # Podman for rootless containers
  virtualisation.podmanConfig = {
    enable = true;
    dockerCompat = false;
    autoPrune = true;
  };

  # System packages
  environment.systemPackages = with pkgs; [
    git gnumake htop btop tmux
    curl wget rsync
    gcc neovim
    jq ripgrep fd tree unzip zip
    molly-guard
  ];

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";

  # Use zsh as default shell
  programs.zsh.enable = true;
  users.users.joost.shell = lib.mkForce pkgs.zsh;
  users.users.joost.linger = true;

  # Run dynamically linked binaries without patchelf
  programs.nix-ld.enable = true;

  # TCP BBR congestion control
  boot.kernelModules = [ "tcp_bbr" ];

  # System limits and performance tuning
  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;
    "fs.file-max" = 2097152;
    "kernel.pid_max" = 4194303;
    "net.core.somaxconn" = 65535;
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq";
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_rmem" = "4096 87380 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";
    "net.ipv6.conf.all.forwarding" = true;
  };

  # PAM limits
  security.pam.loginLimits = [
    { domain = "*"; type = "soft"; item = "nofile"; value = "65536"; }
    { domain = "*"; type = "hard"; item = "nofile"; value = "65536"; }
  ];

  # Disable unnecessary services for a headless server
  services.xserver.enable = false;
  services.printing.enable = false;
  services.pulseaudio.enable = false;

  # Enable useful services
  services.nscd.enable = true;
  services.dbus.enable = true;

  # Tailscale for secure access with SSH
  services.tailscale = {
    enable = true;
    authKeyFile = "/etc/tailscale/authkey";
    extraUpFlags = [
      "--ssh"
      "--accept-routes"
      "--accept-dns=false"
      "--advertise-exit-node"
    ];
  };

  # Allow Tailscale traffic through firewall
  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  # SOPS secrets for OpenClaw + Tailscale auth.
  sops.defaultSopsFile = ../secrets/joostclaw.yaml;
  sops.secrets.openclaw-telegram-bot-token = {
    owner = "joost";
    group = "users";
    mode = "0400";
  };
  sops.secrets.openclaw-anthropic-api-key = {
    owner = "joost";
    group = "users";
    mode = "0400";
  };
  sops.secrets.openclaw-gateway-token = {
    owner = "joost";
    group = "users";
    mode = "0400";
  };
  sops.secrets.openclaw-work01-telegram-bot-token = {
    owner = "openclaw-work01";
    group = "openclaw-work01";
    mode = "0400";
  };
  sops.secrets.openclaw-work01-anthropic-api-key = {
    owner = "openclaw-work01";
    group = "openclaw-work01";
    mode = "0400";
  };
  sops.secrets.openclaw-work01-gateway-token = {
    owner = "openclaw-work01";
    group = "openclaw-work01";
    mode = "0400";
  };
  # IronClaw secrets
  sops.secrets.ironclaw-anthropic-api-key = {
    owner = "ironclaw-main";
    group = "ironclaw-main";
    mode = "0400";
  };
  sops.secrets.ironclaw-telegram-bot-token = {
    owner = "ironclaw-main";
    group = "ironclaw-main";
    mode = "0400";
  };
  sops.secrets.ironclaw-db-password = {
    owner = "ironclaw-main";
    group = "ironclaw-main";
    mode = "0400";
  };
  sops.secrets.tailscale-authkey = {
    path = "/etc/tailscale/authkey";
    owner = "root";
    group = "root";
    mode = "0400";
  };

  # PostgreSQL with pgvector for IronClaw
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    extensions = ps: [ ps.pgvector ];
    ensureDatabases = [ "ironclaw" ];
    ensureUsers = [{
      name = "ironclaw";
      ensureDBOwnership = true;
    }];
    # Listen on localhost only (container uses host networking)
    settings = {
      listen_addresses = lib.mkForce "*";
    };
    authentication = ''
      # Allow ironclaw system user via Unix socket (peer auth)
      local ironclaw ironclaw peer map=ironclaw
      # Allow localhost and slirp4netns container connections (trust for peer-like access)
      host ironclaw ironclaw 127.0.0.1/32 trust
      host ironclaw ironclaw 10.0.2.0/24 trust
    '';
    identMap = ''
      # Map any ironclaw-* system user to the ironclaw PostgreSQL role
      ironclaw /^ironclaw-(.*)$ ironclaw
    '';
  };

  # Override to Type=exec: sdnotify=conmon doesn't work with rootless+linger.
  # Type=exec considers the service started once podman run -d exits successfully.
  systemd.services.podman-ironclaw-main.serviceConfig.Type = lib.mkForce "exec";

  # IronClaw AI assistant instance
  services.ironclawOci.instances.main = {
    enable = true;
    uid = 3020;
    gid = 3020;
    subUidStart = 130200;
    subGidStart = 130200;
    httpPort = 3100;
    # 10.0.2.2 is the host gateway in slirp4netns networking
    databaseUrl = "postgres://ironclaw@10.0.2.2/ironclaw";
    llmBackend = "anthropic";
    anthropicKeyFile = config.sops.secrets.ironclaw-anthropic-api-key.path;
    telegramTokenFile = config.sops.secrets.ironclaw-telegram-bot-token.path;
  };

  services.openclawOci.instances.work01 = {
    enable = true;
    uid = 3010;
    gid = 3010;
    subUidStart = 130100;
    subGidStart = 130100;
    gatewayPort = 18889;
    browserPort = 18891;
    telegramTokenFile = config.sops.secrets.openclaw-work01-telegram-bot-token.path;
    anthropicKeyFile = config.sops.secrets.openclaw-work01-anthropic-api-key.path;
    gatewayTokenFile = config.sops.secrets.openclaw-work01-gateway-token.path;
    allowFrom = [ "5654206852" ];
  };

  # This value determines the NixOS release
  system.stateVersion = "25.05";
}
