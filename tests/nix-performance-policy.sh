#!/usr/bin/env bash

set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$repo_root"

fail() {
  printf 'performance policy failed: %s\n' "$1" >&2
  exit 1
}

reject() {
  local pattern="$1"
  shift
  if rg -n "$pattern" "$@"; then
    fail "unexpected pattern: $pattern"
  fi
}

require() {
  local pattern="$1"
  shift
  if ! rg -q "$pattern" "$@"; then
    fail "required pattern missing: $pattern"
  fi
}

reject 'fh\.url|hyprland\.url' flake.nix
if ! rg -Uq 'nixos-hardware = \{\n[^}]*inputs\.nixpkgs\.follows = "nixpkgs"' flake.nix; then
  fail 'nixos-hardware must follow the primary nixpkgs input'
fi
require 'determinate\.url = "https://flakehub\.com/f/DeterminateSystems/determinate/3"' flake.nix

require 'pkgsUnstableForSystem' lib/overlays.nix
reject 'pkgs-unstable = import inputs\.nixpkgs-unstable' lib/overlays.nix

require 'mkHostEvalChecks' flake.nix
reject 'evaluated = lib\.concatStringsSep' flake.nix
require 'nix flake check --all-systems --no-build' .github/workflows/flake-checker.yml
require 'nix flake check --all-systems --no-build --no-eval-cache.*--option lazy-trees false' .github/workflows/flake-checker.yml
require 'hermes_ref=' .github/workflows/flake-checker.yml
require 'packages\.x86_64-linux\.default\.drvPath' .github/workflows/flake-checker.yml

reject 'download-buffer-size' flake.nix modules/cachix.nix hosts/mac-shared.nix
reject 'cache\.nixos\.org|hyprland\.cachix\.org' modules/cachix.nix
require 'isServer' lib/mksystem.nix modules/cachix.nix

reject 'keep-outputs|keep-derivations' hosts modules
reject 'darwinNixGC|darwin-nix-gc' hosts modules
reject 'nix-collect-garbage|nixKeepDays' modules/disk-cleanup.nix modules/ci-disk-cleanup.nix
require 'inputs\.determinate\.nixosModules\.default' hosts/bali.nix

printf 'Nix performance policy checks passed.\n'
