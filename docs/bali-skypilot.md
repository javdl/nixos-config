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
Do not copy that administrator credential to SkyPilot. The manifest
`hosts/bali-skypilot-rbac.yaml` provisions the `skypilot` namespace, the
`skypilot-api` account, and the pre-created `skypilot-workload` account using
resource-specific permissions based on
[SkyPilot's Kubernetes permissions guide](https://docs.skypilot.ai/en/latest/cloud-setup/cloud-permissions/kubernetes.html).
The API account can manage workload resources only in `skypilot`, plus read
nodes and runtime classes. It cannot write RBAC or read system namespace secrets.
The namespace enforces the Kubernetes baseline pod security standard. Jobs can
run code on Bali; namespace RBAC alone is not a host isolation boundary.

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

SkyPilot is in the
personal `buri-hoki.ts.net` tailnet; Bali is in the FashionUnited
`stargazer-duck.ts.net` tailnet.

The `skypilot-bali-tunnel` system service uses Bali's existing exe.dev SSH
identity at `/home/joost/.ssh/id_exe_fu_sites` and the trusted `exe.dev` host key
in `/home/joost/.ssh/known_hosts`. The service runs as `joost`, requires strict
host-key checking, and restarts after connection failure or reboot. Neither
private key nor Kubernetes credentials are stored in Nix or git.

It forwards `127.0.0.1:16443` on the SkyPilot VM to `127.0.0.1:6443` on Bali.
The kubeconfig endpoint is `https://127.0.0.1:16443`, with Bali's CA and
`tls-server-name: bali.stargazer-duck.ts.net`; do not skip TLS verification.
Verify recovery with `systemctl restart skypilot-bali-tunnel`, then check the
remote listener with `ss -lnt 'sport = :16443'` on the VM. It must bind only
to loopback.

Declarative Tailscale sharing can replace the tunnel after approval, but is
not required for this route.

Kubernetes populates `skypilot-api-token` at runtime. Transfer that scoped
credential only after approval, never the administrator credential. Store it
outside git at `/home/exedev/.kube/bali.yaml` with mode 600, and merge a `bali` context
into `/home/exedev/.kube/config` without overwriting the existing node pool's
contexts. Use namespace `skypilot` and configure the `bali` context's
`remote_identity` as `skypilot-workload`, so SkyPilot uses the pre-created account
instead of creating broader RBAC. Configure private port-forward access as
documented in its Kubernetes setup guide. Retain existing SkyPilot settings.
The service-account token is long-lived; rotate it if the VM or credential is
compromised, and transfer the replacement through the same approved channel.

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
