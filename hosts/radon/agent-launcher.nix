# Full Disk Access launcher for launchd daemons that use radon's external Agent
# volume (javdl/joost docs/architecture/decisions/0004-agent-state-on-external-disk-on-the-mac-mini.md).
#
# macOS privacy protection (TCC) blocks launchd jobs from the external volume,
# root jobs included. TCC holds the binary that launchd started responsible for
# the job's file access, so each daemon declared here runs its job through
# agent-launcher (see agent-launcher/agent-launcher.c), and Joost grants that
# one file Full Disk Access once, in System Settings.
#
# The file is installed only when it is absent. Nix builds are ad-hoc signed,
# so a rebuilt launcher would have a new code hash and lose the grant. To
# replace it: `sudo rm /usr/local/libexec/agent-launcher`, switch, and grant
# Full Disk Access to the new file.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agentLauncher;

  launcherPackage = pkgs.runCommandCC "agent-launcher" { } ''
    mkdir -p $out/bin
    $CC -O2 -Wall -Wextra -o $out/bin/agent-launcher ${./agent-launcher/agent-launcher.c}
  '';
in
{
  options.agentLauncher = {
    path = lib.mkOption {
      type = lib.types.str;
      default = "/usr/local/libexec/agent-launcher";
      readOnly = true;
      description = "Where the launcher is installed.";
    };

    daemons = lib.mkOption {
      default = { };
      description = ''
        launchd daemons (label org.nixos.<name>) whose job runs through the
        launcher. The job becomes /etc/agent-launcher.d/<name>. The launcher
        passes only PATH, so a job sets HOME, TMPDIR and anything else it needs
        itself. A job may exec: the launcher stays the parent.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            job = lib.mkOption {
              type = lib.types.path;
              description = "Executable the launcher runs.";
            };
            serviceConfig = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
              description = "launchd settings besides ProgramArguments.";
            };
          };
        }
      );
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Users besides root that may execute the launcher (an ACL entry each).";
    };
  };

  config = {
    environment.etc = lib.mapAttrs' (
      name: daemon: lib.nameValuePair "agent-launcher.d/${name}" { source = daemon.job; }
    ) cfg.daemons;

    # The job's store path in the plist makes nix-darwin reload the daemon when
    # the job changes. The launcher does not pass it on.
    launchd.daemons = lib.mapAttrs (name: daemon: {
      serviceConfig = daemon.serviceConfig // {
        ProgramArguments = [
          cfg.path
          name
        ];
        EnvironmentVariables = (daemon.serviceConfig.EnvironmentVariables or { }) // {
          AGENT_LAUNCHER_JOB = "${daemon.job}";
        };
      };
    }) cfg.daemons;

    # Before the launchd step, so daemons find the launcher on the first
    # switch. Mode 0754 keeps it readable for the System Settings file picker
    # but executable only by root and cfg.users.
    system.activationScripts.preActivation.text = ''
      if [ ! -e ${cfg.path} ]; then
        echo "installing ${cfg.path}: grant it Full Disk Access in System Settings" >&2
        /usr/bin/install -d -m 0755 -o root -g wheel ${builtins.dirOf cfg.path}
        /usr/bin/install -m 0754 -o root -g wheel ${launcherPackage}/bin/agent-launcher ${cfg.path}
      fi
      /bin/chmod -N ${cfg.path}
      ${lib.concatMapStrings (user: ''
        /bin/chmod +a ${lib.escapeShellArg "user:${user} allow execute"} ${cfg.path}
      '') cfg.users}
    '';
  };
}
