# GitHub Runner on Hetzner Setup Guide

Setup guide for provisioning GitHub Actions runners on Hetzner Cloud for the `fuww` organization.

## Overview

Dedicated NixOS servers running as org-level self-hosted runners for `fuww`:

| Runner           | Instance | Provisioning | Status |
|------------------|----------|--------------|--------|
| github-runner-01 | CCX33 (dedicated cores) | Legacy rescue mode | Active |
| github-runner-02 | CPX62 (16 shared vCPUs, 32GB RAM) | disko + nixos-anywhere | Active |

Each runner:
- Registers as an org-level self-hosted runner for `fuww`
- Includes the full CI package set (Docker, languages, build tools, browsers, cloud CLIs)
- Auto-updates from `github:javdl/nixos-config#<hostname>` daily at 4 AM
- Uses SOPS-encrypted secrets for the runner token
- Connects via Tailscale for secure SSH management

## Prerequisites

- Hetzner Cloud account with a server ordered (CCX33/CPX62 or similar)
- This nixos-config repository cloned locally
- SSH key pair on your local machine
- Tailscale auth key (generate at https://login.tailscale.com/admin/settings/keys)
- GitHub classic PAT with `admin:org` scope for the `fuww` organization

## Configuration Files

| File | Purpose |
|------|---------|
| `hosts/github-runner-01.nix` | Runner 01 host config (legacy hardware import) |
| `hosts/github-runner-02.nix` | Runner 02 host config (disko + shared hardware modules) |
| `hosts/hardware/github-runner-01.nix` | Runner 01 Hetzner QEMU hardware config |
| `modules/hetzner-cloud-hardware.nix` | Shared Hetzner Cloud hardware config (used by runner-02+) |
| `modules/disko-hetzner-cloud.nix` | Shared disko partitioning for Hetzner Cloud (used by runner-02+) |
| `users/github-runner/nixos.nix` | Dedicated system user (shared across all runners) |
| `users/github-runner/home-manager-server.nix` | Minimal home-manager for CI (shared across all runners) |
| `flake.nix` | Entries: `nixosConfigurations.github-runner-{01,02}` |
| `.sops.yaml` | Age keys + creation rules for secrets |
| `secrets/github-runner-{01,02}.yaml` | SOPS-encrypted runner tokens |

## Architecture

The config merges three existing patterns:
1. **Hetzner server infra** (`hosts/desmondroid.nix`) - Tailscale, auto-update, SOPS, security audit, GC
2. **CI package set** (`modules/github-actions-runner.nix`) - Docker, languages, build tools, browsers, cloud CLIs
3. **Runner service** (`hosts/fu137.nix`) - NixOS `services.github-runners` with token + org URL

Key design choices:
- **Dedicated `github-runner` user** runs the runner process, has Docker group access
- **Joost admin user** is also present for SSH management (same as on colleague dev boxes)
- **No repo-updater** (no dev repos to sync)
- **Shorter GC retention** (7 days vs 14) since CI builds are ephemeral
- **SOPS token** instead of plaintext file (improvement over fu137/j7 pattern)
- **New runners use disko + nixos-anywhere** for single-command provisioning (no rescue mode)

## Deployment Steps

### Option A: disko + nixos-anywhere (recommended for new runners)

Used by: `github-runner-02` and all future runners.

1. Order a Hetzner server. Note the IP address.
2. Run single-command provisioning:

```bash
make hetzner/provision NIXADDR=<ip> NIXNAME=github-runner-02
```

This SSHs into the server, kexec into a NixOS installer, partitions with disko, installs NixOS with the full flake config, and reboots — all in one command.

### Option B: Legacy rescue mode bootstrap

Used by: `github-runner-01` (predates disko support).

1. Order Hetzner server. Note the IP address.
2. Boot into rescue mode (Linux 64-bit) from Hetzner Cloud Console.
3. Run bootstrap:

```bash
make hetzner/bootstrap0 NIXADDR=<ip>
```

4. After server reboots into minimal NixOS, copy and apply full config:

```bash
make hetzner/copy NIXADDR=<ip>
ssh root@<ip> "nixos-rebuild switch --flake /nix-config#github-runner-01"
```

### Phase 3: Set Up Secrets

1. Get the host's age public key:

```bash
ssh root@<ip> 'cat /etc/ssh/ssh_host_ed25519_key.pub' | ssh-to-age
```

2. Update `.sops.yaml` with the actual age key (replace the placeholder).

3. Create the encrypted secrets file:

```bash
sops secrets/github-runner-01.yaml
```

Add this content:
```yaml
github-runner-token: ghp_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

The token must be a classic PAT with `admin:org` scope for the `fuww` organization.

4. Rebuild to activate the runner service:

```bash
make hetzner/switch NIXADDR=<ip> NIXNAME=github-runner-01
```

### Phase 4: Tailscale

```bash
make hetzner/tailscale-auth NIXADDR=<ip> TAILSCALE_AUTHKEY=tskey-auth-xxx
```

### Phase 5: Commit and Push

```bash
jj describe -m "feat: add github-runner-01 Hetzner GitHub Actions runner"
jj bookmark set main -r @
jj git push
```

After push, the server's `nixosAutoUpdate` will pull from `github:javdl/nixos-config#github-runner-01` daily at 4 AM.

## Verification

1. **Runner service**: `systemctl status github-runner-fuww-runner`
2. **GitHub UI**: https://github.com/organizations/fuww/settings/actions/runners
   - runner-01 labels: `self-hosted`, `linux`, `x86_64`, `hetzner`, `nixos`, `ccx33`, `self-hosted-16-cores`
   - runner-02 labels: `self-hosted`, `linux`, `x86_64`, `hetzner`, `nixos`, `cpx62`, `self-hosted-16-cores`
3. **Auto-update timer**: `systemctl status nixos-upgrade.timer`
4. **Tailscale**: `tailscale status`

## Scaling to More Runners

To add `github-runner-03` (or beyond):

1. Copy `hosts/github-runner-02.nix` → change hostname, runner name, sops file path, instance label
2. No hardware file needed — use shared `modules/hetzner-cloud-hardware.nix` + `modules/disko-hetzner-cloud.nix`
3. Reuse `users/github-runner/` (shared across all runners via `user = "github-runner"`)
4. Add to `flake.nix`:
   ```nix
   nixosConfigurations.github-runner-03 = mkSystem "github-runner-03" {
     system = "x86_64-linux";
     user   = "github-runner";
     server = true;
   };
   ```
5. Add `.sops.yaml` entry + `secrets/github-runner-03.yaml`
6. Provision: `make hetzner/provision NIXADDR=<ip> NIXNAME=github-runner-03`
7. Run the same secrets + Tailscale steps

## GitHub Actions Workflow Integration

Workflows in `fuww/frontend` use [mikehardy/runner-fallback-action](https://github.com/mikehardy/runner-fallback-action) to prefer the self-hosted runner and fall back to `ubuntu-latest-16-cores` when it's offline or busy.

This requires a `GH_RUNNER_TOKEN` org secret:

1. Generate a classic PAT at https://github.com/settings/tokens with `admin:org` scope
2. Add it as an org secret at https://github.com/organizations/fuww/settings/secrets/actions
   - Name: `GH_RUNNER_TOKEN`
   - Repository access: repos that use the runner (at least `frontend`)

The fallback action uses this token to query runner availability via the GitHub API. Without it, the action falls back silently with a warning.

## Known Caveats

- **cachix.nix** hardcodes `trusted-users = [ "joost" "root" ]` — the `github-runner` user won't be trusted for nix. Fine since the runner only consumes packages.
- **`hashedPassword`** in `users/github-runner/nixos.nix` needs a real value. Generate with `mkpasswd -m sha-512`.
- **SOPS secrets file** can only be created after bootstrap (needs host's SSH key).
- **Runner token rotation**: When the PAT expires, update via `sops secrets/github-runner-01.yaml`, commit, push. Auto-update will apply within 24h, or use `make hetzner/switch` for immediate effect.
