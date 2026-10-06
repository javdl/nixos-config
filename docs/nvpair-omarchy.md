# NVIDIA PAIR on fu137, j9 and radon

fu137 (RTX 3090), j9 (RTX 4090) and radon (Mac) run
[NVIDIA Personal AI Router](https://github.com/NVIDIA/Personal-AI-Router)
(PAIR) as one cluster. Each node's local proxy sends every request to a node
that holds the requested model, so an app on any member can use all of them
through `http://127.0.0.1:11434` (Ollama API) or `http://127.0.0.1:1234`
(OpenAI API).

## What Nix manages

| Piece | Source |
| --- | --- |
| `nvpair` package (desktop app, `nvpair` TUI, static Go services) | `lib/overlays.nix` (`nvpairVersion`) |
| fu137/j9: install, login autostart, root setup script | `users/nvpair-omarchy.nix`, imported by `users/joost/home-manager.nix` |
| radon: `nvidia-pair` cask | `extraCasks` in `users/joost/darwin.nix` |
| radon: kernel tailnet routing (`tun = "utun"`) | `hosts/radon.nix`, `modules/darwin-tailscaled.nix` |

PAIR has no system service on Linux. The desktop app (`nvpair-desktop`)
starts the broker and the worker services and stays in the tray when you close
its window, so `~/.config/autostart/nvpair.desktop` launches it at login. The
in-app updater is disabled because the store is read-only.

Upstream does not support a cluster with mixed PAIR versions. Homebrew sets
radon's version, so when the cask moves, bump `nvpairVersion` to match and
switch all three nodes.

Do not run `nvpair` (the TUI) while the desktop app is running. Each one starts
its own services, and the two sets fight over the same ports.

## Why radon runs tailscaled on utun

radon's headless `tailscaled` used `--tun=userspace-networking`. In that mode
PAIR could not dial peers' tailnet addresses, and incoming tailnet connections
reached PAIR as localhost, which bypasses its loopback-only rule for plaintext
proxy requests. `tun = "utun"` gives the same root launchd daemon a kernel
interface, as upstream's `tailscaled install-system-daemon` does, and keeps
`--ssh`. With real routing, `--accept-routes` now also installs advertised
subnet routes in radon's routing table.

## Which tailnet links which pair

| Link | Path | Address to add in PAIR |
| --- | --- | --- |
| j9 ↔ radon | personal tailnet, both on `tailscaled` | each node's personal Tailscale IP (`tailscale ip -4`) |
| fu137 ↔ j9 | work tailnet; j9 through its tailmix `work` profile | on fu137: j9's work-tailnet IP; on j9: `fu137`, which tailmix's DNS resolves |
| fu137 ↔ radon | personal tailnet, **only if fu137 has a tailmix profile for it** | on fu137: `radon` via tailmix DNS; on radon: fu137's personal-tailnet IP |

fu137's `tailscaled` is on the work tailnet (the Herdr fleet reaches it there).
If fu137 has no personal-tailnet profile yet, add one exactly as j9 added its
work profile in [tailmix on the Omarchy boxes](tailmix-omarchy.md), with a key
from the personal tailnet. Without it, radon and fu137 cannot reach each other.

## One-time setup

### fu137 and j9 (root)

After the first `home-manager switch` on each node, run:

```bash
nvpair-omarchy-setup   # re-execs itself with sudo
```

It does two things:

1. **Firewall.** Omarchy's ufw denies all incoming traffic. The script allows
   tcp `11434`, `1234` and `14318-14323` on `tailscale0` and `tailmix0`.
   Peers on the machine's own tailnet arrive on `tailscale0`; peers on the
   other tailnet come in through tailmix on `tailmix0`. PAIR answers plaintext
   proxy requests from loopback only, so peers must use mutual TLS with pinned
   certificates. mDNS discovery (`5353/udp`) stays closed, so add peers by
   address.
2. **Ollama port.** PAIR's proxy takes `11434` and adopts an Ollama it did not
   start if one is serving `11435`. Pacman's `ollama.service` on fu137 binds
   `11434`, which would push PAIR's proxy onto a random port that the firewall
   does not open. If `ollama.service` exists, the script adds
   `/etc/systemd/system/ollama.service.d/nvpair.conf` with
   `OLLAMA_HOST=127.0.0.1:11435` and restarts it. The models stay in
   `/var/lib/ollama`. On a node without `ollama.service`, install Ollama from
   PAIR's **Engine settings** instead; it goes to
   `~/.config/Nvidia Corporation/Personal AI Router/engine-bin/ollama`.

Restart PAIR (tray → Quit, then launch it again) after the script runs, so it
adopts Ollama on `11435`.

### radon (GUI session)

1. After the switch, check that `tailscale status` lists the peers and that
   `ifconfig | grep -A3 utun` shows the tailnet address.
2. Open **PAIR** from Applications. On first launch it asks to approve its
   background helper in **System Settings → General → Login Items &
   Extensions**. The helper configures the macOS Application Firewall for
   PAIR; relaunch PAIR after approving.
3. Add PAIR to **Login Items** so it starts with the auto-login session.

## Pair the nodes

The PIN exchange is interactive, so it is not in Nix. On each node, first
add the other two under **Add node** with the addresses from the table above,
then:

1. On j9, open **Settings → Cluster** and invite fu137.
2. On fu137, accept and enter the six-digit PIN shown on j9.
3. Repeat from j9 for radon.
4. Every node now lists the other two under **Overview**.

## Verify

```bash
curl -s http://127.0.0.1:11434/v1/models | jq '.data[].id'   # union of all nodes
ss -ltnp | grep -E ':(11434|11435|1234|1431[89]|1432[0-3]) ' # Linux nodes
sudo ufw status | grep nvpair                                # Linux nodes
```

To prove routing, pull a model on one node only, request it from another,
and check **Overview → Jobs → Ran on**.

## Consequences on fu137

- Anything that talks to `127.0.0.1:11434` (`gollama`, `ollama list`,
  `scripts/fu137-gpu-bench.py`) now goes through PAIR. `/api/tags` returns
  the cluster's models, and inference can run on another node. To measure
  fu137 alone, target the engine directly: `OLLAMA_HOST=127.0.0.1:11435`.
- PAIR's services run only while the app does. Before login, after quitting
  it, or after logging out, nothing listens on `11434`.
