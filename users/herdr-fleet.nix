{
  currentSystemName,
  controller ? false,
  # The exe.dev command pane: a second controller in the personal tailnet
  # (tag:cmdpane) that reaches every node over OpenSSH instead of through
  # Bali's SSH aliases. Implies controller.
  cmdpane ? false,
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
  fleetKeys = import ./herdr-fleet-keys.nix;
  isController = controller || cmdpane;
  isFu137 = currentSystemName == "fu137";
  # radon is the macOS fleet worker; its server runs as a launchd agent.
  isRadon = currentSystemName == "radon";
  isFleetMachine = isController || isFu137 || isRadon || provisionAgentRuntime;

  # Single fleet inventory consumed by both hosts.toml and herdctl, with one
  # SSH destination per controller (null = not mirrored from there).
  #  - fromBali: Bali has Tailscale DNS disabled, so tailnet targets use their
  #    stable IPs and reach the runners through Tailscale SSH. The exe.dev
  #    worker uses Bali's dotless team-account SSH alias so the personal
  #    `*.exe.xyz` identity cannot win OpenSSH's first-value resolution.
  #    radon and the Sparks sit in the personal tailnet, whose Tailscale SSH
  #    cannot admit bali; their aliases in Bali's chezmoi SSH config select
  #    OpenSSH on port 2222.
  #  - fromCmdpane: the command pane is in the personal tailnet, so every
  #    work-tailnet node is cross-tailnet and Tailscale SSH cannot admit it
  #    either: OpenSSH on 2222 (22 on fu137, which runs no Tailscale SSH).
  #    The exe.dev team worker would need the team account's key; skipped.
  # See docs/herdr-command-center.md.
  fleetNodes = [
    {
      name = "runner03";
      role = "regular";
      fromBali = "ssh://joost@100.126.150.43";
      fromCmdpane = "ssh://joost@100.126.150.43:2222";
      prefix = "r03";
      remoteBin = "/etc/profiles/per-user/joost/bin/herdr";
      alwaysControl = true;
    }
    {
      name = "runner04";
      role = "regular";
      fromBali = "ssh://joost@100.97.77.46";
      fromCmdpane = "ssh://joost@100.97.77.46:2222";
      prefix = "r04";
      remoteBin = "/etc/profiles/per-user/joost/bin/herdr";
      alwaysControl = true;
    }
    {
      name = "runner05";
      role = "regular";
      fromBali = "ssh://joost@100.108.96.124";
      fromCmdpane = "ssh://joost@100.108.96.124:2222";
      prefix = "r05";
      remoteBin = "/etc/profiles/per-user/joost/bin/herdr";
      alwaysControl = true;
    }
    {
      name = "fu137";
      role = "gpu";
      fromBali = "ssh://joost@fu137";
      fromCmdpane = "ssh://joost@100.92.74.63";
      prefix = "fu137";
      remoteBin = "/home/joost/.nix-profile/bin/herdr";
      alwaysControl = false;
    }
    {
      name = "exedev";
      role = "dev";
      fromBali = "ssh://exedev@fu-herdr-dev";
      fromCmdpane = null;
      prefix = "exe";
      remoteBin = "/home/exedev/.local/bin/herdr";
      alwaysControl = true;
    }
    {
      name = "radon";
      role = "mac";
      fromBali = "ssh://joost@radon";
      fromCmdpane = "ssh://joost@100.92.105.21:2222";
      prefix = "rad";
      remoteBin = "/etc/profiles/per-user/joost/bin/herdr";
      alwaysControl = true;
    }
    {
      name = "spark";
      role = "gpu";
      fromBali = "ssh://joost@spark";
      fromCmdpane = "ssh://joost@100.114.192.43:2222";
      prefix = "sp1";
      remoteBin = "/home/joost/.local/bin/herdr";
      alwaysControl = true;
    }
    {
      name = "spark2";
      role = "gpu";
      fromBali = "ssh://joost@spark2";
      fromCmdpane = "ssh://joost@100.109.106.44:2222";
      prefix = "sp2";
      remoteBin = "/home/joost/.local/bin/herdr";
      alwaysControl = true;
    }
  ];

  controllerNodes = map (node: node // { uri = if cmdpane then node.fromCmdpane else node.fromBali; }) (
    builtins.filter (node: !cmdpane || node.fromCmdpane != null) fleetNodes
  );

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

  activeHerdrConfig = if isController then herdrControllerConfig else herdrFleetConfig;

  herdrMirrorHosts = pkgs.writeText "herdr-mirror-hosts.toml" ''
    autostart = true
    poll_seconds = 60
    default_host = "runner03"
    close_remote_on_local_close = false
    always_control = true

    ${lib.concatMapStringsSep "\n" (node: ''
      [hosts.${node.name}]
      target = "${node.uri}"
      prefix = "${node.prefix}"
      session = "${sessionName}"
      remote_bin = "${node.remoteBin}"
      ${lib.optionalString (!node.alwaysControl) "always_control = false"}
    '') controllerNodes}
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
          lib.concatMapStringsSep "|" (node: node.name) controllerNodes
        }> <herdr arguments...>" >&2
        exit 2
      }

      [ "$#" -ge 1 ] || usage
      node="$1"
      shift

      if [ "$node" = "hosts" ]; then
        printf '%-10s %-15s %s\n' NODE ROLE TARGET
        ${lib.concatMapStringsSep "\n" (
          node: "printf '%-10s %-15s %s\\n' ${node.name} ${node.role} ${node.uri}"
        ) controllerNodes}
        exit 0
      fi

      [ "$#" -ge 1 ] || usage
      case "$node" in
        ${lib.concatMapStringsSep "\n" (node: ''
          ${node.name}) target="${node.uri}"; remote_bin="${node.remoteBin}" ;;
        '') controllerNodes}
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
  # profiles and the command pane need these base packages added here.
  home.packages =
    lib.optionals provisionAgentRuntime [
      pkgs.bubblewrap
      pkgs.codex
      pkgs.herdr
      pkgs.socat
    ]
    ++ lib.optionals cmdpane [ pkgs.herdr ]
    ++ lib.optionals isController [
      herdctl
      herdrMirror
    ];

  # Every fleet machine uses the same named Herdr namespace. The service also
  # sets this explicitly; the session variable makes interactive CLI commands
  # such as `herdr status` target it by default.
  home.sessionVariables.HERDR_SESSION = sessionName;

  xdg.configFile."herdr/fleet.toml".source = herdrFleetConfig;

  xdg.configFile."herdr/config.toml" = lib.mkIf isController {
    source = herdrControllerConfig;
  };

  xdg.configFile."herdr-mirror/hosts.toml" = lib.mkIf isController {
    source = herdrMirrorHosts;
  };

  # Upstream's installer creates this compatibility link and `status` checks
  # it even though plugin actions run relative to the plugin root.
  home.file.".local/bin/herdr-mirror" = lib.mkIf isController {
    source = "${herdrMirror}/bin/herdr-mirror";
  };

  # The command pane is a dedicated VM: nothing else owns its SSH config.
  # Every fleet destination is a tailnet IP; trust each host key on first use
  # (the mirror cannot answer a prompt) and offer only the pane's own key.
  home.file.".ssh/config" = lib.mkIf cmdpane {
    text = ''
      Host 100.*
        IdentitiesOnly yes
        IdentityFile ~/.ssh/herdr-cmdpane
        StrictHostKeyChecking accept-new
        ServerAliveInterval 30
        ServerAliveCountMax 3
    '';
  };

  # Bali is a tagged device while fu137 deliberately remains user-owned, so
  # Tailscale SSH cannot authorize this direction; the command pane is in
  # another tailnet altogether. Append the controller keys to the user-owned
  # file instead of declaring home.file: a Home Manager symlink would replace
  # every other key already trusted by this workstation.
  home.activation.herdrFleetAuthorizedKey = lib.mkIf isFu137 (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      auth_dir="$HOME/.ssh"
      auth_file="$auth_dir/authorized_keys"

      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -d -m 0700 "$auth_dir"
      if [ -L "$auth_file" ]; then
        echo "Refusing to modify symlinked $auth_file; migrate it to a regular file first." >&2
        exit 1
      fi
      if [ ! -e "$auth_file" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 /dev/null "$auth_file"
      fi
      for fleet_key in ${lib.escapeShellArgs (builtins.attrValues fleetKeys)}; do
        if ! ${pkgs.gnugrep}/bin/grep -qxF "$fleet_key" "$auth_file" 2>/dev/null; then
          if [ -n "$DRY_RUN_CMD" ]; then
            echo "Would append a Herdr controller key to $auth_file"
          else
            printf '%s\n' "$fleet_key" >> "$auth_file"
          fi
        fi
      done
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod 0600 "$auth_file"
    ''
  );

  systemd.user.services.herdr-agents = lib.mkIf pkgs.stdenv.isLinux {
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

  # macOS worker (radon): a login-session LaunchAgent, so agents keep access
  # to the login keychain (Claude Code stores its credentials there).
  launchd.agents.herdr-agents = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.herdr}/bin/herdr"
        "--session"
        sessionName
        "server"
      ];
      EnvironmentVariables = {
        HERDR_CONFIG_PATH = "${activeHerdrConfig}";
        HERDR_SESSION = sessionName;
        PATH = "${config.home.homeDirectory}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 5;
    };
  };

  # Ensure every fleet machine publishes Claude and Codex lifecycle state to
  # Herdr. Authentication remains an explicit, machine-local interactive step.
  home.activation.herdrAgentIntegrations = lib.mkIf isFleetMachine (
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
  home.activation.herdrMirrorPlugin = lib.mkIf isController (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${pkgs.herdr}/bin/herdr plugin link \
        ${herdrMirror}/share/herdr-mirror --enabled
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/env HERDR_SESSION=${sessionName} \
        ${pkgs.herdr}/bin/herdr server reload-config || true
    ''
  );
}
