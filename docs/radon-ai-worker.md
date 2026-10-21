# Radon AI-worker profile

Radon is managed by `darwinConfigurations.radon` (macOS/nix-darwin), not NixOS.

## Scope

- Homebrew applications: Bitwarden, Blender, Brave Origin, Chrome and NVIDIA PAIR.
- Homebrew formulas: Podman (CLI only) and Tailscale. Nix agent tooling remains.
- Home Manager uses the existing minimal desktop profile; heavyweight AI tooling
  stays available, including Hermes and computer-use tooling.
- No VICREO listener or PAI voice-server launch agent on radon.
- System rebuilds run Sundays at 04:00; other hosts retain daily scheduling.
- Scheduled Codex/Claude checks run every seven days, not at login. Activation
  still bootstraps/checks these tools. Apple security-update settings are unchanged.

## Verification and deployment

```sh
nix eval --impure --json --file tests/radon-worker.nix
make test NIXNAME=radon
# Only after reviewing the change and approving activation:
make switch NIXNAME=radon
```

The build does not install Homebrew casks or exercise Blender rendering or GUI
permissions. Test those after an approved activation.

## Cleanup is a separate operation

Homebrew cleanup is explicitly `none`: removing an application from the desired
list does not uninstall it. This change therefore does not reclaim disk space
from old Homebrew applications. Review installed applications and their data
before removing anything. Do not delete browser profiles, credentials, model
weights, VM disks, user projects or Nix rollback generations indiscriminately.
The existing local Hermes WebUI commit is separate from this profile change.
