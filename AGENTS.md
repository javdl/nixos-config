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

### Hetzner Dev Box
- `make hetzner/copy NIXADDR=<ip>` - Copy config to Hetzner server
- `make hetzner/switch NIXADDR=<ip> NIXNAME=hetzner-dev` - Apply NixOS config on Hetzner
- `make hetzner/bootstrap0 NIXADDR=<ip>` - Initial NixOS install (Hetzner box must be in rescue mode)
- `make hetzner/bootstrap NIXADDR=<ip>` - Complete setup after bootstrap0
- `make hetzner/secrets NIXADDR=<ip>` - Copy SSH/GPG keys to server
- `make hetzner/tailscale-auth NIXADDR=<ip> TAILSCALE_AUTHKEY=<key>` - Set up Tailscale

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

## Adding Claude Code Skills to Chezmoi

Skills live in `~/.claude/skills/` and are managed by chezmoi under `dot_claude/skills/` in the [dotfiles repo](https://github.com/javdl/dotfiles).

### Adding a new skill

```bash
# Copy skill into chezmoi source directory
cp -R ~/.claude/skills/<skill-name> ~/.local/share/chezmoi/dot_claude/skills/<skill-name>

# If the skill is a symlink (e.g. from ~/.agents/skills/), copy the target instead
cp -R ~/.agents/skills/<skill-name> ~/.local/share/chezmoi/dot_claude/skills/<skill-name>

# Commit and push
cd ~/.local/share/chezmoi
jj file track dot_claude/skills/<skill-name>
jj describe -m "Add <skill-name> skill"
jj git push
```

> **Note:** `chezmoi add` may error due to inconsistent state with plugins. Copying directly into the chezmoi source directory works reliably.

### Syncing skills to a new machine

```bash
chezmoi init --apply --verbose git@github.com:javdl/dotfiles.git
```

Skills are applied to `~/.claude/skills/` automatically. Home-manager also runs `chezmoi update` on every `make switch` (see `users/joost/home-manager.nix`).

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
