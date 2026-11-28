# Beacon fleet capture

[Beacon](https://github.com/Asymptote-Labs/agent-beacon) records coding-agent
sessions on joost's own machines in this repo and ships them to bali, which keeps one fleet
log and serves a dashboard over it. Nothing goes to Beacon Cloud. Source:
[`users/beacon.nix`](../users/beacon.nix), package `beacon` in
[`lib/overlays.nix`](../lib/overlays.nix).

## What runs where

Every machine that imports `users/joost/home-manager.nix` or
`home-manager-server.nix`: bali, the Darwin hosts, joost's NixOS desktops,
and the Omarchy profiles (fu137, j9, mba). Not covered: the DGX Sparks,
joostclaw, github-runner users, and the FashionUnited hosts, which live in
fuww/fashionunited.

| Unit | Does |
| --- | --- |
| `beacon-sync` (timer / launchd, every 5 min) | `beacon endpoint <rt> sync` for each runtime in `sweptRuntimes` with any of its stores under `$HOME` (cursor: `~/.cursor`, `~/.config/Cursor`, or `~/Library/Application Support/Cursor`). On bali the hermes sweep is skipped: `HERMES_HOME` there is the shared gateway. The first runs import all history; the cursor lives in `~/.beacon/endpoint/state/`. |
| `beacon-shipper` | Vector (`beacon-vector` on Linux; nixpkgs `vector` on Darwin, whose Beacon archives have no Vector) tails `~/.beacon/endpoint/logs/runtime.jsonl*` and sends lines to `100.113.194.113:6100` with a 1 GiB disk buffer. |
| activation `beaconEndpoint` | Installs Beacon's omp extension (`~/.omp/agent/extensions/beacon.ts`) for live omp capture. Starts no process. |

bali also runs:

| Unit | Does |
| --- | --- |
| `beacon-receiver` | `beacon-vector` listening on `100.113.194.113:6100`, appending each line unchanged to `~/.local/share/beacon-fleet/runtime.jsonl`. Never rotated; this is the archive. |
| `beacon-dashboard` | Reindexes `history.db` next to the log, then serves the dashboard on `127.0.0.1:8766`. |

Linux logs: `journalctl --user -u beacon-<unit>`. Darwin logs:
`~/Library/Logs/beacon-{shipper,sync}.log`.

## Access

Transcripts are private: every unit runs with umask `077`, and the state,
log, and fleet directories are made owner-only on each start.

- `hosts/bali.nix` refuses TCP 6100 on every interface except `tailscale0`,
  including `cni0`, which bali otherwise trusts for K3s pods.
- The dashboard has no login. An `OUTPUT` rule on `lo` rejects connections to
  8766 from any UID other than joost, so the github-runner user and other
  local accounts cannot read it. Members of the `docker` group (github-runner)
  can still become root; do not treat this as a boundary against them.

## View the dashboard

```bash
ssh -L 8766:127.0.0.1:8766 bali
# open http://127.0.0.1:8766
```

## Check a machine is shipping

1. `beacon-sync` ran: `systemctl --user list-timers beacon-sync.timer` and
   `journalctl --user -u beacon-sync -n 20` (Darwin: the sync log). Each runtime
   prints `<rt> sync: N sessions ...`; `sessions_pending` means the 60 MiB local
   ring is full and the next run continues.
2. Local log grows: `wc -l ~/.beacon/endpoint/logs/runtime.jsonl`.
3. Shipper is connected: `journalctl --user -u beacon-shipper -n 20` shows no
   repeated connection errors.
4. On bali: `grep -c '"hostname":"<host>"' ~/.local/share/beacon-fleet/runtime.jsonl`.

## Caveats

- bali is reached on its FashionUnited tailnet address. A machine off that
  tailnet buffers up to 1 GiB on disk (`~/.local/state/beacon-fleet/shipper`)
  and sends it once it can reach bali. Past 1 GiB the shipper stops reading
  the log, and events that rotate out of the 60 MiB local ring meanwhile are
  lost.
- omp sessions from before the extension was installed are not imported. Do
  not run `beacon endpoint pi sync` against omp sessions; it labels them as
  `pi_cli`.

## Bump the version

1. Set `beaconVersion` in `lib/overlays.nix`. Pin the `v*` tag; GitHub's
   "latest" release is the browser extension.
2. Replace the four hashes from
   `gh release download v<version> --repo Asymptote-Labs/agent-beacon -p checksums.txt`.
3. If Beacon adds a sweep runtime, add it to `sweptRuntimes` in
   `users/beacon.nix` with its default store path from
   `cli/beacon/internal/<rt>session/` in the Beacon source.
4. Build bali and one Darwin host, check `beacon --version`, then switch.
