# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
4. For new hosts, files must be in git: `git add .`

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
