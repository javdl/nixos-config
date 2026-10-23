{ currentSystemName }:

{ config, lib, pkgs, ... }:

let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

  home = config.home.homeDirectory;
  beacon = pkgs.beacon;
  isReceiver = currentSystemName == "bali";

  receiverAddress = "100.113.194.113:6100";
  receiverListen = "0.0.0.0:6100";
  dashboardAddr = "127.0.0.1:8766";
  logDir = "${home}/.beacon/endpoint/logs";
  stateDir = "${home}/.local/state/beacon-fleet";
  fleetDir = "${home}/.local/share/beacon-fleet";
  fleetLog = "${fleetDir}/runtime.jsonl";
  historyDb = "${fleetDir}/history.db";

  # name = the `beacon endpoint <name> sync` subcommand; store = default store
  # path relative to $HOME (Beacon cli/beacon/internal/<name>session).
  # cursor reads ~/.cursor/projects and the IDE's state.vscdb, so gate on ~/.cursor.
  sweptRuntimes = [
    { name = "claude"; store = ".claude/projects"; }
    { name = "codex"; store = ".codex/sessions"; }
    { name = "cursor"; store = ".cursor"; }
    { name = "opencode"; store = ".local/share/opencode"; }
    { name = "grok"; store = ".grok/sessions"; }
    { name = "hermes"; store = ".hermes/state.db"; }
    { name = "pi"; store = ".pi/agent/sessions"; }
  ];

  harnesses = lib.optional (pkgs.omp != null) "omp";

  toml = pkgs.formats.toml { };

  shipperConfig = toml.generate "beacon-shipper.toml" {
    data_dir = "${stateDir}/shipper";
    sources.beacon_log = {
      type = "file";
      include = [
        "${logDir}/runtime.jsonl"
        "${logDir}/runtime.jsonl.[0-9]*"
      ];
      read_from = "beginning";
      max_line_bytes = 16777216;
    };
    sinks.bali = {
      type = "vector";
      inputs = [ "beacon_log" ];
      address = receiverAddress;
      healthcheck.enabled = false;
      acknowledgements.enabled = true;
      buffer = {
        type = "disk";
        max_size = 1073741824;
        when_full = "block";
      };
    };
  };

  receiverConfig = toml.generate "beacon-receiver.toml" {
    data_dir = "${stateDir}/receiver";
    sources.fleet = {
      type = "vector";
      address = receiverListen;
    };
    sinks.fleet_log = {
      type = "file";
      inputs = [ "fleet" ];
      path = fleetLog;
      encoding.codec = "text";
    };
  };

  runVector = name: dirs: configFile:
    pkgs.writeShellScript "beacon-${name}" ''
      mkdir -p ${lib.escapeShellArgs dirs}
      exec ${beacon}/bin/beacon-vector --config ${configFile}
    '';

  shipper = runVector "shipper" [ "${stateDir}/shipper" ] shipperConfig;
  receiver = runVector "receiver" [ "${stateDir}/receiver" fleetDir ] receiverConfig;

  sync = pkgs.writeShellScript "beacon-sync" ''
    failed=0
    ${lib.concatMapStrings (rt: ''
      if [ -e "$HOME/${rt.store}" ]; then
        if ! ${beacon}/bin/beacon endpoint ${rt.name} sync; then
          echo "beacon-sync: ${rt.name} sync failed" >&2
          failed=1
        fi
      else
        echo "beacon-sync: skipping ${rt.name}, no ~/${rt.store}"
      fi
    '') sweptRuntimes}
    exit $failed
  '';

  dashboardEnv = [ "BEACON_HISTORY_DB=${historyDb}" ];
in
{
  home.packages = [ beacon ];

  home.activation.beaconEndpoint = lib.mkIf (harnesses != [ ]) (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      BEACON_ONBOARDING=0 $DRY_RUN_CMD ${beacon}/bin/beacon endpoint install --user \
        --service none --no-start --no-backfill \
        --harness ${lib.concatStringsSep "," harnesses} || \
        echo "beacon: endpoint install failed, skipping" >&2
    ''
  );

  systemd.user.services = lib.mkIf isLinux (
    {
      beacon-shipper = {
        Unit = {
          Description = "Ship Beacon runtime log to ${receiverAddress}";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };
        Service = {
          ExecStart = "${shipper}";
          Restart = "on-failure";
          RestartSec = 10;
        };
        Install.WantedBy = [ "default.target" ];
      };

      beacon-sync = {
        Unit = {
          Description = "Sweep agent session stores into the Beacon runtime log";
          After = [ "beacon-shipper.service" ];
          Wants = [ "beacon-shipper.service" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${sync}";
        };
      };
    }
    // lib.optionalAttrs isReceiver {
      beacon-receiver = {
        Unit = {
          Description = "Receive Beacon fleet events into ${fleetLog}";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };
        Service = {
          ExecStart = "${receiver}";
          Restart = "on-failure";
          RestartSec = 10;
        };
        Install.WantedBy = [ "default.target" ];
      };

      beacon-dashboard = {
        Unit = {
          Description = "Beacon dashboard over the fleet log on ${dashboardAddr}";
          After = [ "beacon-receiver.service" ];
          Wants = [ "beacon-receiver.service" ];
        };
        Service = {
          Environment = dashboardEnv;
          ExecStartPre = [
            "${pkgs.coreutils}/bin/mkdir -p ${fleetDir}"
            "${pkgs.coreutils}/bin/touch ${fleetLog}"
            "${beacon}/bin/beacon endpoint traces reindex --log-path ${fleetLog} --retention-days 36500 --max-size-mb 51200"
          ];
          ExecStart = "${beacon}/bin/beacon endpoint dashboard --log-path ${fleetLog} --addr ${dashboardAddr}";
          Restart = "on-failure";
          RestartSec = 10;
        };
        Install.WantedBy = [ "default.target" ];
      };
    }
  );

  systemd.user.timers.beacon-sync = lib.mkIf isLinux {
    Unit.Description = "Run beacon-sync every 5 minutes";
    Timer = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      AccuracySec = "30s";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  launchd.agents = lib.mkIf isDarwin {
    beacon-shipper = {
      enable = true;
      config = {
        ProgramArguments = [ "${shipper}" ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        ProcessType = "Background";
        StandardOutPath = "${home}/Library/Logs/beacon-shipper.log";
        StandardErrorPath = "${home}/Library/Logs/beacon-shipper.log";
      };
    };
    beacon-sync = {
      enable = true;
      config = {
        ProgramArguments = [ "${sync}" ];
        RunAtLoad = true;
        StartInterval = 300;
        ProcessType = "Background";
        StandardOutPath = "${home}/Library/Logs/beacon-sync.log";
        StandardErrorPath = "${home}/Library/Logs/beacon-sync.log";
      };
    };
  };
}
