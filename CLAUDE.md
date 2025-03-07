# NixOS Config Development Guide

## Build Commands
- `make switch` - Switch to the current configuration 
- `make update` - Update flake.lock and switch to new configuration
- `make upgrade` - Update packages and switch configuration
- `make test` - Test the current configuration without applying changes
- `make wsl` - Build a WSL installer
- `sudo nixos-rebuild switch --flake ".#<host>"` - Switch to specific host config

## Code Style Guidelines
- Use two-space indentation for all Nix files
- Follow camelCase naming convention for variables
- Use descriptive module and option names
- Structure imports at the top of files in a consistent order
- Use `let...in` expressions for local variable definitions
- Prefer attribute sets for structured data
- Use `inherit` keyword to reduce repetition
- Write meaningful comments for complex code sections
- Use multiline strings with `''` delimiters
- Follow standard module structure: `{ config, lib, pkgs, ... }: { ... }`
- Use conditional expressions with `lib.optionals` for platform-specific code
- Maintain consistent overlay and module import patterns

## Common Tasks
- Adding new packages: Add to `users/<user>/home-manager.nix`
- Adding system configurations: Add to `hosts/` and update `flake.nix`
- Testing: Run `make test` before commits