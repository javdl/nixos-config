{
  config,
  lib,
  ...
}:

# Personal (javdl/joost) GitHub Actions runners, added alongside a host's
# existing fuww org runners. Personal accounts have no org-level runner scope,
# so these are repo-scoped (url = github.com/javdl/joost). Registering them does
# not by itself contend with fuww CI — they only burn CPU when javdl/joost jobs
# actually run.
#
# Requires the host to already import modules/github-actions-runner.nix (for the
# CI toolchain via services.github-actions-runner.packages.forRunner) and to
# define the `github-runner` user (all github-runner-0X hosts do, via mkSystem
# user="github-runner"). Gated behind enable so a config push can't break a
# host's 04:00 auto-update before its `github-runner-javdl-token` SOPS key exists.

let
  cfg = config.services.javdlRunners;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    genList
    listToAttrs
    nameValuePair
    ;
in
{
  options.services.javdlRunners = {
    enable = mkEnableOption "personal javdl/joost GitHub Actions runners";

    count = mkOption {
      type = types.ints.positive;
      default = 2;
      description = "Number of javdl/joost runners to register on this host.";
    };

    namePrefix = mkOption {
      type = types.str;
      example = "github-runner-03-javdl";
      description = "Unique-per-host GitHub runner name prefix (a -N index is appended).";
    };

    tokenSopsFile = mkOption {
      type = types.path;
      example = "../secrets/github-runner-03.yaml";
      description = ''
        SOPS file holding the `github-runner-javdl-token` key (a javdl/joost repo
        registration token). Usually the host's own secrets file.
      '';
    };

    labels = mkOption {
      type = types.listOf types.str;
      default = [
        "nixos"
        "hetzner"
        "javdl"
      ];
      description = "extraLabels for the javdl runners.";
    };
  };

  config = mkIf cfg.enable {
    # Repo registration token. Fresh one (1h expiry) from
    # https://github.com/javdl/joost/settings/actions/runners/new — stored under
    # key `github-runner-javdl-token` in cfg.tokenSopsFile.
    sops.secrets.github-runner-javdl-token = {
      sopsFile = cfg.tokenSopsFile;
      key = "github-runner-javdl-token";
      mode = "0400";
      owner = "root";
    };

    # Per-runner work dirs off tmpfs (large checkouts), owned by the runner user.
    systemd.tmpfiles.rules = genList (
      i: "d /var/lib/github-runner-work/javdl-runner-${toString (i + 1)} 0700 github-runner users -"
    ) cfg.count;

    services.github-runners = listToAttrs (
      genList (
        i:
        let
          idx = i + 1;
        in
        nameValuePair "javdl-runner-${toString idx}" {
          enable = true;
          ephemeral = false;
          replace = true;
          tokenFile = config.sops.secrets.github-runner-javdl-token.path;
          url = "https://github.com/javdl/joost";
          user = "github-runner";
          name = "${cfg.namePrefix}-${toString idx}";
          workDir = "/var/lib/github-runner-work/javdl-runner-${toString idx}";
          extraPackages = config.services.github-actions-runner.packages.forRunner;
          extraLabels = cfg.labels;
          extraEnvironment = {
            DOCKER_HOST = "unix:///var/run/docker.sock";
            # nixpkgs github-runner ships only node24 externals; force JS actions
            # (checkout@v4, upload-artifact@v4, …) onto node24.
            FORCE_JAVASCRIPT_ACTIONS_TO_NODE24 = "true";
          };
        }
      ) cfg.count
    );
  };
}
