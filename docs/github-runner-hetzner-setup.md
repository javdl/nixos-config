# GitHub Runner on Hetzner Setup Guide

Setup guide for provisioning a GitHub Actions runner on Hetzner Cloud for the `fuww` organization.

## Overview

This creates a dedicated NixOS server (`github-runner-01`) on Hetzner CCX33 that:
- Registers as an org-level self-hosted runner for `fuww`
- Includes the full CI package set (Docker, languages, build tools, browsers, cloud CLIs)
- Auto-updates from `github:javdl/nixos-config#github-runner-01` daily at 4 AM
- Uses SOPS-encrypted secrets for the runner token
- Connects via Tailscale for secure SSH management

## Prerequisites

- Hetzner Cloud account with a CCX33 (or similar) server ordered
- This nixos-config repository cloned locally
- SSH key pair on your local machine
- Tailscale auth key (generate at https://login.tailscale.com/admin/settings/keys)
- GitHub classic PAT with `admin:org` scope for the `fuww` organization

## Configuration Files

| File | Purpose |
|------|---------|
| `hosts/github-runner-01.nix` | Main host config (Hetzner base + runner service + SOPS) |
| `hosts/hardware/github-runner-01.nix` | Hetzner QEMU hardware config |
| `users/github-runner/nixos.nix` | Dedicated system user |
| `users/github-runner/home-manager-server.nix` | Minimal home-manager for CI |
| `flake.nix` | Entry: `nixosConfigurations.github-runner-01` |
| `.sops.yaml` | Age key + creation rule for secrets |
| `secrets/github-runner-01.yaml` | SOPS-encrypted runner token |

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

## Deployment Steps

### Phase 1: Prepare Config (done in this repo)

The NixOS configuration files should already exist. If creating a new runner, see "Scaling to More Runners" below.

### Phase 2: Bootstrap (Hetzner Rescue Mode)

1. Order Hetzner CCX33 server. Note the IP address.
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
2. **GitHub UI**: https://github.com/organizations/fuww/settings/actions/runners - runner should appear online with labels `self-hosted`, `linux`, `x86_64`, `hetzner`, `nixos`, `ccx33`
3. **Auto-update timer**: `systemctl status nixos-upgrade.timer`
4. **Tailscale**: `tailscale status`

## Scaling to More Runners

To add `github-runner-02`:

1. Copy `hosts/github-runner-01.nix` → change hostname, runner name, sops file path
2. Copy `hosts/hardware/github-runner-01.nix` → change comment only
3. Reuse `users/github-runner/` (shared across all runners via `user = "github-runner"`)
4. Add to `flake.nix`:
   ```nix
   nixosConfigurations.github-runner-02 = mkSystem "github-runner-02" {
     system = "x86_64-linux";
     user   = "github-runner";
     server = true;
   };
   ```
5. Add `.sops.yaml` entry + `secrets/github-runner-02.yaml`
6. Run the same bootstrap + secrets + Tailscale steps

## Known Caveats

- **cachix.nix** hardcodes `trusted-users = [ "joost" "root" ]` — the `github-runner` user won't be trusted for nix. Fine since the runner only consumes packages.
- **`hashedPassword`** in `users/github-runner/nixos.nix` needs a real value. Generate with `mkpasswd -m sha-512`.
- **SOPS secrets file** can only be created after bootstrap (needs host's SSH key).
- **Runner token rotation**: When the PAT expires, update via `sops secrets/github-runner-01.yaml`, commit, push. Auto-update will apply within 24h, or use `make hetzner/switch` for immediate effect.
