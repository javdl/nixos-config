{
  currentSystemName,
  controller ? false,
  provisionAgentRuntime ? false,
}:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  sessionName = "agents";
  baliFleetPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEfx6qICt/nunP+X3Wv8Y6hhZtGo0AZreAp3QOThy0SD bali-herdr-command-center";
  isFu137 = currentSystemName == "fu137";
  isFleetMachine = controller || isFu137 || provisionAgentRuntime;

  # Single fleet inventory consumed by both hosts.toml and herdctl. Bali has
  # Tailscale DNS disabled, so tailnet targets use their stable IPs. The
  # exe.dev worker uses Bali's dotless team-account SSH alias so the personal
  # `*.exe.xyz` identity cannot win OpenSSH's first-value resolution.
  fleetNodes = [
    {
      name = "runner03";
      role = "regular";
      user = "joost";
      target = "100.126.150.43";
      prefix = "r03";
      remoteBin = "/etc/profiles/per-user/joost/bin/herdr";
      alwaysControl = true;
    }
    {
      name = "runner04";
      role = "regular";
      user = "joost";
      target = "100.97.77.46";
      prefix = "r04";
      remoteBin = "/etc/profiles/per-user/joost/bin/herdr";
      alwaysControl = true;
    }
    {
      name = "runner05";
      role = "regular";
      user = "joost";
      target = "100.108.96.124";
      prefix = "r05";
      remoteBin = "/etc/profiles/per-user/joost/bin/herdr";
      alwaysControl = true;
    }
    {
      name = "gpu";
      role = "gpu";
      user = "joost";
      target = "fu137";
      prefix = "gpu";
      remoteBin = "/home/joost/.nix-profile/bin/herdr";
      alwaysControl = false;
    }
    {
      name = "exedev";
      role = "dev";
      user = "exedev";
      target = "fu-herdr-dev";
      prefix = "exe";
      remoteBin = "/home/exedev/.local/bin/herdr";
      alwaysControl = true;
    }
  ];

  herdrFleetConfig = pkgs.writeText "herdr-fleet-config.toml" ''
    onboarding = false

    [session]
    resume_agents_on_restore = true

    [remote]
    manage_ssh_config = true
  '';

  herdrControllerConfig = pkgs.writeText "herdr-controller-config.toml" ''
    onboarding = false

    [session]
    resume_agents_on_restore = true

    [remote]
    manage_ssh_config = true

    [ui]
    window_title = "{hostname}: {workspace}"

    [ui.toast]
    delivery = "terminal"

    [[keys.command]]
    key = "prefix+shift+m"
    type = "plugin_action"
    command = "mirror.start"

    [[keys.command]]
    key = "prefix+shift+s"
    type = "plugin_action"
    command = "mirror.pause"

    [[keys.command]]
    key = "prefix+shift+b"
    type = "plugin_action"
    command = "mirror.restore"

    [[keys.command]]
    key = "prefix+shift+n"
    type = "plugin_action"
    command = "mirror.new-workspace-pick"
  '';

  activeHerdrConfig = if controller then herdrControllerConfig else herdrFleetConfig;

  herdrMirrorHosts = pkgs.writeText "herdr-mirror-hosts.toml" ''
    autostart = true
    poll_seconds = 60
    default_host = "runner03"
    close_remote_on_local_close = false
    always_control = true

    ${lib.concatMapStringsSep "\n" (node: ''
      [hosts.${node.name}]
      target = "ssh://${node.user}@${node.target}"
      prefix = "${node.prefix}"
      session = "${sessionName}"
      remote_bin = "${node.remoteBin}"
      ${lib.optionalString (!node.alwaysControl) "always_control = false"}
    '') fleetNodes}
  '';

  herdrMirrorBinary = pkgs.fetchurl {
    url = "https://github.com/nikok6/herdr-mirror/releases/download/v0.4.1/herdr-mirror-linux-x86_64";
    hash = "sha256-a7gE+us75/ibNZdl9tqtJP9sdMGd7TOdkYarS4ktjqg=";
  };

  herdrMirror = pkgs.stdenvNoCC.mkDerivation {
    pname = "herdr-mirror";
    version = "0.4.1";
    dontUnpack = true;

    installPhase = ''
      install -Dm755 ${herdrMirrorBinary} \
        "$out/share/herdr-mirror/target/release/herdr-mirror"
      install -Dm644 ${./herdr-mirror-plugin.toml} \
        "$out/share/herdr-mirror/herdr-plugin.toml"
      mkdir -p "$out/bin"
      ln -s "$out/share/herdr-mirror/target/release/herdr-mirror" \
        "$out/bin/herdr-mirror"
    '';

    meta = with lib; {
      description = "Mirror multiple remote Herdr servers into one local sidebar";
      homepage = "https://github.com/nikok6/herdr-mirror";
      license = licenses.mit;
      mainProgram = "herdr-mirror";
      platforms = [ "x86_64-linux" ];
    };
  };

  herdctl = pkgs.writeShellApplication {
    name = "herdctl";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      session=${lib.escapeShellArg sessionName}

      usage() {
        echo "usage: herdctl hosts | herdctl <${
          lib.concatMapStringsSep "|" (node: node.name) fleetNodes
        }> <herdr arguments...>" >&2
        exit 2
      }

      [ "$#" -ge 1 ] || usage
      node="$1"
      shift

      if [ "$node" = "hosts" ]; then
        printf '%-10s %-15s %s\n' NODE ROLE TARGET
        ${lib.concatMapStringsSep "\n" (
          node: "printf '%-10s %-15s %s\\n' ${node.name} ${node.role} ${node.target}"
        ) fleetNodes}
        exit 0
      fi

      [ "$#" -ge 1 ] || usage
      case "$node" in
        ${lib.concatMapStringsSep "\n" (node: ''
          ${node.name}) target="${node.user}@${node.target}"; remote_bin="${node.remoteBin}" ;;
        '') fleetNodes}
        *) usage ;;
      esac

      remote=(env "HERDR_SESSION=$session" "$remote_bin" "$@")
      printf -v command '%q ' "''${remote[@]}"
      exec ssh -o BatchMode=yes "$target" "$command"
    '';
  };
in
lib.mkIf isFleetMachine {
  home.username = lib.mkDefault "joost";
  home.homeDirectory = lib.mkDefault "/home/joost";
  home.stateVersion = lib.mkDefault "25.11";

  xdg.enable = true;

  # Bali and fu137 already receive Herdr/Codex from their existing profiles;
  # fu137's socat is owned by Omarchy/pacman. Only the new runner operator
  # profiles need these base packages added here.
  home.packages =
    lib.optionals provisionAgentRuntime [
      pkgs.bubblewrap
      pkgs.codex
      pkgs.herdr
      pkgs.socat
    ]
    ++ lib.optionals controller [
      herdctl
      herdrMirror
    ];

  # Every fleet machine uses the same named Herdr namespace. The service also
  # sets this explicitly; the session variable makes interactive CLI commands
  # such as `herdr status` target it by default.
  home.sessionVariables.HERDR_SESSION = sessionName;

  xdg.configFile."herdr/fleet.toml".source = herdrFleetConfig;

  xdg.configFile."herdr/config.toml" = lib.mkIf controller {
    source = herdrControllerConfig;
  };

  xdg.configFile."herdr-mirror/hosts.toml" = lib.mkIf controller {
    source = herdrMirrorHosts;
  };

  # Upstream's installer creates this compatibility link and `status` checks
  # it even though plugin actions run relative to the plugin root.
  home.file.".local/bin/herdr-mirror" = lib.mkIf controller {
    source = "${herdrMirror}/bin/herdr-mirror";
  };

  # Bali is a tagged device while fu137 deliberately remains user-owned, so
  # Tailscale SSH cannot authorize this direction. Append Bali's fleet key to
  # the user-owned file instead of declaring home.file: a Home Manager symlink
  # would replace every other key already trusted by this workstation.
  home.activation.herdrFleetAuthorizedKey = lib.mkIf isFu137 (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      auth_dir="$HOME/.ssh"
      auth_file="$auth_dir/authorized_keys"
      fleet_key=${lib.escapeShellArg baliFleetPublicKey}

      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -d -m 0700 "$auth_dir"
      if [ -L "$auth_file" ]; then
        echo "Refusing to modify symlinked $auth_file; migrate it to a regular file first." >&2
        exit 1
      fi
      if [ ! -e "$auth_file" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 /dev/null "$auth_file"
      fi
      if ! ${pkgs.gnugrep}/bin/grep -qxF "$fleet_key" "$auth_file" 2>/dev/null; then
        if [ -n "$DRY_RUN_CMD" ]; then
          echo "Would append Bali's Herdr fleet key to $auth_file"
        else
          printf '%s\n' "$fleet_key" >> "$auth_file"
        fi
      fi
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod 0600 "$auth_file"
    ''
  );

  systemd.user.services.herdr-agents = {
    Unit = {
      Description = "Persistent Herdr agents session";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      Environment = [
        "HERDR_CONFIG_PATH=${activeHerdrConfig}"
        "HERDR_SESSION=${sessionName}"
      ];
      ExecStart = "${pkgs.herdr}/bin/herdr --session ${sessionName} server";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Match the established native Claude Code installation used by the full
  # server profiles. Authentication remains an explicit interactive step.
  home.activation.herdrAgentIntegrations = lib.mkIf provisionAgentRuntime (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -x "$HOME/.local/bin/claude" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/env \
          PATH=${lib.makeBinPath [ pkgs.curl ]}:"$PATH" \
          ${pkgs.bash}/bin/bash -c \
          "${pkgs.curl}/bin/curl -fsSL https://claude.ai/install.sh | ${pkgs.bash}/bin/bash"
      fi

      $DRY_RUN_CMD mkdir -p "$HOME/.claude" "$HOME/.codex"
      $DRY_RUN_CMD ${pkgs.herdr}/bin/herdr integration install claude
      $DRY_RUN_CMD ${pkgs.herdr}/bin/herdr integration install codex
    ''
  );

  # Linking is local and network-free: the Nix package already contains the
  # verified release binary and a manifest without upstream's download step.
  home.activation.herdrMirrorPlugin = lib.mkIf controller (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${pkgs.herdr}/bin/herdr plugin link \
        ${herdrMirror}/share/herdr-mirror --enabled
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/env HERDR_SESSION=${sessionName} \
        ${pkgs.herdr}/bin/herdr server reload-config || true
    ''
  );
}
