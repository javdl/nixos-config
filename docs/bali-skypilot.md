# Bali as SkyPilot compute

Bali runs an independent, single-node K3s server managed by NixOS. The
SkyPilot API server at `skypilot.exe.xyz` uses Kubernetes integration to
schedule container workloads on it. Do not run `sky ssh up` against Bali:
that command installs and manages its own Kubernetes runtime.

## Configuration and access

The host configuration in `hosts/bali.nix` owns K3s. It uses the existing
Tailscale address `100.113.194.113`, pod network `10.52.0.0/16`, and service
network `10.53.0.0/16`. Check for route conflicts before adding other nodes.
The `host-gw` backend is intended for this single-node setup; review networking
before expanding the cluster across hosts.

No public firewall ports are added. Traefik and ServiceLB are disabled, and
NodePort addresses are restricted to loopback and Bali's Tailscale IP.
The existing trusted `tailscale0` interface still permits tailnet traffic;
Tailscale policy must restrict the remote SkyPilot identity to the required
destination. The `cni0` pod bridge is trusted for pod-to-host traffic.

The administrator kubeconfig at `/etc/rancher/k3s/k3s.yaml` is root-only.
Do not copy that administrator credential to SkyPilot. Provision a dedicated
namespace and service account using the permissions documented in
[SkyPilot's Kubernetes permissions guide](https://docs.skypilot.ai/en/latest/cloud-setup/cloud-permissions/kubernetes.html).
Jobs can run code on Bali; namespace RBAC alone is not a host isolation boundary.

## Build and activation

From the repository root:

```sh
make test NIXNAME=bali
```

Activation requires explicit approval because Bali runs existing services and
CI workers. Review the built system diff first. After approval, follow the
repository deployment procedure with `NIXNAME=bali` explicitly set. Publishing
to `main` also deploys through Bali's scheduled auto-update.

After activation, verify:

```sh
systemctl is-active k3s
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A
sudo stat -c '%a %U' /etc/rancher/k3s/k3s.yaml
```

Require a Ready node, healthy system pods, and kubeconfig mode `600 root`.
Verify pod DNS and outbound downloads before registering SkyPilot. Review CPU
and memory allocations alongside Bali's existing CI and agent workloads before
launching jobs.

## Connect and register

Connectivity remains a separate deployment decision. SkyPilot is in the
personal `buri-hoki.ts.net` tailnet; Bali is in the FashionUnited
`stargazer-duck.ts.net` tailnet.

- With approved declarative sharing, allow the SkyPilot server to reach Bali
  on TCP 6443 and use `https://bali.stargazer-duck.ts.net:6443`.
- Alternatively, prepare a persistent outbound SSH reverse tunnel from Bali
  to the exe.dev VM, binding its remote listener to loopback only and forwarding
  to Bali's Kubernetes API. Preserve Kubernetes CA verification and set the
  kubeconfig TLS server name if the tunnel endpoint differs from the certificate.
  Verify exe.dev forwarding support before relying on this path.

Create the dedicated service account credential after K3s is running. Store it
outside git, transfer it securely, and merge a uniquely named `bali` context
into `/home/exedev/.kube/config` without overwriting the existing node pool's
contexts. Use namespace `skypilot` and configure SkyPilot port-forward access
as documented in its Kubernetes setup guide. Retain existing SkyPilot settings.

On the API server, validate access with the dedicated context, then run:

```sh
kubectl --context bali get nodes
kubectl --context bali -n skypilot auth can-i create pods
/home/exedev/.local/bin/sky check kubernetes
/home/exedev/.local/bin/sky launch --infra k8s/bali --cpus 1 --memory 2 -- echo bali-ok
```

Registration is complete only after the test job returns `bali-ok`, its logs
are accessible, and the cluster appears in SkyPilot. Installing the NixOS
service alone does not complete registration. Retire the test cluster after
approval using its actual SkyPilot cluster name.
