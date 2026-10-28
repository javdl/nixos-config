{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # Family Hermes agent (javdl/joost docs/plans/active/hermes-family-mac-mini.md).
  # Everything the `hermes` user writes lives on the encrypted `Agent` APFS
  # volume on the agent disk, never on the internal SSD.
  #
  # The agent disk is a Samsung T7 Shield (2 TB), named by its USB serial
  # number. To set up a new disk: put its serial here and switch, run
  # `agent-volume-format --erase`, pin the UUID it prints below and switch
  # again. agent-volume-unlock then encrypts the volume with the root-only key.
  agentDiskSerial = "S6YLNS0W800550A";
  agentVolumeUUID = "CEFC4785-1252-443A-B861-F871994AB0FC";
  agentRoot = "/Volumes/Agent";
  hermesHome = "${agentRoot}/hermes";
  # Exits 0 only when the Agent volume itself is mounted at agentRoot. A path
  # check is not enough: an empty /Volumes/Agent on the internal disk, or the
  # volume mounted at "/Volumes/Agent 1" because such a directory exists,
  # would both pass it.
  agentVolumeMounted = pkgs.writeShellScript "agent-volume-mounted" ''
    mountPoint=$(/usr/sbin/diskutil info ${agentVolumeUUID} 2>/dev/null |
      /usr/bin/awk -F': +' '/^ *Mounted:/ {m=$2} /^ *Mount Point:/ {p=$2} END {if (m == "Yes") print p}')
    [ "$mountPoint" = ${agentRoot} ]
  '';
  agentVolumeFormat = pkgs.writeShellApplication {
    name = "agent-volume-format";
    runtimeInputs = [ pkgs.python3 ];
    text = ''exec python3 ${./radon/agent-volume-format.py} ${agentDiskSerial} "$@"'';
  };
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
    # Secrets for the family Hermes gateway (secrets/radon.yaml). Only radon
    # imports it, so the other Macs keep their activation unchanged.
    inputs.sops-nix.darwinModules.sops
    ./radon/agent-launcher.nix
    (import ./radon/hermes-family.nix { inherit agentRoot agentVolumeMounted hermesHome; })
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
  # macmon is the sudo-less Apple Silicon monitor (CPU/GPU temperatures).
  # Same place as cua: a radon-only CLI from nixpkgs, not the shared
  # homebrew.brews list. The hand-installed Homebrew formula is left alone
  # because homebrew.onActivation.cleanup stays at its default, "none".
  environment.systemPackages = [
    pkgs.cua
    pkgs.macmon
    agentVolumeFormat
  ];
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

  # Every launchd job that touches the Agent volume runs through the Full
  # Disk Access launcher (radon/agent-launcher.nix); TCC refuses the others,
  # root included.
  agentLauncher.users = [ "hermes" ];

  # Unlock the encrypted Agent volume at boot with the root-only key
  # (/etc/hermes/agent-volume.key, mode 0400, on the FileVault-encrypted
  # internal disk; made here if missing), encrypt a volume that
  # agent-volume-format has just made, keep ownership enforced (external
  # volumes default to "ignore ownership", which shows every file as
  # _unknown), and create the directories the hermes user writes to.
  agentLauncher.daemons.agent-volume-unlock = {
    job = pkgs.writeShellScript "agent-volume-unlock" ''
      key=/etc/hermes/agent-volume.key
      if [ ! -e "$key" ]; then
        /usr/bin/install -d -m 0700 /etc/hermes
        (umask 0277 && /usr/bin/openssl rand -base64 32 > "$key")
      fi
      if ! ${agentVolumeMounted}; then
        /usr/sbin/diskutil apfs unlockVolume ${agentVolumeUUID} -stdinpassphrase \
          < "$key" || /usr/sbin/diskutil mount ${agentVolumeUUID}
      fi
      if ! ${agentVolumeMounted}; then
        echo "agent-volume-unlock: the Agent volume is not mounted at ${agentRoot}" >&2
        exit 1
      fi
      if /usr/sbin/diskutil info ${agentVolumeUUID} | /usr/bin/grep -q '^ *FileVault: *No$'; then
        /usr/sbin/diskutil apfs encryptVolume ${agentVolumeUUID} -user disk \
          -stdinpassphrase < "$key" || exit 1
      fi
      /usr/sbin/diskutil enableOwnership ${agentRoot}
      /usr/bin/install -d -o hermes -g staff -m 0700 \
        ${hermesHome} ${agentRoot}/logs ${agentRoot}/tmp
    '';
    # A non-zero exit (the disk is not there yet, or unlocking failed) makes
    # launchd run the job again after 30 s.
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      ThrottleInterval = 30;
      StandardOutPath = "/var/log/agent-volume-unlock.log";
      StandardErrorPath = "/var/log/agent-volume-unlock.log";
    };
  };

  # Shows whether the hermes user can write to the Agent volume from launchd,
  # which needs the launcher's Full Disk Access. Runs at load, so also at boot
  # next to agent-volume-unlock: it first waits up to 120 s for that job to
  # mount the volume and make its logs directory. Run it again with
  # `sudo launchctl kickstart system/org.nixos.agent-volume-probe`.
  agentLauncher.daemons.agent-volume-probe = {
    job = pkgs.writeShellScript "agent-volume-probe" ''
      waited=0
      until ${agentVolumeMounted} && [ -d ${agentRoot}/logs ]; do
        [ "$waited" -ge 120 ] && break
        /bin/sleep 1
        waited=$((waited + 1))
      done
      now=$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)
      if ! ${agentVolumeMounted}; then
        echo "$now FAILED: the Agent volume is not mounted at ${agentRoot}"
        exit 1
      fi
      if echo "$now" > ${agentRoot}/logs/agent-volume-probe 2>/dev/null; then
        echo "$now ok: $(/usr/bin/id -un) wrote ${agentRoot}/logs/agent-volume-probe"
      else
        echo "$now FAILED: $(/usr/bin/id -un) cannot write ${agentRoot}/logs/agent-volume-probe"
        exit 1
      fi
    '';
    serviceConfig = {
      UserName = "hermes";
      GroupName = "staff";
      RunAtLoad = true;
      StandardOutPath = "/var/log/agent-volume-probe.log";
      StandardErrorPath = "/var/log/agent-volume-probe.log";
    };
  };

  # The hermes user may reach only Aperture (and MagicDNS) on the tailnet.
  # The tailnet policy cannot say this: it applies per node, and PAIR on radon
  # needs the tailnet too. Apple's /etc/pf.conf already evaluates every
  # anchor under com.apple/*, so loading this one is enough. The script names
  # the anchor's store path, so a changed anchor changes the plist and
  # nix-darwin reloads the daemon.
  environment.etc."pf.anchors/hermes".text = ''
    pass out quick proto tcp from any to 100.75.128.40 port 443 user hermes
    pass out quick proto { tcp udp } from any to 100.100.100.100 port 53 user hermes
    block drop out quick inet from any to 100.64.0.0/10 user hermes
    block drop out quick inet6 from any to fd7a:115c:a1e0::/48 user hermes
  '';
  launchd.daemons.hermes-pf = {
    script = ''
      /sbin/pfctl -E
      /sbin/pfctl -a com.apple/hermes -f ${config.environment.etc."pf.anchors/hermes".source}
    '';
    serviceConfig = {
      RunAtLoad = true;
      StandardOutPath = "/var/log/hermes-pf.log";
      StandardErrorPath = "/var/log/hermes-pf.log";
    };
  };

  # OpenSSH on port 2222: bali's path (it reaches radon from the work
  # tailnet via declarative sharing, tag://work/herdr grant in javdl/joost
  # infra/tailscale, and Tailscale SSH on 22 rejects cross-tailnet sources)
  # and Joost's key-only fallback when Tailscale SSH is unavailable (ssh
  # alias radon-fb in chezmoi), plus the exe.dev Herdr command pane
  # (users/herdr-fleet-keys.nix). Key-only, joost only, bound to radon's
  # tailnet address so it is not reachable on the LAN (launchd restarts it
  # until tailscaled has brought that address up).
  environment.etc."ssh/radon-2222-authorized_keys".text = ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEfx6qICt/nunP+X3Wv8Y6hhZtGo0AZreAp3QOThy0SD bali-agent-nopass
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEx6MK8mQ22KWCA0uDV6uBNvMw/NeBl70Mu4hxrX9SJ9 ssh-key-joost
    ${(import ../users/herdr-fleet-keys.nix).cmdpane}
  '';
  # /etc/ssh/radon-2222-authorized_keys is a symlink into /nix/store, whose
  # group-writable parent fails sshd's StrictModes ("bad ownership or modes
  # for directory /nix/store"), so every login was refused. Copy it to a
  # root-owned 0644 file at start. Copy from the store path, not /etc: the
  # path changes with the keys, so the plist changes and nix-darwin restarts
  # the daemon. Copying from /etc left a new key unread until a manual restart.
  launchd.daemons.sshd-bali = {
    script = ''
      /usr/bin/ssh-keygen -A
      /usr/bin/install -o root -g wheel -m 0644 \
        ${config.environment.etc."ssh/radon-2222-authorized_keys".source} \
        /var/db/sshd-bali-authorized_keys
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

  # Hermes WebUI (~/hermes-webui checkout) from login, restarted on exit.
  # FileVault unlock at boot logs joost in, so this starts with the machine.
  # start.sh --foreground execs into server.py, so launchd tracks the real
  # server PID instead of the daemonising ctl.sh path (docs/supervisor.md).
  # The Label is ctl.sh's default HERMES_WEBUI_LAUNCHD_LABEL: `./ctl.sh start`
  # then refuses to spawn a second instance on 8787. Restart with
  # `launchctl kickstart -k gui/$(id -u)/com.parantoux.hermes-webui`.
  launchd.user.agents.hermes-webui = {
    serviceConfig = {
      Label = "com.parantoux.hermes-webui";
      ProgramArguments = [
        "/bin/bash"
        "/Users/joost/hermes-webui/start.sh"
        "--foreground"
      ];
      WorkingDirectory = "/Users/joost/hermes-webui";
      EnvironmentVariables = {
        HOME = "/Users/joost";
        # git/hermes from the Nix profile; python3 resolves to /usr/bin/python3,
        # and bootstrap.py hands off to the agent venv interpreter.
        PATH = "/etc/profiles/per-user/joost/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        HERMES_WEBUI_STATE_DIR = "/Users/joost/.hermes/webui";
      };
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      # Same file ctl.sh writes, so `./ctl.sh logs` keeps working.
      StandardOutPath = "/Users/joost/.hermes/webui.log";
      StandardErrorPath = "/Users/joost/.hermes/webui.log";
    };
  };
}
