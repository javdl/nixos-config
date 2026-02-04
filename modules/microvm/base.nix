# MicroVM base configuration function
#
# Creates a reusable VM configuration with common settings for Claude Code development.
# Based on https://michael.stapelberg.ch/posts/2026-02-01-coding-agent-microvm-nix/
#
# This is a function that takes parameters and returns a NixOS module.
# The module receives pkgs, lib, and inputs through the standard module arguments.
#
# Usage in loom-microvms.nix:
#   microvm.vms.myvm = {
#     autostart = false;
#     config = (import ../modules/microvm/base.nix {
#       hostName = "myvm";
#       ipAddress = "192.168.83.2/24";
#       tapId = "01";
#       mac = "02:00:00:00:00:01";
#       workspace = "/home/joost/microvm/myvm";
#     });
#   };

{ hostName
, ipAddress
, tapId
, mac
, workspace
, vcpu ? 8
, mem ? 4096
, extraPackages ? []
, gatewayAddress ? "192.168.83.1"
, bridgeName ? "microbr"
, hostUser ? "joost"
}:

# Return a NixOS module that receives pkgs, lib, inputs via _module.args
{ pkgs, lib, inputs, ... }:

let
  # Import unstable nixpkgs for latest Claude Code
  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in
{
  imports = [
    inputs.microvm.nixosModules.microvm
  ];

  # VM hardware configuration
  microvm = {
    hypervisor = "cloud-hypervisor";
    vcpu = vcpu;
    mem = mem;

    # Network interface - TAP device connected to bridge
    interfaces = [{
      type = "tap";
      id = "vm-${tapId}";
      inherit mac;
    }];

    # Shared directories via virtiofs
    shares = [
      # Read-only Nix store from host (huge efficiency gain)
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        proto = "virtiofs";
      }
      # Workspace directory for the agent
      {
        tag = "workspace";
        source = workspace;
        mountPoint = "/workspace";
        proto = "virtiofs";
      }
      # SSH host keys (generated on host, persisted across VM restarts)
      {
        tag = "ssh-host-keys";
        source = "${workspace}/ssh-host-keys";
        mountPoint = "/etc/ssh/host-keys";
        proto = "virtiofs";
      }
      # Claude credentials from host
      {
        tag = "claude-credentials";
        source = "/home/${hostUser}/claude-microvm";
        mountPoint = "/home/agent/.claude-host";
        proto = "virtiofs";
      }
    ];

    # Writable overlay for /var (8GB)
    volumes = [{
      image = "var.img";
      mountPoint = "/var";
      size = 8192;
    }];
  };

  # Networking inside the VM
  systemd.network.enable = true;
  systemd.network.networks."20-lan" = {
    matchConfig.Type = "ether";
    networkConfig = {
      Address = ipAddress;
      Gateway = gatewayAddress;
      DNS = [ "1.1.1.1" "8.8.8.8" ];
    };
  };

  networking.hostName = hostName;

  # Note: microvm.nix automatically handles the Nix store overlay when
  # you specify shares with mountPoint = "/nix/.ro-store". No need to
  # manually configure fileSystems."/nix/store".

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
    # Use host keys from shared directory for persistence
    hostKeys = [
      { path = "/etc/ssh/host-keys/ssh_host_ed25519_key"; type = "ed25519"; }
    ];
  };

  # Agent user for Claude Code
  users.users.agent = {
    isNormalUser = true;
    home = "/home/agent";
    extraGroups = [ "wheel" ];
    # SSH keys are set up at runtime via setup-agent-ssh service
  };

  # Setup SSH authorized_keys at runtime from host-mounted file
  systemd.services.setup-agent-ssh = {
    description = "Setup SSH authorized_keys for agent user";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    before = [ "sshd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /home/agent/.ssh
      if [ -f /etc/ssh/host-keys/authorized_keys ]; then
        cp /etc/ssh/host-keys/authorized_keys /home/agent/.ssh/authorized_keys
        chmod 600 /home/agent/.ssh/authorized_keys
      fi
      chown -R agent:users /home/agent/.ssh
    '';
  };

  # Allow agent to sudo without password
  security.sudo.wheelNeedsPassword = false;

  # Link Claude credentials into agent home
  systemd.services.setup-claude-credentials = {
    description = "Setup Claude Code credentials for agent user";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /home/agent/.claude
      if [ -f /home/agent/.claude-host/.claude.json ]; then
        ln -sf /home/agent/.claude-host/.claude.json /home/agent/.claude/.claude.json
      fi
      if [ -f /home/agent/.claude-host/settings.json ]; then
        ln -sf /home/agent/.claude-host/settings.json /home/agent/.claude/settings.json
      fi
      chown -R agent:users /home/agent/.claude
    '';
  };

  # System packages
  environment.systemPackages = with pkgs; [
    # Development essentials
    git
    gnumake
    gcc

    # Editors
    neovim

    # Utilities
    htop
    ripgrep
    fd
    jq
    tree
    curl
    wget

    # Claude Code from unstable
    pkgs-unstable.claude-code
  ] ++ extraPackages;

  # Nix configuration
  nix = {
    package = pkgs.nixVersions.latest;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  # Timezone
  time.timeZone = "UTC";

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";

  # Note: nixpkgs.config.allowUnfree is inherited from the host's configuration
  # when the VM is built via microvm.nix module system.

  system.stateVersion = "25.05";
}
