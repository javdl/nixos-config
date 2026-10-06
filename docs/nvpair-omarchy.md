# NVIDIA PAIR on fu137 and j9

fu137 (RTX 3090) and j9 (RTX 4090) run
[NVIDIA Personal AI Router](https://github.com/NVIDIA/Personal-AI-Router)
(PAIR) as one cluster. Each node's local proxy sends every request to a node
that holds the requested model, so an app on either machine can use both
GPUs through `http://127.0.0.1:11434` (Ollama API) or `http://127.0.0.1:1234`
(OpenAI API).

## What Nix manages

| Piece | Source |
| --- | --- |
| `nvpair` package (desktop app, `nvpair` TUI, static Go services) | `lib/overlays.nix` (`nvpairVersion`) |
| Install, login autostart, root setup script | `users/nvpair-omarchy.nix`, imported by `users/joost/home-manager.nix` |

PAIR has no system service on Linux. The desktop app (`nvpair-desktop`)
starts the broker and the worker services and stays in the tray when you close
its window, so `~/.config/autostart/nvpair.desktop` launches it at login. The
in-app updater is disabled because the store is read-only. Upgrade by bumping
`nvpairVersion` and switching **both** nodes; upstream does not support a
cluster with mixed PAIR versions.

Do not run `nvpair` (the TUI) while the desktop app is running. Each one starts
its own services, and the two sets fight over the same ports.

## One-time root setup, per node

After the first `home-manager switch` on each node, run:

```bash
nvpair-omarchy-setup   # re-execs itself with sudo
```

It does two things:

1. **Firewall.** Omarchy's ufw denies all incoming traffic. The script allows
   tcp `11434`, `1234` and `14318-14323` on `tailscale0` only, so the nodes
   reach each other over the tailnet. PAIR answers plaintext proxy requests
   from loopback only; peers must use mutual TLS with pinned certificates.
   mDNS discovery (`5353/udp`) stays closed, so pair by Tailscale address.
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

## Pair the nodes

The PIN exchange is interactive, so it is not in Nix:

1. On fu137, open PAIR → **Settings → Cluster**, invite by address with j9's
   Tailscale IP (`tailscale ip -4 j9`).
2. On j9, accept the invitation and enter the six-digit PIN shown on fu137.
3. Both nodes now list each other under **Overview**.

## Verify

```bash
curl -s http://127.0.0.1:11434/v1/models | jq '.data[].id'   # union of both nodes
ss -ltnp | grep -E ':(11434|11435|1234|1431[89]|1432[0-3]) '
sudo ufw status | grep nvpair
```

To prove routing, pull a model on one node only, request it from the other,
and check **Overview → Jobs → Ran on**.

## Consequences on fu137

- Anything that talks to `127.0.0.1:11434` (`gollama`, `ollama list`,
  `scripts/fu137-gpu-bench.py`) now goes through PAIR. `/api/tags` returns
  the cluster's models, and inference can run on j9. To measure fu137 alone,
  target the engine directly: `OLLAMA_HOST=127.0.0.1:11435`.
- PAIR's services run only while the app does. Before login, after quitting
  it, or after logging out, nothing listens on `11434`.
