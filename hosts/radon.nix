{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Family Hermes agent (javdl/joost docs/plans/active/hermes-family-mac-mini.md).
  # Everything the `hermes` user writes lives on the encrypted `Agent` APFS
  # volume on the external disk, never on the internal SSD.
  agentVolumeUUID = "B1E4C91E-5FF3-4FF7-B66E-18F5E6D877DD";
  agentRoot = "/Volumes/Agent";
  hermesHome = "${agentRoot}/hermes";
in
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

  # Stay current: rebuild from the GitHub flake daily (launchd equivalent of
  # the colleague Linux servers' services.nixosAutoUpdate at 04:00).
  services.darwinAutoUpdate = {
    enable = true;
    flake = "github:javdl/nixos-config#radon";
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

  # Headless server: never sleep, come back after a power cut or a freeze.
  power.sleep.computer = "never";
  power.restartAfterPowerFailure = true;
  power.restartAfterFreeze = true;

  # Service account for the family Hermes gateway. Standard (non-admin), no
  # login shell; its home is on the Agent volume. nix-darwin cannot create a
  # user over SSH without Full Disk Access, so the record was made once by
  # hand with dscl (UniqueID 506, PrimaryGroupID 20, the home below,
  # UserShell /usr/bin/false, IsHidden 1, Password "*"). nix-darwin then only
  # keeps its properties in line.
  users.knownUsers = [ "hermes" ];
  users.users.hermes = {
    uid = 506;
    gid = 20; # staff
    home = hermesHome;
    shell = "/usr/bin/false";
    description = "Hermes family agent";
  };

  # Mount external volumes at boot, before anyone logs in, so the daemons
  # below find them on a headless restart.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    /usr/bin/defaults write /Library/Preferences/SystemConfiguration/autodiskmount \
      AutomountDisksWithoutUserLogin -bool true
  '';

  # Unlock the encrypted Agent volume at boot with the root-only key
  # (/etc/hermes/agent-volume.key, mode 0400, on the FileVault-encrypted
  # internal disk), keep ownership enforced (external volumes default to
  # "ignore ownership", which shows every file as _unknown), and create the
  # directories the hermes user writes to.
  launchd.daemons.agent-volume-unlock = {
    script = ''
      if ! /sbin/mount | /usr/bin/grep -q ' on ${agentRoot} '; then
        /usr/sbin/diskutil apfs unlockVolume ${agentVolumeUUID} -stdinpassphrase \
          < /etc/hermes/agent-volume.key
      fi
      /usr/sbin/diskutil enableOwnership ${agentRoot}
      /usr/bin/install -d -o hermes -g staff -m 0700 \
        ${hermesHome} ${agentRoot}/logs ${agentRoot}/tmp
    '';
    serviceConfig = {
      RunAtLoad = true;
      StandardOutPath = "/var/log/agent-volume-unlock.log";
      StandardErrorPath = "/var/log/agent-volume-unlock.log";
    };
  };

  # OpenSSH on port 2222: bali's path (it reaches radon from the work
  # tailnet via declarative sharing, tag://work/herdr grant in javdl/joost
  # infra/tailscale, and Tailscale SSH on 22 rejects cross-tailnet sources)
  # and Joost's key-only fallback when Tailscale SSH is unavailable (ssh
  # alias radon-fb in chezmoi). Key-only, joost only, bound to radon's
  # tailnet address so it is not reachable on the LAN (launchd restarts it
  # until tailscaled has brought that address up).
  environment.etc."ssh/radon-2222-authorized_keys".text = ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEfx6qICt/nunP+X3Wv8Y6hhZtGo0AZreAp3QOThy0SD bali-agent-nopass
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEx6MK8mQ22KWCA0uDV6uBNvMw/NeBl70Mu4hxrX9SJ9 ssh-key-joost
  '';
  # /etc/ssh/radon-2222-authorized_keys is a symlink into /nix/store, whose
  # group-writable parent fails sshd's StrictModes ("bad ownership or modes
  # for directory /nix/store"), so every login was refused. Copy it to a
  # root-owned 0644 file at start.
  launchd.daemons.sshd-bali = {
    script = ''
      /usr/bin/ssh-keygen -A
      /usr/bin/install -o root -g wheel -m 0644 \
        /etc/ssh/radon-2222-authorized_keys /var/db/sshd-bali-authorized_keys
      exec /usr/sbin/sshd -D -e \
        -o ListenAddress=100.92.105.21:2222 \
        -o AuthorizedKeysFile=/var/db/sshd-bali-authorized_keys \
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
