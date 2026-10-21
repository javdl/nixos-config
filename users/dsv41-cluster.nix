# One dsv41 TP2 cluster for the two DGX Sparks.
#
# spark is the head (rank 0). spark2 is the worker (rank 1). Both homes
# import this file and select themselves from `cluster.nodes` by hostname.
# Edit the cluster attrset to change image, weights, the DSpark table,
# the HTTP listener, or the CX7 rendezvous for both machines at once.
#
# Default exposure is the Aperture profile: 127.0.0.1:8000, API key from
# ~/.config/spark-vllm/api.env, Tailscale Serve :8443 on spark. Set
# `expose = "open"` for the previous 0.0.0.0:8000 listener with no key.
# Ranks pair on the CX7 (masterAddr:masterPort). That path does not follow
# the HTTP bind address.
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
  nodes = {
    spark = {
      role = "head";
      gid = 3;
      ip = "192.168.100.10";
    };
    spark2 = {
      role = "worker";
      gid = 5;
      ip = "192.168.100.11";
    };
  };

  # Measured on the shipping weights, 2026-10-21 13:34 CEST (prose probe,
  # depths 0..5). The launcher default (28.90,...) is not this table.
  dsparkRoundMs = "31.10,34.89,38.17,41.62,44.60,47.08";

  cluster = {
    inherit nodes dsparkRoundMs;
    expose = "aperture";
    image = "ghcr.io/sybil-solutions/deepseek-v4.1-flash-exl3-spark@sha256:5817414f92e9bec0406dfc4575e16b282209f0cb1ead16fe53d51bac7ac9e9e4";
    modelDir = "/home/joost/models/dsv41-1017-exl3";
    servedModelName = "dsv41";
    port = 8000;
    apiKeyFileRel = ".config/spark-vllm/api.env";
    tailscaleHttpsPort = 8443;
    masterAddr = nodes.spark.ip;
    masterPort = 25000;
    fabIf = "enp1s0f0np0";
    fabHca = "rocep1s0f0";
    tensorParallelSize = 2;
    nnodes = 2;
    gpuMemoryUtilization = "0.88";
    maxModelLen = 262144;
    maxNumSeqs = 2;
    maxNumBatchedTokens = 2048;
    loadFormat = "auto";
    kvCacheMemoryBytes = 2684354560;
    engram = ''{"cpu_offload":true,"dp_shared_memory":false,"disk_offload":true,"disk_threads":256}'';
    compilation = ''{"cudagraph_mode":"FULL_DECODE_ONLY"}'';
    kernel = ''{"enable_flashinfer_autotune":false}'';
    speculative = ''{"method":"dspark","num_speculative_tokens":5}'';
    mmLimit = ''{"image":0}'';
    containerName = "dsv41-serve";
    cacheRel = ".cache/dsv41-serve";
    shmSize = "64g";
    memlock = "-1";
    stack = "67108864";
    healthEvery = "2min";
    healthFailures = 2;
    healthTimeoutSec = 90;
    followEvery = "30s";
    readyRetries = 40;
    readyRetryDelaySec = 15;
    fabricWaitSec = 120;
    masterWaitSec = 180;
    restartSec = 30;
    timeoutStartSec = "20min";
    timeoutStopSec = 90;
    stopTimeoutSec = 60;
    startLimitIntervalSec = 3600;
    startLimitBurst = 5;
  };

  cfg = config.services.dsv41Cluster;
  node = cluster.nodes.${hostName};
  isHead = node.role == "head";
  rank = if isHead then 0 else 1;
  unitName = "dsv41-cluster-${node.role}";
  aperture = cfg.expose == "aperture";
  bindAddress = if aperture then "127.0.0.1" else "0.0.0.0";
  followMode = if aperture then "tcp" else "http";
  apiKeyFile = "${config.home.homeDirectory}/${cluster.apiKeyFileRel}";

  markov = ./dsv41/markov_top_tokens.json;
  markovHash = builtins.hashFile "md5" markov;

  scriptDir = pkgs.runCommand "dsv41-cluster-scripts" { } ''
    mkdir -p "$out"
    for s in lib.sh gid.sh api-key.sh prepare.sh run.sh ready.sh health.sh follow.sh serve.sh; do
      install -m 755 "${./dsv41}/$s" "$out/$s"
    done
  '';

  shellEnv =
    name: attrs:
    pkgs.writeText name (
      lib.concatStringsSep "\n" (
        lib.mapAttrsToList (key: value: "${key}=${lib.escapeShellArg (toString value)}") attrs
      )
      + "\n"
    );

  recipeEnv = pkgs.writeText "dsv41-recipe.env" ''
    NCCL_IB_HCA=${cluster.fabHca}
    NCCL_IB_DISABLE=0
    NCCL_NET=IB
    NCCL_SOCKET_IFNAME=${cluster.fabIf}
    GLOO_SOCKET_IFNAME=${cluster.fabIf}
    TP_SOCKET_IFNAME=${cluster.fabIf}
    VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=1800
    VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
    VLLM_DISABLED_KERNELS=FlashInferCutlassMxfp8LinearKernel
    HF_HUB_OFFLINE=1
    VLLM_EXL3_MOE_PARALLEL_GROUPS=1
    EXL3_MOE_COOP_WIDE=1
    EXL3_INT8_GEMV=0
    VLLM_DSPARK_DEPTH_POLICY=conf
    VLLM_DSPARK_DRAFT_MS=0
    VLLM_DSPARK_LOCAL_ARGMAX=1
    VLLM_DSPARK_ROUND_MS=${cluster.dsparkRoundMs}
    VLLM_DSPARK_MARKOV_CACHE=/root/.cache/markov_top_tokens.json
    EXL3_L2PF=attn,moe,next
    EXL3_L2PF_HC=1
    EXL3_RDMA_AR=1
    EXL3_ROUTER=1
    EXL3_MROW_GROUPED=1
    EXL3_SMOE_FLAGS=-DSMOE_RUNFLAGS=1
    VLLM_DSV41_MHC_OVERLAP=1
    VLLM_ENGRAM_DISK_SPIN_MS=1000
    VLLM_SHORT_CTX_BOUNDS=512,1025
    VLLM_EXL3_MOE_TF_PROMPT=1
    TORCH_EXTENSIONS_DIR=/root/.cache/torch_extensions
  '';

  nodeEnv = shellEnv "dsv41-node.env" {
    DSV41_IMAGE = cluster.image;
    DSV41_MODEL_DIR = cluster.modelDir;
    DSV41_SERVED = cluster.servedModelName;
    DSV41_PORT = cluster.port;
    DSV41_BIND = bindAddress;
    DSV41_EXPOSE = cfg.expose;
    DSV41_MASTER_ADDR = cluster.masterAddr;
    DSV41_MASTER_PORT = cluster.masterPort;
    DSV41_FAB_IF = cluster.fabIf;
    DSV41_FAB_HCA = cluster.fabHca;
    DSV41_TP = cluster.tensorParallelSize;
    DSV41_NNODES = cluster.nnodes;
    DSV41_UTIL = cluster.gpuMemoryUtilization;
    DSV41_MAX_LEN = cluster.maxModelLen;
    DSV41_MAX_SEQS = cluster.maxNumSeqs;
    DSV41_MAX_BATCH = cluster.maxNumBatchedTokens;
    DSV41_LOAD_FORMAT = cluster.loadFormat;
    DSV41_KV_BYTES = cluster.kvCacheMemoryBytes;
    DSV41_ENGRAM = cluster.engram;
    DSV41_GRAPH = cluster.compilation;
    DSV41_KERNEL = cluster.kernel;
    DSV41_SPEC = cluster.speculative;
    DSV41_MM = cluster.mmLimit;
    DSV41_SHM = cluster.shmSize;
    DSV41_MEMLOCK = cluster.memlock;
    DSV41_STACK = cluster.stack;
    DSV41_CONTAINER = cluster.containerName;
    DSV41_CACHE_REL = cluster.cacheRel;
    DSV41_FOLLOW_MODE = followMode;
    DSV41_API_KEY_FILE = apiKeyFile;
    DSV41_RANK = rank;
    DSV41_ROLE = node.role;
    DSV41_HOST_IP = node.ip;
    DSV41_GID = node.gid;
    DSV41_RECIPE_ENV = recipeEnv;
    DSV41_SERVE_SCRIPT = "${scriptDir}/serve.sh";
    DSV41_MARKOV = markov;
    DSV41_HEALTH_FAILURES = cluster.healthFailures;
    DSV41_HEALTH_TIMEOUT_SEC = cluster.healthTimeoutSec;
    DSV41_READY_RETRIES = cluster.readyRetries;
    DSV41_READY_RETRY_DELAY = cluster.readyRetryDelaySec;
    DSV41_FABRIC_WAIT_SEC = cluster.fabricWaitSec;
    DSV41_MASTER_WAIT_SEC = cluster.masterWaitSec;
  };

  clusterService = {
    Unit = {
      Description = "dsv41 cluster ${node.role} (${hostName}, rank ${toString rank})";
      StartLimitIntervalSec = cluster.startLimitIntervalSec;
      StartLimitBurst = cluster.startLimitBurst;
    }
    // lib.optionalAttrs isHead {
      Conflicts = [
        "spark-vllm.service"
        "nvpair.service"
      ];
    };
    Service = {
      Type = "exec";
      Environment = [ "DSV41_CLUSTER_ENV=${nodeEnv}" ];
      ExecStartPre = [
        "${scriptDir}/prepare.sh wait-fabric"
        "${scriptDir}/prepare.sh wait-master"
        "${scriptDir}/prepare.sh preflight"
        "${scriptDir}/gid.sh"
        "-${scriptDir}/prepare.sh docker-rm"
        "${scriptDir}/prepare.sh drop-caches"
        "${scriptDir}/prepare.sh api-key"
      ];
      ExecStart = "${scriptDir}/run.sh";
      ExecStop = "/usr/bin/docker stop -t ${toString cluster.stopTimeoutSec} ${cluster.containerName}";
      Restart = "always";
      RestartSec = toString cluster.restartSec;
      TimeoutStartSec = cluster.timeoutStartSec;
      TimeoutStopSec = toString cluster.timeoutStopSec;
      KillMode = "mixed";
    }
    // lib.optionalAttrs isHead {
      ExecStartPost = "${scriptDir}/ready.sh";
    };
    Install.WantedBy = [ "default.target" ];
  };
in
{
  options.services.dsv41Cluster = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install and start this machine's unit of the dsv41 cluster.
        spark runs dsv41-cluster-head. spark2 runs dsv41-cluster-worker.
      '';
    };

    expose = lib.mkOption {
      type = lib.types.enum [
        "aperture"
        "open"
      ];
      default = cluster.expose;
      description = ''
        aperture (default): bind 127.0.0.1, require the API key file, and
        on spark publish Tailscale Serve. open: bind 0.0.0.0 with no API
        key and no Tailscale Serve change. Change this in the cluster
        attrset in users/dsv41-cluster.nix so both nodes stay in agreement.
        The CX7 rendezvous does not follow this setting.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.hasAttr hostName cluster.nodes;
        message = "dsv41 cluster has no node for ${hostName}";
      }
      {
        assertion = cluster.nodes.spark.role == "head" && cluster.nodes.spark2.role == "worker";
        message = "dsv41 cluster nodes must be spark = head and spark2 = worker";
      }
      {
        assertion = cluster.masterAddr == cluster.nodes.spark.ip;
        message = "dsv41 rendezvous address must be the head CX7 IP";
      }
      {
        assertion = node.role == "head" || node.role == "worker";
        message = "dsv41 role for ${hostName} must be head or worker";
      }
      {
        assertion = markovHash == "3e5d1845b6083e108bde9dc2a1372113";
        message = "dsv41 Markov cache hash is ${markovHash}, expected 3e5d1845b6083e108bde9dc2a1372113";
      }
    ];

    home.file = {
      ".config/dsv41/serve.sh".source = "${scriptDir}/serve.sh";
      ".config/dsv41/node.env".source = nodeEnv;
      ".config/dsv41/recipe.env".source = recipeEnv;
      ".config/dsv41/markov_top_tokens.json".source = markov;
    };

    systemd.user.services = {
      ${unitName} = clusterService;
    }
    // lib.optionalAttrs isHead {
      dsv41-cluster-health = {
        Unit.Description = "Probe the dsv41 cluster and restart the head after repeated chat failures";
        Service = {
          Type = "oneshot";
          Environment = [ "DSV41_CLUSTER_ENV=${nodeEnv}" ];
          ExecStart = "${scriptDir}/health.sh";
          TimeoutStartSec = "3min";
        };
      };
    }
    // lib.optionalAttrs (isHead && aperture) {
      dsv41-cluster-serve = {
        Unit.Description = "Publish the dsv41 cluster API on Tailscale Serve";
        Service = {
          Type = "oneshot";
          RemainAfterExit = "yes";
          ExecStart = "/usr/bin/tailscale serve --bg --https=${toString cluster.tailscaleHttpsPort} http://127.0.0.1:${toString cluster.port}";
          ExecStop = "/usr/bin/tailscale serve --https=${toString cluster.tailscaleHttpsPort} off";
          Restart = "on-failure";
          RestartSec = "10s";
        };
        Install.WantedBy = [ "default.target" ];
      };
    }
    // lib.optionalAttrs (!isHead) {
      dsv41-cluster-follow = {
        Unit.Description = "Restart the dsv41 worker when the head goes from up to down";
        Service = {
          Type = "oneshot";
          Environment = [ "DSV41_CLUSTER_ENV=${nodeEnv}" ];
          ExecStart = "${scriptDir}/follow.sh";
          TimeoutStartSec = "30s";
        };
      };
    };

    systemd.user.timers =
      lib.optionalAttrs isHead {
        dsv41-cluster-health = {
          Unit = {
            Description = "dsv41 cluster health probe every ${cluster.healthEvery}";
            After = [ "dsv41-cluster-head.service" ];
          };
          Timer = {
            OnBootSec = cluster.healthEvery;
            OnUnitActiveSec = cluster.healthEvery;
            AccuracySec = "15s";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      }
      // lib.optionalAttrs (!isHead) {
        dsv41-cluster-follow = {
          Unit.Description = "dsv41 cluster follower every ${cluster.followEvery}";
          Timer = {
            OnBootSec = cluster.followEvery;
            OnUnitActiveSec = cluster.followEvery;
            AccuracySec = "5s";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
  };
}
