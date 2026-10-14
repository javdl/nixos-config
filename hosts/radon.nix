{
  config,
  lib,
  pkgs,
  ...
}:
{
  # nix-darwin stateVersion. Host runs macOS Tahoe.
  system.stateVersion = 6;

  # This makes it work with the Determinate Nix installer
  ids.gids.nixbld = 30000;

  # Set the primary user for homebrew and other user-specific settings
  system.primaryUser = "joost";

  # Don't let nix-darwin manage nix configuration since we use Determinate
  nix.settings = { };

  # Prevent nix-darwin from managing nix.conf
  environment.etc."nix/nix.conf".enable = false;

  imports = [
    ./mac-shared.nix
    ../modules/darwin-auto-update.nix
    ../modules/darwin-tailscaled.nix
  ];

  # Compact worker: native Blender, two browsers, and CLI-only containers.
  # Keep remote access, credentials and the existing PAIR cluster integration.
  # No uninstall/zap here: application data is retained until reviewed.
  homebrew.casks = lib.mkForce [
    "bitwarden"
    "blender"
    "brave-origin"
    "google-chrome"
    "nvidia-pair"
  ];
  homebrew.brews = lib.mkForce [
    "podman"
    "tailscale"
  ];
  homebrew.onActivation.cleanup = lib.mkForce "none";
  homebrew.onActivation.upgrade = lib.mkForce false;

  # Check agent releases weekly, not at every login or every six hours.
  # The manual updater and activation-time bootstrap remain available.
  home-manager.users.joost.launchd.agents.agent-cli-update.config = {
    RunAtLoad = lib.mkForce false;
    StartInterval = lib.mkForce 604800;
  };

  # Weekly maintenance rather than daily system activation. This does not
  # change Apple's own macOS/security-update settings.
  services.darwinAutoUpdate = {
    enable = true;
    flake = "github:javdl/nixos-config#radon";
    weekday = 0; # Sunday, launchd convention
  };

  # Hardened headless Tailscale (replaces the inline launchd daemon). Persistent
  # state, userspace networking (required on macOS without macsys), joost as
  # operator (no sudo for `tailscale ...`). Place an auth key at the path below
  # (mode 0600 root) to enable unattended re-auth after reboots/rebuilds.
  services.darwinTailscaled = {
    enable = true;
    operator = "joost";
    authKeyFile = "/etc/tailscale/authkey";
    # NVIDIA PAIR (docs/nvpair-omarchy.md) must dial j9/fu137 over the
    # tailnet and see peers' real addresses; userspace networking allows
    # neither.
    tun = "utun";
    # bali is shared in from the FashionUnited tailnet; resolve it by its
    # full name (bali.stargazer-duck.ts.net) through MagicDNS.
    magicDNSDomains = [ "stargazer-duck.ts.net" ];
  };

  # Cua Bots controller (docs/cua-bots-fleet.md): `cua auth login` and
  # `cua devices enroll` for the app, which reaches the fleet's Spaces
  # through the cua.ai relay. The app itself is built by
  # scripts/build-cua-bots.sh.
  environment.systemPackages = [ pkgs.cua ];
  # Usage telemetry off for the CLI and for the Cua Bots app started from a
  # shell (scripts/build-cua-bots.sh --run inherits it).
  environment.variables.CUA_TELEMETRY = "0";

  # Headless tailscaled does not install a domain resolver when the tailnet
  # supplies default DNS servers. Delegate only this tailnet to MagicDNS.
  environment.etc."resolver/buri-hoki.ts.net".text = ''
    # Managed by nix-darwin for Radon's Tailscale domain.
    nameserver 100.100.100.100
  '';

  # OpenSSH for bali on port 2222. bali reaches radon from the work tailnet
  # (declarative sharing, tag://work/herdr grant in javdl/joost
  # infra/tailscale), but Tailscale SSH on port 22 cannot admit it: the
  # policy's ssh section rejects cross-tailnet sources. Key-only, joost only,
  # bound to radon's tailnet address so it is not reachable on the LAN
  # (launchd restarts it until tailscaled has brought that address up).
  environment.etc."ssh/radon-2222-authorized_keys".text = ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEfx6qICt/nunP+X3Wv8Y6hhZtGo0AZreAp3QOThy0SD bali-agent-nopass
  '';
  launchd.daemons.sshd-bali = {
    script = ''
      /usr/bin/ssh-keygen -A
      exec /usr/sbin/sshd -D -e \
        -o ListenAddress=100.92.105.21:2222 \
        -o AuthorizedKeysFile=/etc/ssh/radon-2222-authorized_keys \
        -o AuthorizedKeysCommand=none \
        -o PasswordAuthentication=no \
        -o KbdInteractiveAuthentication=no \
        -o PermitRootLogin=no \
        -o AllowUsers=joost \
        -o PidFile=/var/run/sshd-bali.pid
    '';
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      StandardOutPath = "/var/log/sshd-bali.log";
      StandardErrorPath = "/var/log/sshd-bali.log";
    };
  };
}
