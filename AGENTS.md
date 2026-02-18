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
- `make hetzner/copy NIXADDR=<ip>` - Copy config to Hetzner server
- `make hetzner/switch NIXADDR=<ip> NIXNAME=hetzner-dev` - Apply NixOS config on Hetzner
- `make hetzner/bootstrap0 NIXADDR=<ip>` - Initial NixOS install (Hetzner box must be in rescue mode)
- `make hetzner/bootstrap NIXADDR=<ip>` - Complete setup after bootstrap0
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

**Deployment:** All colleague machines have `nixosAutoUpdate` pulling from `github:javdl/nixos-config#<hostname>` at 4 AM daily. To deploy changes:
1. Edit the relevant `users/<name>/home-manager-server.nix` or `hosts/<hostname>.nix`
2. Commit and push to `main` — machines auto-update on next scheduled check

**Immediate deployment** (if you can't wait for auto-update):
- `make hetzner/copy NIXADDR=<ip> NIXUSER=<user>` then `make hetzner/switch NIXADDR=<ip> NIXNAME=<hostname>`
- Or SSH in and run: `sudo nixos-rebuild switch --flake "github:javdl/nixos-config#<hostname>"`

**Bootstrap a new colleague server (full guide):**

Prerequisites: Order a Hetzner Cloud CPX32 server. Note the IP, root password, and server ID.

**Step 1: Create the NixOS configuration files**

Pick a robot-themed hostname (pattern: `<name>` + `-roid`/`-ator`/`-bot`). Create 4 files based on an existing colleague (e.g., copy Desmond's):

| File | What to change |
|------|----------------|
| `hosts/<hostname>.nix` | `networking.hostName`, `services.nixosAutoUpdate.flake`, `services.repoUpdater.user`/`projectsDir`, `users.users.<name>.shell` line, IP in comment |
| `hosts/hardware/<hostname>.nix` | Comment header only (hardware is identical for all Hetzner CPX VMs) |
| `users/<name>/nixos.nix` | `users.users.<name>` block (username, home dir, SSH keys, hashedPassword) |
| `users/<name>/home-manager-server.nix` | `programs.git` (userName, userEmail, github.user) |

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

**Step 2: Bootstrap the server (rescue mode required)**

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

**Step 3: Apply full configuration**

After the server reboots into minimal NixOS (root password: "nixos"):

```bash
# Copy config (as root since joost user may not have SSH key access yet)
rsync -av -e 'ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password' \
  --exclude={vendor/,.git/,.git-crypt/,.jj/,.beads/,iso/} \
  /path/to/nixos-config/ root@<ip>:/nix-config

# Apply the full config
ssh root@<ip> "nixos-rebuild switch --flake /nix-config#<hostname>"
```

Expected warnings after first switch:
- `repo-updater` fails (gh not authenticated yet) — normal
- `tailscaled-autoconnect` fails (no auth key yet) — normal

**Step 4: Post-bootstrap**

```bash
# Set up Tailscale (generate key at https://login.tailscale.com/admin/settings/keys)
make hetzner/tailscale-auth NIXADDR=<ip> TAILSCALE_AUTHKEY=tskey-auth-xxx

# Commit and push config so auto-update works
jj describe -m "feat: add <name> colleague server (<hostname>)"
jj bookmark set main -r @
jj git push
```

After push, the server's `nixosAutoUpdate` will pull from `github:javdl/nixos-config#<hostname>` daily at 4 AM.

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

## Common Issues

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

## Related Tools

- **Beads**: [github.com/steveyegge/beads](https://github.com/steveyegge/beads) - AI-native issue tracking
