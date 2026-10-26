# Production dsv41 on the DGX Sparks: Mia-AiLab DeepSeek V4.1 Flash 1017
# EAQ 2.9bpw, TensorFold, two ranks.
#
# spark runs dsv41-mia.service. start.sh on the head launches rank 1 on
# spark2 over ssh (CX7 192.168.100.11). spark2 has no model unit, which is
# what removes the old head/worker boot race.
#
# The launcher is the checkout at ~/mia29/recipe, pinned to Mia's recipe
# commit 370daf0cc38f348516a98ebab38f6053858eab1f (image
# tensorfold-dsv41:exl3-tp2-625d420e24a4). scripts/local.sh in that
# checkout holds the NAS paths. Serving settings below are systemd
# environment, which the recipe prefers over local.sh.
#
# Tailscale Serve stays dsv41-cluster-serve in users/dsv41-cluster.nix.
# The sybil EXL3 units in that file stay installed only when
# services.dsv41Cluster.enable is true.
#
# See docs/dgx-spark.md.
{ hostName }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.dsv41Mia;
  home = config.home.homeDirectory;
  recipe = "${home}/mia29/recipe";
  stateDir = "${home}/.local/state/dsv41-tensorfold";
  keyFile = "${stateDir}/api-key";
  apiEnv = "${home}/.config/spark-vllm/api.env";
  shim = "${home}/mia29/shimw";
  # MiaAI-Lab/DeepSeek-v4.1-Flash-1017-2x-DGX-Sparks @ 370daf0c.
  # "Add optional systemd user service template for both ranks (#32)".
  recipeRev = "370daf0cc38f348516a98ebab38f6053858eab1f";
  image = "tensorfold-dsv41:exl3-tp2-625d420e24a4";
  worker = "joost@192.168.100.11";
  models = "/mnt/models/mia29";
  port = 8000;
  bind = "127.0.0.1";
  servedName = "dsv41";

  scriptDir = pkgs.runCommand "dsv41-mia-scripts" { } ''
    mkdir -p "$out"
    for s in lib.sh api-key.sh mia-prepare.sh mia-health.sh; do
      install -m 755 "${./dsv41}/$s" "$out/$s"
    done
  '';

  prepare = "${scriptDir}/mia-prepare.sh";
in
{
  options.services.dsv41Mia = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        On spark, install and start dsv41-mia.service (Mia TensorFold as
        the production dsv41). spark2 gets no unit: the head starts rank 1
        over ssh. Set false together with services.dsv41Cluster.enable =
        true to restore the sybil EXL3 units.
      '';
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = hostName == "spark" || hostName == "spark2";
          message = "dsv41 Mia only applies to spark and spark2 (got ${hostName})";
        }
        {
          assertion = !(cfg.enable && config.services.dsv41Cluster.enable);
          message = ''
            Mia and the sybil dsv41 cluster cannot both be enabled.
            Leave services.dsv41Cluster.enable false for Mia, or set
            services.dsv41Mia.enable = false and
            services.dsv41Cluster.enable = true to roll back.
          '';
        }
      ];
    }
    (lib.mkIf (cfg.enable && hostName == "spark") {
      systemd.user.services = {
        dsv41-mia = {
          Unit = {
            Description = "Mia TensorFold DeepSeek V4.1 Flash 1017 EAQ 2.9bpw as dsv41";
            After = [
              "network-online.target"
              "dsv41-cluster-serve.service"
            ];
            Conflicts = [
              "spark-vllm.service"
              "nvpair.service"
            ];
            # Three starts in 30 minutes, including the first. A GPU fault
            # stops there instead of looping. The health timer does not
            # restart this unit.
            StartLimitIntervalSec = "30min";
            StartLimitBurst = 3;
          };
          Service = {
            Type = "simple";
            WorkingDirectory = recipe;
            Environment = [
              "FOREGROUND=1"
              "PREPARE=0"
              "SERVED_NAME=${servedName}"
              "PORT=${toString port}"
              "HOST=${bind}"
              "TENSORFOLD_NO_UPDATE_CHECK=1"
              "CONTEXT=262144"
              "PARALLEL=4"
              "DRAFTS=1"
              "API_KEY=1"
              "THINKING=1"
              "WORKER=${worker}"
              "IMAGE=${image}"
              "STATE_DIR=${stateDir}"
              "API_KEY_FILE=${keyFile}"
              "PATH=${shim}:${home}/glm-dl/venv/bin:/usr/local/bin:/usr/bin:/bin"
              "DSV41_API_KEY_FILE=${apiEnv}"
              "MIA_RECIPE=${recipe}"
              "MIA_REV=${recipeRev}"
              "MIA_IMAGE=${image}"
              "MIA_WORKER=${worker}"
              "MIA_MODELS=${models}"
              "MIA_SHIM=${shim}"
              "MIA_PORT=${toString port}"
              "MIA_FAB_IF=enp1s0f0np0"
              "MIA_HOST_IP=192.168.100.10"
              "MIA_FABRIC_WAIT_SEC=120"
              "MIA_WORKER_WAIT_SEC=180"
              "MIA_MODELS_WAIT_SEC=120"
            ];
            ExecStartPre = [
              "${prepare} wait-fabric"
              "${prepare} wait-worker"
              "${prepare} wait-models"
              "${prepare} preflight"
              "${scriptDir}/api-key.sh write-raw ${keyFile}"
            ];
            ExecStart = "/usr/bin/bash ./start.sh";
            # SIGTERM runs the recipe's own stop trap (both ranks). This
            # second stop.sh is the one that still runs if that trap does
            # not. stop.sh is a no-op when the containers are already gone.
            ExecStopPost = "/usr/bin/bash ${recipe}/stop.sh";
            Restart = "on-failure";
            RestartSec = "60";
            TimeoutStartSec = "15min";
            TimeoutStopSec = "120";
          };
          Install.WantedBy = [ "default.target" ];
        };

        # Not wanted by a target. The timer starts it. After= is on this
        # oneshot, not on the timer: the timer is WantedBy=timers.target,
        # and a service ordered after basic.target closes a cycle back
        # through timers.target. That cycle deleted the timers.target job
        # on the sybil health timer.
        dsv41-mia-health = {
          Unit = {
            Description = "Log if Mia /health is down. Does not restart dsv41-mia";
            After = [ "dsv41-mia.service" ];
          };
          Service = {
            Type = "oneshot";
            Environment = [
              "MIA_UNIT=dsv41-mia.service"
              "MIA_HEALTH_URL=http://${bind}:${toString port}/health"
              "MIA_HEALTH_GRACE_SEC=900"
            ];
            ExecStart = "${scriptDir}/mia-health.sh";
          };
        };
      };

      systemd.user.timers.dsv41-mia-health = {
        Unit.Description = "Log Mia /health once a minute after the startup grace";
        Timer = {
          OnBootSec = "2min";
          OnUnitActiveSec = "60s";
          AccuracySec = "10s";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    })
  ];
}
