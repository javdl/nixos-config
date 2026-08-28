# Agents Operational Guide

## Operating Principles (applied throughout this file)

1. **Audit consumers before changing a config value.** If a field is interpolated (`${X}/...`), grep every file that consumes it and confirm the consumer handles your new value's shape (no unexpanded tildes, no unexpanded env vars).
2. **Model the system before acting in it.** Auto-syncs, hooks, schedules, and races are documented in this file and in dotfiles. Read them first. Don't get surprised by behavior the docs already explained.
3. **Expand scope to paired infrastructure.** Before removing X, grep for siblings (X→Y same prefix/suffix, same module-directory pattern, same purpose comment). Surface them: "should Y go too?"
4. **Investigate before asking.** Read the upstream README/source/`--help` before drafting a plan or presenting a question menu. The answer is often two grep calls away.
5. **Verify after every change.** Execute the runtime path of what changed, not just "the edit applied". For configs, trigger the consumer. For binaries, run `--version` *and* a representative subcommand.
6. **Don't blindly stage Plans/.** Auto-generated plan-mode files (`Plans/now-*.md`) are gitignored; descriptive plan docs commit normally. Check names before `git add Plans/`.



## Project Overview
This is a NixOS/nix-darwin configuration repository using Nix flakes. It manages system configurations for multiple hosts including macOS (Darwin), NixOS VMs, WSL, and bare metal Linux installations.

## Build Commands

### Primary Commands

**Always pass `NIXNAME=<hostname>` explicitly.** The Makefile defaults `NIXNAME ?= vm-intel`, so an unqualified `make switch` silently targets the wrong host. The OS branch (Darwin vs NixOS) is detected automatically; the host name is not.

- `make switch NIXNAME=<host>` - Apply configuration to the named host (e.g. `make switch NIXNAME=fu146`)
- `make test NIXNAME=<host>` - Test configuration without applying changes
- `make update NIXNAME=<host>` - Update flake.lock and switch
- `make upgrade NIXNAME=<host>` - Update packages and switch

`<host>` is the matching key in `flake.nix` `darwinConfigurations` / `nixosConfigurations` (usually `hostname -s` on the local machine).

### Platform-Specific
- `make wsl` - Build WSL installer tarball
- `sudo nixos-rebuild switch --flake ".#<host>"` - Switch to specific host config
- `nix flake update` - Update all flake inputs

### VM Management
- `make vm/bootstrap0` - Initial NixOS install on VM
- `make vm/bootstrap` - Complete VM setup with configurations
- `make vm/copy` - Copy configs to VM
- `make vm/switch` - Apply changes in VM

### Scraper Machine (fu146)
Mac Studio M1 configured as a minimal scraping workstation. Uses `isMinimal` flag in `darwin.nix` and `home-manager.nix` to install only browsers (Chrome, Chrome Canary, Firefox, Firefox Dev Edition, Brave, LibreWolf, Zen) and essential tools (Bitwarden, Google Drive, Companion, Linear, Zed, Podman, etc.). No IDEs, creative apps, audio tools, or social apps. Chrome Canary is used for scraping with Claude Code.

Apply config from GitHub: `darwin-rebuild switch --flake "github:javdl/nixos-config#fu146"`

### Hetzner Servers
- `make hetzner/provision NIXADDR=<ip> NIXNAME=<hostname>` - **Single-command provisioning** (no rescue mode needed, uses nixos-anywhere + disko)
- `make hetzner/copy NIXADDR=<ip>` - Copy config to Hetzner server
- `make hetzner/switch NIXADDR=<ip> NIXNAME=<hostname>` - Apply NixOS config on Hetzner
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
| ~~Lennard~~ | ~~`lennardroid`~~ | N/A            | **DECOMMISSIONED 2026-07-28**: server gone; `hosts/lennardroid.nix`, `hosts/hardware/lennardroid.nix` and `users/lennard/` deleted |
| Peter     | `peterbot`      | `#peterbot`      | `users/peter/home-manager-server.nix`   |
| Rajesh    | `rajbot`        | `#rajbot`        | `users/rajesh/home-manager-server.nix`  |

### GitHub Actions Runner
Dedicated self-hosted runner for the `fuww` GitHub organization:

| Server           | Host Config          | Flake Target          | Instance         | User Config                              |
|------------------|----------------------|-----------------------|------------------|------------------------------------------|
| ~~github-runner-02~~ | `github-runner-02`   | `#github-runner-02`   | CPX62 (cloud)    | **DECOMMISSIONED 2026-07-28**: cloud VM deleted; fleet is dedicated-EX63 only |
| github-runner-03 | `github-runner-03`   | `#github-runner-03`   | EX63 (dedicated) | `users/github-runner/home-manager-server.nix` |
| github-runner-04 | `github-runner-04`   | `#github-runner-04`   | EX63 (dedicated, 178.63.233.19) | `users/github-runner/home-manager-server.nix` |
| github-runner-05 | `github-runner-05`   | `#github-runner-05`   | EX63 (dedicated, 144.76.86.24)  | `users/github-runner/home-manager-server.nix` |
| ~~github-runner-06~~ | `github-runner-06`   | `#github-runner-06`   | EX63 (dedicated, 136.243.104.36) | **DECOMMISSIONED 2026-07-20**: box repurposed as `bali` |

### bali (loom replacement)

`bali` (EX63 dedicated, 136.243.104.36, Tailscale 100.113.194.113, ex-github-runner-06)
is loom's replacement: a clone of `hosts/loom.nix` on `hetzner-dedicated-hardware` +
`disko-hetzner-dedicated`, root disk pinned by NVMe EUI (enumeration on this box is
unstable across boots). **Cutover completed 2026-07-20**: hermes-agent now runs on bali
(state migrated from loom); loom's hermes is gated off via `enableHermes = false` in
`hosts/loom.nix`. Never enable both; the shared tokens double-answer every platform.
bali also took over loom's role as the SOPS bootstrap/editing key (agent-jay-01.yaml is
encrypted to agent-jay-01 + bali). **SSH is tailnet-only** (public 22/2222 closed;
recovery = Hetzner Robot rescue): `ssh bali` (chezmoi ssh config alias) or headless
`ssh -i ~/.ssh/id_ed25519_nopass joost@100.113.194.113`; port 2222 allows password
auth for key-less apps (Codex). Loom (91.99.204.187) is passive and pending decommission. Cancel at
Hetzner when comfortable, then remove `hosts/loom.nix`, its flake entry, sops anchor,
and `secrets/loom.yaml`.

The runners use `modules/github-actions-runner.nix` for CI packages (Docker, languages, build tools, browsers, cloud CLIs) and `services.github-runners` for runner registration. Tokens are SOPS-encrypted in `secrets/github-runner-{01,03,04,05,06}.yaml`. See `docs/github-runner-hetzner-setup.md` for full setup/scaling guide.

**Cloud (CPX/CCX) vs dedicated (EX) hardware:** runner-01 is a Hetzner Cloud VM and imports `modules/hetzner-cloud-hardware.nix` + `modules/disko-hetzner-cloud.nix` (qemu-guest profile, single `/dev/sda`). runner-03 is bare-metal EX63 and imports `modules/hetzner-dedicated-hardware.nix` + `modules/disko-hetzner-dedicated.nix` (no qemu-guest, NVMe initrd, `/dev/nvme0n1`). The second NVMe (`/dev/nvme1n1`) is intentionally left unmanaged so a future host can mount it at `/var/lib/github-runner-work` without rebuilding the root layout.

**EX63 provisioning notes:**
- **SSH access**: rescue mode only ships the SSH key registered at order time (e.g. `j8 mac studio`). Run `make hetzner/provision NIXADDR=<ip> NIXNAME=github-runner-03` from a machine that holds the matching private key, or add an extra pubkey to rescue via Hetzner Robot first.
- **Pre-provision disk prep** (in rescue, before `make hetzner/provision`): EX-series Robot orders sometimes include software RAID superblocks from the installimage step. Wipe both NVMes so disko has a clean canvas: `for d in /dev/nvme0n1 /dev/nvme1n1; do mdadm --stop --scan; mdadm --zero-superblock --force "$d" 2>/dev/null || true; wipefs -af "$d"; done`. Also confirm UEFI boot before proceeding: `[ -d /sys/firmware/efi ] && echo UEFI || echo BIOS`. If BIOS-only, swap `boot.loader.systemd-boot` for `boot.loader.grub` (devices = `[ "/dev/nvme0n1" ]`) before provisioning.
- **Disk-name stability**: the disko module hardcodes `/dev/nvme0n1`. If a particular EX63 enumerates the boot disk as `nvme1n1`, override per-host with `disko.devices.disk.main.device = lib.mkForce "/dev/disk/by-id/nvme-<eui>";`.
- **SOPS re-key after first boot**: the secrets file is initially encrypted to loom's age key. After provisioning succeeds, derive the server's real age key and re-encrypt:
  ```
  ssh-keyscan <ip> 2>/dev/null | grep ed25519 | ssh-to-age
  # replace the &github-runner-03 anchor in .sops.yaml with the printed key
  sops updatekeys secrets/github-runner-03.yaml
  make hetzner/copy NIXADDR=<ip> NIXUSER=joost
  make hetzner/switch NIXADDR=<ip> NIXNAME=github-runner-03 NIXUSER=joost
  ```
- **Token rotation**: the placeholder token in `secrets/github-runner-03.yaml` must be replaced with a fresh org runner registration token from https://github.com/organizations/fuww/settings/actions/runners/new (29-char `AAU5P4...`, expires in 1 hour, single-use). Edit via `sops secrets/github-runner-03.yaml`, then rebuild on the server.

**Runner token type:** The `tokenFile` must contain an **org-level runner registration token** (format: `AAU5P4...`, 29 chars), NOT a GitHub PAT. Get it from https://github.com/organizations/fuww/settings/actions/runners/new → copy the `--token` value. Tokens expire in 1 hour and are single-use.

**SOPS chicken-and-egg for new runners:** New servers don't have SSH host keys until provisioned, but the NixOS build needs an encrypted secrets file. Solution: temporarily use a known age key (e.g., loom's) in `.sops.yaml`, encrypt secrets, provision, then re-key with the server's real age key after provisioning.

**SSH after provisioning:** Root SSH has no authorized keys. Always SSH as `joost@<ip>` and use `sudo`. Run `ssh-keygen -R <ip>` first since the host key changes.

To scale: copy `hosts/github-runner-03.nix`, change hostname/runner name/sops path/instance label, reuse `users/github-runner/`, add flake.nix + `.sops.yaml` entries. New runners use disko + nixos-anywhere (no rescue mode).

**Deployment:** All colleague machines have `nixosAutoUpdate` pulling from `github:javdl/nixos-config#<hostname>` at 4 AM daily. To deploy changes:
1. Edit the relevant `users/<name>/home-manager-server.nix` or `hosts/<hostname>.nix`
2. Commit and push to `main`; machines auto-update on next scheduled check

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

New hosts no longer need a separate `hosts/hardware/<hostname>.nix`. They import the shared `modules/hetzner-cloud-hardware.nix` and `modules/disko-hetzner-cloud.nix` modules directly.

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

One command does all of it: SSH into the server, kexec into a NixOS installer, partition the disk with disko, install NixOS with the full flake config, and reboot.

Expected warnings after first boot:
- `repo-updater` fails (gh not authenticated yet), which is normal
- `tailscaled-autoconnect` fails (no auth key yet), which is normal

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
- The Determinate Nix installer does NOT include `nixos-generate-config` or `nixos-install`. You MUST install `nixos-install-tools` via `nix-env` first
- After sourcing nix-daemon.sh, start the daemon manually: `/nix/var/nix/profiles/default/bin/nix-daemon &`

After bootstrap0, apply full config:

```bash
rsync -av -e 'ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password' \
  --exclude={vendor/,.git/,.git-crypt/,.jj/,.beads/,iso/} \
  /path/to/nixos-config/ root@<ip>:/nix-config

ssh root@<ip> "nixos-rebuild switch --flake /nix-config#<hostname>"
```

</details>

### Agent Dev Boxes (rondo)

Boxes that run autonomous coding agents (currently [rondo](https://github.com/sandsower/rondo), a Claude Code agent that polls Linear and works issues in isolated git-worktree workspaces).

| Server        | Host Config        | Flake Target          | Instance        | User Config         |
|---------------|--------------------|-----------------------|-----------------|---------------------|
| agent-jay-01  | `agent-jay-01`     | `#agent-jay-01`       | CCX33 (reused github-runner-01, TS 100.78.158.57) | `users/agent-jay/` |

Built for reuse: `modules/agent-dev-box.nix` holds the common host config and `users/agent-lib/home-manager.nix` the shared (git-identity-parameterized) home-manager profile, so host and per-agent files are thin. **To add another machine for an agent, or a new agent user, see `docs/agent-dev-box-setup.md`.**

rondo runs in the **deps + manual run** model: NixOS provides the dev box (+ Docker + `mise`); the agent operator installs the runtime via `mise`, runs `claude` /login (OAuth), exports `LINEAR_API_KEY`, and launches rondo by hand. No rondo secrets live in the repo.

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

### Omarchy Quattro/fu137 Machine (Arch Linux)

`fu137` also boots Arch Linux running **Omarchy Quattro** (Arch + Hyprland). It uses standalone Home Manager via `homeConfigurations."fu137"` in `flake.nix`; `j9` and `omarchy` remain compatibility aliases for old commands.

**DO NOT add these packages to the Omarchy Nix config.** They are managed by Omarchy via pacman:
- Desktop stack: `hyprland`, `quickshell`, `uwsm`, `xdg-desktop-portal-hyprland`
- Omarchy CLI/core tools: `gum`, `tldr`, `mpv`, `localsend`, `inxi`, `mise-bin`, `tmux`, `starship`
- Capture tools: `grim`, `slurp`, `gpu-screen-recorder`, `hyprland-preview-share-picker`
- Desktop apps: `foot`, `ghostty`, `chromium`, `obsidian`
- System: PipeWire, SDDM, NVIDIA drivers, fonts (ttf-cascadia-mono-nerd, etc.)

**Omarchy package lists** (authoritative source):
- `/usr/share/omarchy/install/omarchy-base.packages`: Quattro core packages
- `/usr/share/omarchy/install/omarchy-other.packages`: hardware and additional packages

**Protected Quattro configuration** (Home Manager won't generate these files):
- `~/.config/omarchy`: Omarchy branding/themes
- `~/.config/hypr`: Hyprland configuration
- `~/.config/alacritty`, `~/.config/foot`, `~/.config/ghostty`, `~/.config/kitty`: terminal configs
- `~/.config/btop/themes`: btop themes
- Bash, Git, Neovim, Starship, tmux, zoxide, and terminal program modules are disabled in the Omarchy Home Manager profile so Quattro retains ownership.

Only add CLI tools that complement Omarchy without conflicting. `playerctl` is the one remaining supplemental package from the pre-Quattro list.

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
1. **Pre-built binary from GitHub releases** (preferred): `fetchurl` + copy binary (beads, ntm, dcg, caam, etc.)
2. **Pre-built binary from npm registry**: `fetchurl` of platform-specific npm tarball (codex)
3. **Build from source** (last resort): `buildRustPackage` or `overrideAttrs` (cass, gemini-cli)

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

### `~/.claude/settings.json`: hooks need absolute paths
Claude Code performs **literal env-var substitution** on hook commands like `"${PAI_DIR}/hooks/SecurityValidator.hook.ts"`. It does **not** tilde-expand the result. If `PAI_DIR` contains `~/`, hooks silently fail to exec.

The file is therefore a chezmoi template: `~/.local/share/chezmoi/dot_claude/settings.json.tmpl`. All home-rooted env vars use `{{ .chezmoi.homeDir }}` (renders to `/home/joost/...` on Linux, `/Users/joost/...` on macOS). Never put tildes or hardcoded `/home/joost` in the source; edit the `.tmpl` instead. If a chezmoi auto-sync from another machine reintroduces tildes, revert it.

### chezmoi auto-sync races with manual pushes
A background hook auto-syncs `~/.claude/MEMORY` (and observably `~/.claude/settings.json`) to `~/.local/share/chezmoi` every ~5 min and `jj git push`es to `javdl/dotfiles`. Manual pushes regularly hit "stale info" rejections. Standard recovery: `jj git fetch && jj rebase -d main@origin && jj bookmark set main -r @ && jj git push`. Plan for one or two rebase cycles; it's not a bug.

### Bitwarden session handoff for agents

`BW_SESSION` is a bearer secret. Never paste it, a vault item password, or a
PAT into chat, a prompt, a tool argument, shell history, a diff, or logs. When
an agent needs Bitwarden, the human creates a short-lived, owner-only handoff
file in a normal terminal:

```bash
umask 077
bw unlock --raw > /private/tmp/codex-bw-session
chmod 600 /private/tmp/codex-bw-session
```

The agent must verify that the path is a regular, non-symlink file owned by the
current user with mode `600`, load it without echoing it, and check only the
vault state:

```bash
session_file=/private/tmp/codex-bw-session
test -f "$session_file" && test ! -L "$session_file" && test -O "$session_file"
mode="$(stat -f '%Lp' "$session_file" 2>/dev/null || stat -c '%a' "$session_file")"
test "$mode" = 600
session_value="$(<"$session_file")"
BW_SESSION="$session_value" bw status | jq -e '.status == "unlocked"' >/dev/null
```

Use the session only in the same non-echoing command that needs it. Retrieve a
password into a shell variable and pass it through the child process
environment, never on the command line:

```bash
secret_value="$(BW_SESSION="$session_value" bw get password "$item_name")"
GH_TOKEN="$secret_value" gh api user --jq .login
```

Never enable `set -x`, run `env`/`printenv`, use `gh auth status --show-token`,
or emit raw `bw get item` JSON while secrets are loaded. Metadata inspection
must use a fixed `jq` projection that cannot include login passwords, notes, or
hidden fields. Validate secrets with boolean/length checks or an authenticated
read request, not by displaying them.

For GitHub automation, use a dedicated fine-grained PAT limited to the exact
repository and required read-only permissions. The
`codex-github-personal-access-token` item, for example, must target only
`fuww/fashionunited` with `Actions: Read-only` and the mandatory
`Metadata: Read-only`; a classic `repo` PAT is not an acceptable substitute.

After the operation, unset secret variables, delete the exact handoff file,
and report the cleanup:

```bash
unset secret_value session_value BW_SESSION
rm -- /private/tmp/codex-bw-session
test ! -e /private/tmp/codex-bw-session
```

If a session or credential is ever pasted into chat or appears in output,
treat it as compromised: stop, run `bw lock`, rotate the exposed credential
when applicable, and create a fresh handoff file. If the vault is locked or
least privilege cannot be verified, stop rather than falling back to a broader
credential.

### `chezmoi apply` aborts when Bitwarden is locked: fall back to a scoped apply
chezmoi renders **all** templates up front, so one unrenderable template aborts the entire apply. Exactly two source templates call `bitwarden`:

| Source template | Target |
|---|---|
| `dot_claude-code-router/config.json.tmpl` | `~/.claude-code-router/config.json` |
| `private_dot_env.tmpl` | `~/.env` |

With the vault locked (`bw` prints `You are not logged in`) both fail, and everything else, including `~/.claude` (PAI hooks, skills, `settings.json`), silently stays unmanaged. Servers hit the same trap; `d20712c` fixed it for them by re-applying `~/.claude` explicitly after `chezmoi update`.

**Always fall back to a Bitwarden-free scoped apply rather than leaving the sync half-done, and tell the user you did so, since the two secret-backed files are skipped:**
```bash
chezmoi managed --path-style=absolute \
  | awk -F/ 'NF==4' \
  | grep -vxE "$HOME/(\.claude-code-router|\.env)" \
  | xargs chezmoi apply
```
Gotchas, all verified the hard way:
- **Pipe through `xargs`.** zsh does not word-split unquoted parameters, so `chezmoi apply $targets` passes one newline-joined argument and dies with `... : not managed`.
- **`-x/--exclude` takes entry *types*, not paths.** Scoping by target path is the only way to skip specific files.
- **`awk -F/ 'NF==4'`** trims the managed list to top-level entries under `$HOME` (`/home/joost/.claude` → 4 fields), keeping the arg list short while still covering everything.
- **Expect a prompt.** chezmoi asks before overwriting files changed since it last wrote them (typically `~/.claude/MEMORY/STATE/*`); without a TTY it fails with `could not open a new TTY`. Only reach for `--force` after confirming that destination drift is disposable. Live `~/.claude/settings.json` regularly runs *ahead* of the chezmoi source.
- To get the two skipped files too: `bw unlock`, export `BW_SESSION`, then re-run a full `chezmoi apply`.

### zoxide "detected a possible configuration issue" on every Claude Code command
Cosmetic, and **not** a real init-order problem. Do not reshuffle `.zshrc`. The check lives in the generated init script, not the binary:
```zsh
__zoxide_doctor() {
    [[ ${_ZO_DOCTOR:-1} -ne 0 ]] || return 0
    [[ ${chpwd_functions[(Ie)__zoxide_hook]:-} -eq 0 ]] || return 0   # hook present → silent
    ...
}
```
`--cmd cd` makes `cd` a zoxide function that calls `__zoxide_doctor`. Claude Code's shell snapshot (`~/.claude/shell-snapshots/snapshot-zsh-*.sh`) restores functions and aliases but **not** the `chpwd_functions` array, so inside the tool shell `chpwd_functions` is empty and every `cd` warns. Real shells are fine: verified `chpwd_functions=(_direnv_hook __zoxide_hook)` in an interactive zsh, and direnv *prepends* rather than clobbers.

Fix: `_ZO_DOCTOR = "0"` in `home.sessionVariables`, set in `users/shared-home-manager.nix` (desktop/`music` profiles) and repeated in `users/joost/home-manager-server.nix`, which does **not** consume `shared.sessionVariables`. Grep for `shared.sessionVariables` before assuming a shared value reaches a server profile.

### Editing `lib/overlays.nix`: audit siblings before removing
Many overlay blocks are paired infrastructure (e.g., `ironclaw` + `openclaw` were both AI-assistant gateways with matching modules `modules/ironclaw-oci.nix` and `modules/openclaw-oci.nix`, both wired into `hosts/joostclaw.nix`). Before removing a package, grep for related names in the same files and surface them: "I see X is configured alongside Y, should that go too?"

### Loom uses `home-manager-server.nix`, not `home-manager.nix`
`loom` is `server = true` in `flake.nix`, so `lib/mksystem.nix` loads `users/joost/home-manager-server.nix` for it. Edits to `users/joost/home-manager.nix` have **no effect on loom**. Confirm which file a host uses before adding home-manager config for it:
```bash
nix-instantiate --eval --strict -E '
  let f = builtins.getFlake (toString ./.);
  in builtins.attrNames f.nixosConfigurations.<host>.config.home-manager.users.<user>.systemd.user.services'
```

### Plans/ directory hygiene
`Plans/` holds two kinds of files:
- **Auto-generated plan-mode scratchpads** with names like `Plans/now-<slug>.md`: session-internal, gitignored (see `.gitignore`).
- **Intentional plan docs** with descriptive names, such as `Plans/add-hermes-agent.md` and `Plans/simplify-build-from-source-overlays.md`, commit normally.

When staging changes, do not blindly `git add Plans/`. Check the names first.

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
| ntm | `ntm` | Named Tmux Manager: spawn, coordinate, and monitor AI agents across tmux panes |
| bd/br | `bd` / `br` | Beads issue tracker (bd = alias for br, the fast Rust port) |
| bv | `bv` | Beads Viewer TUI: kanban board, DAG visualization, PageRank prioritization |
| caam | `caam` | Instant auth switching for AI coding subscriptions (Claude Max, GPT Pro, Gemini Ultra) |
| cass | `cass` | Index and search AI coding agent session history across all tools |
| cm | `cm` | CASS Memory: procedural cross-agent persistent memory system |
| caut | `caut` | Track and monitor LLM provider usage across AI coding agents (cargo nightly install) |
| dcg | `dcg` | Destructive Command Guard: blocks dangerous git/shell commands from AI agents |
| ubs | `ubs` | Ultimate Bug Scanner: static analysis catching 1000+ bug patterns |
| grepai | `grepai` | Semantic code search for AI coding assistants |
| herdr | `herdr` | Terminal workspace manager/multiplexer with first-class AI-agent awareness |
| am | `am` | Agent Mail: MCP HTTP server for async multi-agent coordination (systemd service) |
| ru | `ru` | Repo Updater: parallel GitHub repo clone/pull sync |

### Installation notes

- Most tools are pre-built binaries installed via Nix overlay (`flake.nix`)
- **caut** is installed via `cargo nightly` activation script (needs sqlite for linking)
- **caam** wrapper translates `--version` flag to `version` subcommand (ntm compatibility)
- **cass** index is rebuilt on each `make switch` via activation script
- **agent-mail** runs as a systemd user service (`systemctl --user status agent-mail`)
- `~/.cargo/bin` is in PATH via `home.sessionPath` for cargo-installed tools

## BitFocus Companion Config Sync

Companion button/macro configs are synced between machines via chezmoi using the `companion-sync` script.

**Workflow (any machine):**
```bash
# After editing Companion buttons/connections:
companion-sync export          # Exports config via Companion API → chezmoi source
cd ~/.local/share/chezmoi
jj describe -m "chore: update Companion config"
jj bookmark set main -r @ && jj git push

# On another machine, to pull updated config:
cd ~/.local/share/chezmoi && jj git fetch && jj rebase -d main
chezmoi apply
companion-sync import          # Guides you through importing into Companion
```

**How it works:**
- `companion-sync export` calls `GET http://localhost:8000/int/export/full?format=json-gz` to save the full config as a `.companionconfig` file (gzipped JSON) into the chezmoi source dir
- `companion-sync import` offers web UI import (recommended) or direct DB replacement
- Import via Companion's web UI handles schema migrations across versions safely
- The config file lives at `~/.config/companion/companion-backup.companionconfig` (managed by chezmoi)
- Companion must be running for export; import via web UI also requires Companion running

**Important:**
- Always export before pushing chezmoi changes if you edited Companion
- The `.companionconfig` format is version-aware, so importing across minor version bumps (e.g., 4.1 → 4.2) works fine
- `machid` (machine identifier) is NOT synced. Each machine keeps its own
- Connection secrets (passwords, API keys) ARE included in the export by default

## Related Tools

- **Beads**: [github.com/steveyegge/beads](https://github.com/steveyegge/beads) - AI-native issue tracking
