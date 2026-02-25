# Agents Operational Guide

## Issue Tracking

This project uses **bd (beads)** for issue tracking.
Run `bd prime` for workflow context, or install hooks (`bd hooks install`) for auto-injection.

**Quick reference:**
- `bd ready` - Find unblocked work
- `bd create "Title" --type task --priority 2` - Create issue
- `bd close <id>` - Complete work
- `bd sync` - Sync with jj/git (run at session end)

For full workflow details: `bd prime`

## Project Overview
This is a NixOS/nix-darwin configuration repository using Nix flakes. It manages system configurations for multiple hosts including macOS (Darwin), NixOS VMs, WSL, and bare metal Linux installations.

## Build Commands

### Primary Commands
- `make switch` - Apply configuration to current system (detects OS type automatically)
- `make test` - Test configuration without applying changes
- `make update` - Update flake.lock and switch to new configuration
- `make upgrade` - Update packages and switch configuration

### Platform-Specific
- `make wsl` - Build WSL installer tarball
- `sudo nixos-rebuild switch --flake ".#<host>"` - Switch to specific host config
- `nix flake update` - Update all flake inputs

### VM Management
- `make vm/bootstrap0` - Initial NixOS install on VM
- `make vm/bootstrap` - Complete VM setup with configurations
- `make vm/copy` - Copy configs to VM
- `make vm/switch` - Apply changes in VM

### Hetzner Dev Box (joost)
- `make hetzner/provision NIXADDR=<ip> NIXNAME=<hostname>` - **Single-command provisioning** (no rescue mode needed, uses nixos-anywhere + disko)
- `make hetzner/copy NIXADDR=<ip>` - Copy config to Hetzner server
- `make hetzner/switch NIXADDR=<ip> NIXNAME=hetzner-dev` - Apply NixOS config on Hetzner
- `make hetzner/bootstrap0 NIXADDR=<ip>` - Initial NixOS install (legacy, requires rescue mode)
- `make hetzner/bootstrap NIXADDR=<ip>` - Complete setup after bootstrap0 (legacy)
- `make hetzner/secrets NIXADDR=<ip>` - Copy SSH/GPG keys to server
- `make hetzner/tailscale-auth NIXADDR=<ip> TAILSCALE_AUTHKEY=<key>` - Set up Tailscale

### Colleague Dev Servers
Each colleague has a dedicated NixOS server config with auto-update enabled:

| Colleague | Host Config     | Flake Target     | User Config                           |
|-----------|-----------------|------------------|---------------------------------------|
| Desmond   | `desmondroid`   | `#desmondroid`   | `users/desmond/home-manager-server.nix` |
| Jackson   | `jacksonator`   | `#jacksonator`   | `users/jackson/home-manager-server.nix` |
| Jeevan    | `jeevanator`    | `#jeevanator`    | `users/jeevan/home-manager-server.nix`  |
| Lennard   | `lennardroid`   | `#lennardroid`   | `users/lennard/home-manager-server.nix` |
| Peter     | `peterbot`      | `#peterbot`      | `users/peter/home-manager-server.nix`   |
| Rajesh    | `rajbot`        | `#rajbot`        | `users/rajesh/home-manager-server.nix`  |

### GitHub Actions Runner
Dedicated self-hosted runner for the `fuww` GitHub organization:

| Server           | Host Config          | Flake Target          | Instance | User Config                              |
|------------------|----------------------|-----------------------|----------|------------------------------------------|
| github-runner-01 | `github-runner-01`   | `#github-runner-01`   | CCX33    | `users/github-runner/home-manager-server.nix` |
| github-runner-02 | `github-runner-02`   | `#github-runner-02`   | CPX62    | `users/github-runner/home-manager-server.nix` |

The runners use `modules/github-actions-runner.nix` for CI packages (Docker, languages, build tools, browsers, cloud CLIs) and `services.github-runners` for runner registration. Tokens are SOPS-encrypted in `secrets/github-runner-{01,02}.yaml`. See `docs/github-runner-hetzner-setup.md` for full setup/scaling guide.

**Runner token type:** The `tokenFile` must contain an **org-level runner registration token** (format: `AAU5P4...`, 29 chars), NOT a GitHub PAT. Get it from https://github.com/organizations/fuww/settings/actions/runners/new → copy the `--token` value. Tokens expire in 1 hour and are single-use.

**SOPS chicken-and-egg for new runners:** New servers don't have SSH host keys until provisioned, but the NixOS build needs an encrypted secrets file. Solution: temporarily use a known age key (e.g., loom's) in `.sops.yaml`, encrypt secrets, provision, then re-key with the server's real age key after provisioning.

**SSH after provisioning:** Root SSH has no authorized keys — always SSH as `joost@<ip>` and use `sudo`. Run `ssh-keygen -R <ip>` first since the host key changes.

To scale: copy `hosts/github-runner-02.nix`, change hostname/runner name/sops path/instance label, reuse `users/github-runner/`, add flake.nix + `.sops.yaml` entries. New runners use disko + nixos-anywhere (no rescue mode).

**Deployment:** All colleague machines have `nixosAutoUpdate` pulling from `github:javdl/nixos-config#<hostname>` at 4 AM daily. To deploy changes:
1. Edit the relevant `users/<name>/home-manager-server.nix` or `hosts/<hostname>.nix`
2. Commit and push to `main` — machines auto-update on next scheduled check

**Immediate deployment** (if you can't wait for auto-update):
- `make hetzner/copy NIXADDR=<ip> NIXUSER=<user>` then `make hetzner/switch NIXADDR=<ip> NIXNAME=<hostname>`
- Or SSH in and run: `sudo nixos-rebuild switch --flake "github:javdl/nixos-config#<hostname>"`

**Bootstrap a new colleague server (full guide):**

Prerequisites: Order a Hetzner Cloud CPX32 server. Note the IP, root password, and server ID.

**Step 1: Create the NixOS configuration files**

Pick a robot-themed hostname (pattern: `<name>` + `-roid`/`-ator`/`-bot`). Create 3 files based on an existing colleague (e.g., copy Desmond's):

| File | What to change |
|------|----------------|
| `hosts/<hostname>.nix` | `networking.hostName`, `services.nixosAutoUpdate.flake`, `services.repoUpdater.user`/`projectsDir`, `users.users.<name>.shell` line, IP in comment. Import `../modules/hetzner-cloud-hardware.nix` and `../modules/disko-hetzner-cloud.nix` in the hardware config. |
| `users/<name>/nixos.nix` | `users.users.<name>` block (username, home dir, SSH keys, hashedPassword) |
| `users/<name>/home-manager-server.nix` | `programs.git` (userName, userEmail, github.user) |

New hosts no longer need a separate `hosts/hardware/<hostname>.nix` — they import the shared `modules/hetzner-cloud-hardware.nix` and `modules/disko-hetzner-cloud.nix` modules directly.

Then add to `flake.nix`:
```nix
nixosConfigurations.<hostname> = mkSystem "<hostname>" {
  system = "x86_64-linux";
  user   = "<name>";
  server = true;
};
```

Update the colleague table in this file.

TODOs to fill in later: SSH public key, `hashedPassword` (generate with `mkpasswd -m sha-512`), git email/GitHub username.

**Step 2: Provision the server (single command, no rescue mode)**

```bash
# Provision directly from any running Linux (e.g., Hetzner's default Ubuntu)
# Uses nixos-anywhere + disko for declarative partitioning
make hetzner/provision NIXADDR=<ip> NIXNAME=<hostname>
```

This will SSH into the server, kexec into a NixOS installer, partition the disk with disko, install NixOS with the full flake config, and reboot — all in one command.

Expected warnings after first boot:
- `repo-updater` fails (gh not authenticated yet) — normal
- `tailscaled-autoconnect` fails (no auth key yet) — normal

**Step 3: Post-provisioning**

```bash
# Set up Tailscale (generate key at https://login.tailscale.com/admin/settings/keys)
make hetzner/tailscale-auth NIXADDR=<ip> TAILSCALE_AUTHKEY=tskey-auth-xxx

# Commit and push config so auto-update works
jj describe -m "feat: add <name> colleague server (<hostname>)"
jj bookmark set main -r @
jj git push
```

After push, the server's `nixosAutoUpdate` will pull from `github:javdl/nixos-config#<hostname>` daily at 4 AM.

<details>
<summary>Legacy bootstrap (rescue mode required, for non-disko hosts)</summary>

The `make hetzner/bootstrap0` command requires interactive SSH (for password auth to rescue system). If running from Claude Code (non-interactive), use this script-based approach:

```bash
# 1. Create /tmp/bootstrap-<hostname>.sh with the full install script:
#    - Mount partitions (or partition first if fresh disk)
#    - Install Nix: curl ... | sh -s -- install linux --no-confirm --init none
#    - Source nix profile, start nix-daemon in background
#    - nix-env -f '<nixpkgs>' -iA nixos-install-tools  (CRITICAL: nix doesn't include these)
#    - nixos-generate-config --root /mnt
#    - Write minimal bootstrap configuration.nix (SSH enabled, root password "nixos")
#    - nixos-install --root /mnt --no-root-passwd
#    - reboot

# 2. Copy and run:
scp /tmp/bootstrap-<hostname>.sh root@<ip>:/tmp/bootstrap.sh
ssh root@<ip> "bash /tmp/bootstrap.sh"
```

Key gotchas for non-interactive (Claude Code) SSH:
- Use `expect` with `-o PreferredAuthentications=password` (agent has too many keys, hangs)
- Use `parted -s` (not `parted`) to avoid interactive confirmation prompts
- Use `mkfs.ext4 -F` to force without confirmation
- The Determinate Nix installer does NOT include `nixos-generate-config` or `nixos-install` — you MUST install `nixos-install-tools` via `nix-env` first
- After sourcing nix-daemon.sh, start the daemon manually: `/nix/var/nix/profiles/default/bin/nix-daemon &`

After bootstrap0, apply full config:

```bash
rsync -av -e 'ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password' \
  --exclude={vendor/,.git/,.git-crypt/,.jj/,.beads/,iso/} \
  /path/to/nixos-config/ root@<ip>:/nix-config

ssh root@<ip> "nixos-rebuild switch --flake /nix-config#<hostname>"
```

</details>

## Architecture

### Core Structure
The repository uses a modular architecture with clear separation of concerns:

- **flake.nix**: Central entry point defining all system configurations and overlays
- **lib/mksystem.nix**: Factory function that creates system configurations, handling platform differences (Darwin/Linux/WSL)
- **hosts/**: Individual host configurations with hardware-specific settings
- **users/**: User-specific configurations split into home-manager.nix, nixos.nix (Linux), and darwin.nix (macOS)
- **modules/**: Reusable system modules (GPU drivers, window managers, etc.)
- **overlays/**: Package overrides and custom builds

### Key Design Patterns

1. **Platform Detection**: The mksystem function automatically handles differences between Darwin, Linux, and WSL
2. **Overlay System**: Uses overlays to pull packages from nixpkgs-unstable when needed
3. **Home Manager Integration**: User environments managed separately from system config
4. **Shared Configuration**: `shared-home-manager.nix` provides common settings across users

### Adding Configurations

**New Host**:
1. Create `hosts/<hostname>.nix` with system configuration
2. If bare metal, add `hosts/hardware/<hostname>.nix`
3. Add entry in flake.nix following existing pattern
4. Use appropriate mksystem parameters (darwin, wsl, raphael, pstate, zenpower)

**New Package**:
- User packages: Add to `users/<user>/home-manager.nix` in `home.packages`
- Global overlay: Add to flake.nix overlay section for unstable packages
- Custom overlay: Create in `overlays/` directory

## Code Style

- Two-space indentation for all Nix files
- camelCase for variables
- Module structure: `{ config, lib, pkgs, ... }: { ... }`
- Use `lib.optionals` for platform-specific code
- Use `inherit` to reduce repetition
- Multiline strings with `''` delimiters

## Testing Workflow

1. Run `make test` before applying changes
2. Check for evaluation errors
3. Apply with `make switch` when ready
4. For new hosts, files must be tracked: `jj file track .`

## Package Management

### Finding Packages
- `nix search nixpkgs <package>` - Search for packages
- Check if already used: `rg "pkgs.<package>" users/`

### Rust/Cargo Updates
To use latest Rust toolchain, add to flake.nix overlays:
```nix
rustup = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.rustup;
```

## Overlay Packaging Patterns

The flake.nix overlay uses three patterns for third-party tools:
1. **Pre-built binary from GitHub releases** (preferred) — `fetchurl` + copy binary (beads, ntm, dcg, caam, etc.)
2. **Pre-built binary from npm registry** — `fetchurl` of platform-specific npm tarball (codex)
3. **Build from source** (last resort) — `buildRustPackage` or `overrideAttrs` (cass, gemini-cli)

Prefer pre-built binaries. Building from source is slow and fragile with hash pinning.

### Testing Overlay Changes
Overlays are internal to the flake (not exposed as outputs). You cannot test individual overlays with `nix build .#<pkg>`. Use `make test NIXNAME=loom` to validate overlay changes.

### Nix Hash Gotcha
`nix-prefetch-url --unpack` gives a DIFFERENT hash than `fetchurl`. If using `fetchurl` + manual `tar xzf` in unpackPhase, use `nix-prefetch-url` WITHOUT `--unpack` to get the correct hash.

## Common Issues

### bd broken on loom
`bd` has a broken libicu dependency (`libicui18n.so.74`). Use `br` (beads_rust) instead for all beads operations.

### Nix Command Not Found
Ensure Nix is installed and experimental features enabled:
```bash
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
```

### Package Collisions
Run: `sudo nix-store --verify --check-contents --repair`

### macOS Sequoia Issues
If nixbld users missing, run the migration script from NixOS/nix repository

## Important Files

- `Makefile`: All build/deploy commands with OS detection
- `flake.nix`: System definitions and package overlays
- `lib/mksystem.nix`: System builder function
- `users/joost/home-manager.nix`: Main user package list
- `users/shared-home-manager.nix`: Shared user settings

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

## NTM Flywheel Tools

All dev servers include the following AI agent tooling. Run `ntm deps -v` to check health status.

| Tool | Command | What it does |
|------|---------|-------------|
| ntm | `ntm` | Named Tmux Manager — spawn, coordinate, and monitor AI agents across tmux panes |
| bd/br | `bd` / `br` | Beads issue tracker (bd = alias for br, the fast Rust port) |
| bv | `bv` | Beads Viewer TUI — kanban board, DAG visualization, PageRank prioritization |
| caam | `caam` | Instant auth switching for AI coding subscriptions (Claude Max, GPT Pro, Gemini Ultra) |
| cass | `cass` | Index and search AI coding agent session history across all tools |
| cm | `cm` | CASS Memory — procedural cross-agent persistent memory system |
| caut | `caut` | Track and monitor LLM provider usage across AI coding agents (cargo nightly install) |
| dcg | `dcg` | Destructive Command Guard — blocks dangerous git/shell commands from AI agents |
| ubs | `ubs` | Ultimate Bug Scanner — static analysis catching 1000+ bug patterns |
| grepai | `grepai` | Semantic code search for AI coding assistants |
| am | `am` | Agent Mail — MCP HTTP server for async multi-agent coordination (systemd service) |
| ru | `ru` | Repo Updater — parallel GitHub repo clone/pull sync |

### Installation notes

- Most tools are pre-built binaries installed via Nix overlay (`flake.nix`)
- **caut** is installed via `cargo nightly` activation script (needs sqlite for linking)
- **caam** wrapper translates `--version` flag to `version` subcommand (ntm compatibility)
- **cass** index is rebuilt on each `make switch` via activation script
- **agent-mail** runs as a systemd user service (`systemctl --user status agent-mail`)
- `~/.cargo/bin` is in PATH via `home.sessionPath` for cargo-installed tools

## Related Tools

- **Beads**: [github.com/steveyegge/beads](https://github.com/steveyegge/beads) - AI-native issue tracking
