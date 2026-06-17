{
  config,
  pkgs,
  lib,
  ...
}:

# Hetzner dedicated GitHub Actions runner for fuww org (github-runner-03)
# EX63 dedicated server (Intel i9-9900K, 64GB RAM, 2x 512GB NVMe).
#
# Provisioning (from a machine with the j8 SSH key, since rescue mode only
# accepts the j8 mac studio key registered at order time):
#   1. Confirm server is reachable: ssh root@<ip>
#   2. Run: make hetzner/provision NIXADDR=<ip> NIXNAME=github-runner-03
#   3. SOPS re-key (host age key changes from loom's placeholder to real):
#        ssh-keyscan <ip> | grep ed25519 | ssh-to-age
#        # Replace the github-runner-03 anchor in .sops.yaml with the new key
#        sops updatekeys secrets/github-runner-03.yaml
#        # Rebuild so the runner can decrypt the token
#        make hetzner/copy NIXADDR=<ip> && make hetzner/switch NIXADDR=<ip> NIXNAME=github-runner-03
#   4. Set up Tailscale: make hetzner/tailscale-auth NIXADDR=<ip> TAILSCALE_AUTHKEY=tskey-auth-xxx
#   5. Rotate the github-runner-token in SOPS with a fresh org registration token:
#        sops secrets/github-runner-03.yaml
#        # paste new token from https://github.com/organizations/fuww/settings/actions/runners/new

{
  imports = [
    ../modules/hetzner-dedicated-hardware.nix
    ../modules/disko-hetzner-dedicated.nix
    ../modules/github-actions-runner.nix
    ../modules/cachix.nix
    ../modules/secrets.nix
    ../modules/automatic-nix-gc.nix
    ../modules/nixos-auto-update.nix
    ../modules/security-audit.nix
    ../modules/ghostty-terminfo.nix
    ../modules/mosh.nix
    ../modules/netdata.nix
    ../modules/ci-disk-cleanup.nix
  ];

  # Enable the GitHub Actions runner packages module
  services.github-actions-runner.enable = true;

  # Latest kernel for best hardware support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use systemd-boot for UEFI — limit boot entries to prevent /boot filling up.
  # If EX63 turns out to be BIOS-only at first boot, swap to grub here.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 3;
  boot.loader.efi.canTouchEfiVariables = true;

  # Hostname
  networking.hostName = "github-runner-03";

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

  # CI disk cleanup: Docker prune, journal vacuum, tmp cleanup
  services.ciDiskCleanup.enable = true;

  # Disk-based garbage collection (shorter retention for CI - builds are ephemeral)
  services.automaticNixGC = {
    enable = true;
    minFreeGB = 50;
    maxFreeGB = 100;
    scheduledThresholdGB = 100;
    keepDays = 5;
  };

  # Automatic NixOS updates from git repository
  services.nixosAutoUpdate = {
    enable = true;
    flake = "github:javdl/nixos-config#github-runner-03";
    dates = "04:00";
    randomizedDelaySec = "30m";
    allowReboot = false;
  };

  # Security auditing — disabled, auditd filled disks on dev servers
  services.securityAudit.enable = false;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = _: true;

  # Networking - DHCP
  networking.useDHCP = true;

  # Firewall - base config (Tailscale settings added below)
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

  # Admin user (joost) for SSH management
  users.users.joost = {
    isNormalUser = true;
    home = "/home/joost";
    extraGroups = [
      "docker"
      "wheel"
    ];
    shell = pkgs.zsh;
    hashedPassword = "$6$nJOFfAkJl1RJMxUW$DuXpYNq7rc/TE7Awuyjv7vyOyzbUnHmxN3YN1Gz1DiAw363a9GkpEU6bU9MvYa94nXaP7oTSFbZegNb8kAcUm1";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINAQwjDkpe7I8Y6xdD5SbICFy0v5ArILxyTBXhtSOOmw joostvanderlaan@gmail.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFB87It3cS6o8kgD/6r3R59KP2o1eOJz1bgLJl4syLX1 joost"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEx6MK8mQ22KWCA0uDV6uBNvMw/NeBl70Mu4hxrX9SJ9 j8 mac studio"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKiS5X4s5jEKzgpaRMX7gIxKCGcRGSF9qUAlUkOUdFbW j@jlnw.nl"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIy0FO1ta1djvSamjM1Ph/YZpMhMtXSeuFE1Zl9GHhkQ joost+agent@fashionunited.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEfx6qICt/nunP+X3Wv8Y6hhZtGo0AZreAp3QOThy0SD loom-agent-nopass"
    ];
  };

  # Docker already enabled by github-actions-runner module;
  # ensure ip_forward for Docker networking
  boot.kernel.sysctl."net.ipv4.ip_forward" = true;

  # System packages for server management
  environment.systemPackages = with pkgs; [
    git
    gnumake
    htop
    btop
    tmux
    curl
    wget
    rsync
    neovim
    jq
    ripgrep
    fd
    tree
    unzip
    zip
    molly-guard
  ];

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";

  # Use zsh as default shell
  programs.zsh.enable = true;

  # Run dynamically linked binaries (AppImages, prebuilt tools) without patchelf
  programs.nix-ld.enable = true;

  # Load BBR TCP congestion control module
  boot.kernelModules = [ "tcp_bbr" ];

  # System limits and performance tuning
  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 2097152;
    "fs.inotify.max_user_instances" = 2048;
    "fs.file-max" = 2097152;
    "kernel.pid_max" = 4194303;
    "net.core.somaxconn" = 65535;
    "net.ipv4.tcp_max_syn_backlog" = 65535;
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
    {
      domain = "*";
      type = "soft";
      item = "nofile";
      value = "65536";
    }
    {
      domain = "*";
      type = "hard";
      item = "nofile";
      value = "65536";
    }
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

  # SOPS secrets for GitHub runner token
  # Token must be an org-level runner registration token (NOT a PAT).
  # Get from: https://github.com/organizations/fuww/settings/actions/runners/new
  # Format: AAU5P4... (29 chars). Expires in 1 hour, single-use per registration.
  sops.defaultSopsFile = ../secrets/github-runner-03.yaml;
  sops.secrets.github-runner-token = {
    mode = "0400";
    owner = "root";
  };

  # Pre-job cleanup hook (shared with runner-02 pattern).
  # Monitors BOTH root disk and /run tmpfs.
  environment.etc."github-runner-pre-job.sh" = {
    mode = "0755";
    text = ''
      #!/bin/bash
      AVAIL_GB=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
      TMPFS_PCT=$(df --output=pcent /run | tail -1 | tr -d ' %')
      echo "Pre-job disk check: ''${AVAIL_GB}GB free on /, /run tmpfs at ''${TMPFS_PCT}%"

      # Always purge cache dirs that Docker containers (e.g., Lighthouse CI)
      # write as non-runner UIDs. Workflows re-create them but cannot `chmod`
      # the leftovers since only the original owner can chmod. Parent dirs are
      # runner-owned, so `rm` only needs write-on-parent (no sudo).
      find /var/lib/github-runner-work -type d -name ".lighthouseci" -exec rm -rf {} + 2>/dev/null || true

      # Visual-regression writes diff PNGs from a root container into the
      # workspace. Those land in root-owned subdirs the non-root runner user
      # cannot delete, so they break the next job's checkout (EACCES on
      # unlink). Clear them with a throwaway root container.
      if command -v docker >/dev/null 2>&1; then
        docker run --rm -v /var/lib/github-runner-work:/w busybox \
          find /w -type d -name '__diff_output__' -prune -exec rm -rf {} + 2>/dev/null || true
      fi

      if [ "$TMPFS_PCT" -ge 80 ]; then
        echo "Tmpfs /run pressure — clearing _actions/_temp caches"
        find /run/github-runner -type d -name "_actions" -exec rm -rf {} + 2>/dev/null || true
        find /run/github-runner -type d -name "_temp" -exec rm -rf {} + 2>/dev/null || true
        find /run/github-runner -type d -name "_tool" -exec rm -rf {} + 2>/dev/null || true
        NEW_PCT=$(df --output=pcent /run | tail -1 | tr -d ' %')
        echo "Tmpfs /run after cleanup: ''${NEW_PCT}%"
      fi

      if [ "$AVAIL_GB" -lt 40 ]; then
        echo "Low disk — running emergency cleanup before job"
        docker system prune --all --force --filter "until=4h" 2>/dev/null || true
        docker builder prune --all --force 2>/dev/null || true
        docker volume prune --force 2>/dev/null || true
        for dir in /var/lib/github-runner-work/fuww-runner-*/*/; do
          [ -d "$dir" ] || continue
          case "$(basename "$dir")" in
            _actions|_PipelineMapping|_diag|_temp|_tool) continue ;;
          esac
          if [ "$(find "$dir" -maxdepth 0 -mtime +1 2>/dev/null)" ]; then
            echo "Removing stale: $dir"
            rm -rf "$dir"
            # The runner records each repo's workspace path in _PipelineMapping
            # and reuses it on later jobs WITHOUT re-checking that it exists.
            # Deleting a workspace while keeping its mapping makes the next job
            # cwd into a now-deleted directory and fail at the first step with
            # "No such file or directory". Drop the mapping too so the runner
            # treats the next job as a fresh checkout and recreates the workspace.
            rm -rf "$(dirname "$dir")/_PipelineMapping"
          fi
        done
        NEW_AVAIL=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
        echo "After cleanup: ''${NEW_AVAIL}GB available"
      fi
    '';
  };

  # Long-lived runners sharing 1 registration token at first start.
  # i9-9900K = 8 cores / 16 threads, so 16 runner slots maps 1:1 with HT lanes.
  # See github-runner-02.nix for full design rationale (ephemeral=false, workDir off tmpfs).
  systemd.tmpfiles.rules =
    let
      runnerCount = 16;
    in
    lib.genList (
      i: "d /var/lib/github-runner-work/fuww-runner-${toString (i + 1)} 0700 github-runner users -"
    ) runnerCount;

  services.github-runners =
    let
      runnerCount = 16;
    in
    lib.listToAttrs (
      lib.genList (
        i:
        let
          idx = i + 1;
        in
        lib.nameValuePair "fuww-runner-${toString idx}" {
          enable = true;
          ephemeral = false;
          replace = true;
          name = "github-runner-03-${toString idx}";
          tokenFile = config.sops.secrets.github-runner-token.path;
          url = "https://github.com/fuww";
          workDir = "/var/lib/github-runner-work/fuww-runner-${toString idx}";
          extraLabels = [
            "hetzner"
            "nixos"
            "ex63"
            "self-hosted-${toString runnerCount}-cores"
          ];
          user = "github-runner";
          extraPackages = config.services.github-actions-runner.packages.forRunner;
          extraEnvironment = {
            DOCKER_HOST = "unix:///var/run/docker.sock";
            ACTIONS_RUNNER_HOOK_JOB_STARTED = "/etc/github-runner-pre-job.sh";
            # nixpkgs 26.05 ships github-runner with ONLY the node24 externals
            # (Node 20 is EOL and was dropped upstream). Node 20 JS actions
            # (actions/checkout@v4, actions/upload-artifact@v4, ...) would try to
            # exec the missing lib/externals/node20/bin/node and fail with
            # "No such file or directory". Force them onto the bundled node24,
            # which GitHub makes the default on 2026-06-16 anyway.
            FORCE_JAVASCRIPT_ACTIONS_TO_NODE24 = "true";
          };
        }
      ) runnerCount
    );

  # This value determines the NixOS release
  system.stateVersion = "25.05";
}
