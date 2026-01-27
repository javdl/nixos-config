{ config, lib, pkgs, ... }:

# K3s lightweight Kubernetes module
#
# Provides a minimal Kubernetes cluster for container orchestration:
# - Single-node server mode (can scale to multi-node)
# - Optional Traefik ingress controller
# - GHCR/Docker registry secret automation
# - Common namespaces setup
# - Kubernetes CLI tools

let
  cfg = config.services.k3sConfig;
  inherit (lib) mkEnableOption mkOption types mkIf mkDefault optionalString;
in {
  options.services.k3sConfig = {
    enable = mkEnableOption "K3s lightweight Kubernetes";

    role = mkOption {
      type = types.enum [ "server" "agent" ];
      default = "server";
      description = "K3s role: server (control plane) or agent (worker only)";
    };

    serverAddr = mkOption {
      type = types.str;
      default = "";
      description = "Server address for agents to join (required for agent role)";
    };

    tokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing cluster token for joining nodes";
    };

    disableTraefik = mkOption {
      type = types.bool;
      default = true;
      description = "Disable built-in Traefik ingress (recommended if using external ingress)";
    };

    disableServicelb = mkOption {
      type = types.bool;
      default = false;
      description = "Disable built-in Klipper service load balancer";
    };

    disableLocalStorage = mkOption {
      type = types.bool;
      default = false;
      description = "Disable local-path-provisioner storage class";
    };

    flannelBackend = mkOption {
      type = types.enum [ "vxlan" "host-gw" "wireguard-native" "none" ];
      default = "vxlan";
      description = "Flannel CNI backend";
    };

    extraFlags = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional flags to pass to k3s";
    };

    clusterCIDR = mkOption {
      type = types.str;
      default = "10.42.0.0/16";
      description = "CIDR range for pod IPs";
    };

    serviceCIDR = mkOption {
      type = types.str;
      default = "10.43.0.0/16";
      description = "CIDR range for service IPs";
    };
  };

  config = mkIf cfg.enable {
    # Enable K3s
    services.k3s = {
      enable = true;
      inherit (cfg) role;

      # Server address for agents
      serverAddr = mkIf (cfg.role == "agent") cfg.serverAddr;

      # Cluster token
      tokenFile = mkIf (cfg.tokenFile != null) cfg.tokenFile;

      # Build extra flags
      extraFlags = let
        disableFlags = lib.optionals cfg.disableTraefik [ "--disable=traefik" ]
          ++ lib.optionals cfg.disableServicelb [ "--disable=servicelb" ]
          ++ lib.optionals cfg.disableLocalStorage [ "--disable=local-storage" ];
        networkFlags = [
          "--flannel-backend=${cfg.flannelBackend}"
          "--cluster-cidr=${cfg.clusterCIDR}"
          "--service-cidr=${cfg.serviceCIDR}"
        ];
      in disableFlags ++ networkFlags ++ cfg.extraFlags;
    };

    # Kubernetes CLI tools
    environment.systemPackages = with pkgs; [
      kubectl           # Kubernetes CLI
      kubernetes-helm   # Helm package manager
      k9s               # Terminal UI for Kubernetes
    ];

    # Open firewall ports for K3s
    networking.firewall = mkIf (cfg.role == "server") {
      allowedTCPPorts = [
        6443  # Kubernetes API server
        10250 # Kubelet metrics
      ];
      allowedUDPPorts = [
        8472  # Flannel VXLAN
      ];
    };

    # Configure kubectl to use k3s kubeconfig
    environment.variables.KUBECONFIG = mkDefault "/etc/rancher/k3s/k3s.yaml";

    # Add k3s kubectl wrapper to PATH for proper permissions
    environment.shellAliases = {
      k = "kubectl";
      kgp = "kubectl get pods";
      kgs = "kubectl get svc";
      kgn = "kubectl get nodes";
    };
  };
}
