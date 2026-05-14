# Plan: Clone loom's hermes-agent setup to a new Hetzner Cloud host `hermes-fu`

## Context

We've just finished migrating `loom`'s hermes-agent runtime from the install.sh path to the upstream `services.hermes-agent` NixOS module (commits `237ba4a` + follow-ups). That setup now needs to be **replicated to a fresh Hetzner Cloud VM** that will serve as the **company-wide hermes-agent host for FashionUnited**.

The user's directive is explicit: *"no changes to config yet, first just a clone with new naming."* So this plan is a pure copy + new-naming + new-host-infrastructure operation. Hermes-agent settings (model, provider, base_url, `extraDependencyGroups = [ "messaging" ]`) are preserved verbatim. Tuning the deployment for FashionUnited's specific workload (allowlists, different model, Discord/Slack adapters, etc.) is a deliberate later phase.

Locked naming decisions (from clarifying questions just answered):

| Decision | Value |
|---|---|
| Hostname | `hermes-fu` |
| Admin user | `agent` |
| Flake target | `nixosConfigurations.hermes-fu` |
| Auto-update ref | `github:javdl/nixos-config#hermes-fu` |
| Hardware profile | Hetzner Cloud (shared modules, NOT dedicated) |

This plan is scoped to **repository changes only** plus a provisioning runbook. Actual `nixos-anywhere` execution happens in a separate session once the Hetzner Cloud VM is ordered and its IP is known.

---

## File-level plan

### New files

| File | Source template | Required substitutions |
|---|---|---|
| `hosts/hermes-fu.nix` | `hosts/loom.nix` (current commit `bafbc94`) | See **A** below |
| `users/agent/nixos.nix` | `users/desmond/nixos.nix` | See **B** below |
| `users/agent/home-manager-server.nix` | `users/desmond/home-manager-server.nix` | See **C** below |
| `secrets/hermes-fu.yaml` | Created **post-provisioning** (chicken-and-egg) | See **F** below |

### Edited files

| File | Edit |
|---|---|
| `flake.nix` | Add `nixosConfigurations.hermes-fu` entry next to colleague servers (see **D**) |
| `.sops.yaml` | Reserve a slot for `hermes-fu`'s age recipient + creation rule (see **E**) |

### Files **not** touched

- `lib/mksystem.nix` — `inputs` is already in `specialArgs` from the loom migration
- `flake.nix` `inputs` section — `hermes-agent` input already present
- `modules/hetzner-cloud-hardware.nix`, `modules/disko-hetzner-cloud.nix` — reused as-is
- `users/joost/*` — untouched (joost is not the admin of hermes-fu)

---

### A. `hosts/hermes-fu.nix` — what to copy vs change from `hosts/loom.nix`

**Copy verbatim from `hosts/loom.nix`:**
- Module imports: `../modules/cachix.nix`, `../modules/secrets.nix`, `../modules/automatic-nix-gc.nix`, `../modules/nixos-auto-update.nix`, `../modules/security-audit.nix`, `../modules/disk-cleanup.nix`, `../modules/podman.nix`, `../modules/ghostty-terminfo.nix`
- `inputs.hermes-agent.nixosModules.default` import
- The entire `sops.secrets."hermes-env" = { ... }` block (just point `sopsFile = ../secrets/hermes-fu.yaml;`)
- The entire `services.hermes-agent = { ... }` block including `extraDependencyGroups = [ "messaging" ]` and `settings.model = { default = "anthropic/claude-opus-4.6"; ...; }`
- `boot.loader.systemd-boot.enable = true;` + EFI bits
- `nix = { ... }` (experimental-features etc.)
- `services.automaticNixGC = { ... }`
- `services.diskCleanup.enable = true;`
- `services.securityAudit.enable = false;`
- `nixpkgs.config.allowUnfree`
- Firewall base (port 22 only), `services.openssh = { ... }`, `security.sudo.wheelNeedsPassword = false`
- `users.mutableUsers = false`
- `virtualisation.docker` + `virtualisation.podmanConfig`
- The `environment.systemPackages` list (essentials)
- Locale, `programs.zsh.enable`, `programs.nix-ld.enable`
- BBR sysctl + inotify limits + PAM limits
- `services.tailscale = { enable = true; authKeyFile = "/etc/tailscale/authkey"; extraUpFlags = [ "--ssh" "--accept-routes" "--accept-dns=false" ]; }` — **note: drop `--advertise-exit-node`** (loom-specific)
- Tailscale firewall passthrough
- `services.xserver.enable = false; services.printing.enable = false; services.pulseaudio.enable = false; services.nscd.enable = true; services.dbus.enable = true;`
- `system.stateVersion = "25.05"`

**Change from loom:**

| Loom value | New value |
|---|---|
| Top-of-file header: `# Hetzner dedicated server: loom-32gb-nbg1-1\n# IP: 91.99.204.187 / 2a01:4f8:c0c:d0e8::/64` | `# Hetzner Cloud VM: hermes-fu — FashionUnited company-wide hermes-agent host\n# IP: <fill in after order>` |
| `imports = [ ./hardware/loom.nix ... ]` | `imports = [ ../modules/hetzner-cloud-hardware.nix ../modules/disko-hetzner-cloud.nix ... ]` |
| `networking.hostName = "loom";` | `networking.hostName = "hermes-fu";` |
| `services.nixosAutoUpdate.flake = "github:javdl/nixos-config#loom";` | `services.nixosAutoUpdate.flake = "github:javdl/nixos-config#hermes-fu";` |
| `users.users.joost.shell = lib.mkForce pkgs.zsh;` | `users.users.agent.shell = lib.mkForce pkgs.zsh;` |
| `users.users.joost.extraGroups = [ "hermes" ];` | `users.users.agent.extraGroups = [ "hermes" ];` |

**Drop entirely (loom-specific, won't apply to a fresh cloud VM):**
- `services.repoUpdater = { user = "joost"; projectsDir = "/home/joost/code"; ... };` — joost doesn't exist on hermes-fu; this would crash. If the company eventually wants per-user repo sync, add it back later targeting the `agent` user.
- The static IPv6 block `networking.interfaces.enp1s0.ipv6.addresses = [...]` + `networking.defaultGateway6 = {...}` — Hetzner Cloud handles IPv6 via cloud-init/RA, not a static config.

---

### B. `users/agent/nixos.nix` — copy of `users/desmond/nixos.nix`

Replace every `desmond` → `agent` (username, home dir). TODOs the operator fills before provisioning:

| Field | How to fill |
|---|---|
| `users.users.agent.openssh.authorizedKeys.keys` | Paste the SSH public keys of whoever will administer `agent@hermes-fu` |
| `users.users.agent.hashedPassword` | `mkpasswd -m sha-512` on any machine; the resulting hash goes here (won't be used interactively because SSH is key-only, but `users.mutableUsers = false` requires *something*) |

`extraGroups` should be `[ "docker" "wheel" ]` (matches loom and colleagues; `hermes` group is added by `hosts/hermes-fu.nix` to keep host-vs-user concerns separated).

---

### C. `users/agent/home-manager-server.nix` — copy of `users/desmond/home-manager-server.nix`

Replace these three fields (the only personal data in the colleague-server template):

```nix
programs.git = {
  userName = "FashionUnited Agent";       # was "Desmond …"
  userEmail = "<TBD>@fashionunited.com";  # the operator picks
  github.user = "<TBD>";                  # GitHub handle for the box, or leave blank
};
```

Everything else (zellij layouts, shared shell setup, server-shaped home-manager bits) reuses verbatim.

---

### D. `flake.nix` entry

Add this entry adjacent to the colleague servers (after `loom`, before `joostclaw`, alphabetical-ish):

```nix
nixosConfigurations.hermes-fu = mkSystem "hermes-fu" {
  system = "x86_64-linux";
  user   = "agent";
  server = true;
};
```

The `server = true` flag causes `lib/mksystem.nix` to load `users/agent/home-manager-server.nix` (not `home-manager.nix`) — same pattern as loom.

---

### E. `.sops.yaml` edit

Two sub-edits.

**E1.** Reserve an anchor for `hermes-fu`'s age key. At provisioning time we don't have it yet (the VM has no SSH host key until first boot). Two options:

- **Option E1a (recommended): leave a TODO line.** Add:
  ```yaml
    - &hermes-fu age1__TBD__derived_after_provisioning__
  ```
  with a comment marking it as a placeholder. The plan's provisioning runbook (section **G** below) replaces this line once the VM is up.
- **Option E1b: temporarily encrypt to loom.** Per CLAUDE.md's "SOPS chicken-and-egg for new runners" section, you could encrypt the secret to loom's age key for the first nixos-anywhere build and re-key after. Avoided here because it requires keeping a chunk of secrets readable by loom, which we don't want long-term.

**E2.** Add a creation rule that references `&hermes-fu`:

```yaml
  # hermes-fu secrets (hermes-agent env for FashionUnited company-wide host)
  - path_regex: secrets/hermes-fu\.yaml$
    key_groups:
      - age:
          - *hermes-fu
```

The path regex won't match anything until `secrets/hermes-fu.yaml` exists (section **F**), but having the rule pre-staged means `sops secrets/hermes-fu.yaml` Just Works once the recipient is finalized.

---

### F. `secrets/hermes-fu.yaml` — created **after** provisioning

Until the VM exists and its age recipient is known, we can't encrypt to it. Two-step plan:

1. **Before provisioning:** in `hosts/hermes-fu.nix`, **comment out** the `sops.secrets."hermes-env"` block and `services.hermes-agent.environmentFiles` line. Hermes-agent will start with no provider keys (same state loom was in for ~10 minutes during its own migration). Service will be `active (running)` with the same "No adapter / No allowlists" warnings — non-fatal.
2. **After provisioning** (section **G** below): derive the host's age key, populate `.sops.yaml`, create + encrypt `secrets/hermes-fu.yaml` with the same `hermes-env` payload shape as `secrets/loom.yaml`, uncomment the two lines in `hosts/hermes-fu.nix`, commit, and `nixos-rebuild switch` on the new host.

---

## G. Post-creation provisioning runbook

Steps after the repo PR lands (separate session):

```bash
# 1. Order a Hetzner Cloud VM (CCX-class recommended for hermes uv2nix builds)
#    Note the IP. Update hosts/hermes-fu.nix header comment.

# 2. Provision via nixos-anywhere (one-command, no rescue mode needed)
make hetzner/provision NIXADDR=<new-ip> NIXNAME=hermes-fu

# 3. Derive the new host's age key
ssh agent@<new-ip>                    # or root if password still set
sudo ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
#    → age1xxxx...

# 4. Back on a workstation: replace the placeholder in .sops.yaml
#    - &hermes-fu age1__TBD__...   →   - &hermes-fu age1xxxx...

# 5. Create + encrypt secrets/hermes-fu.yaml — mirror secrets/loom.yaml structure
#    (sops creation rule from E2 routes encryption to the new recipient)
sops secrets/hermes-fu.yaml          # editor opens; paste hermes-env: | block

# 6. Uncomment the sops.secrets + environmentFiles lines in hosts/hermes-fu.nix

# 7. Commit + push
git add -p
git commit -m "hermes-fu: enable sops secrets after provisioning"
git push

# 8. Pull on the new host + switch
ssh agent@<new-ip> sudo nixos-rebuild switch --flake github:javdl/nixos-config#hermes-fu

# 9. Tailscale auth
make hetzner/tailscale-auth NIXADDR=<new-ip> TAILSCALE_AUTHKEY=tskey-auth-...
```

This mirrors the established colleague-server runbook (CLAUDE.md "Bootstrap a new colleague server"); only step 5 is hermes-specific.

---

## Verification

**Before merging the PR (Nix code is correct):**

```bash
# Evaluate the new host without provisioning
nix eval .#nixosConfigurations.hermes-fu.config.services.hermes-agent.enable
#   → true

nix eval .#nixosConfigurations.hermes-fu.config.networking.hostName
#   → "hermes-fu"

nix eval --raw .#nixosConfigurations.hermes-fu.config.systemd.services.hermes-agent.serviceConfig.ExecStart 2>/dev/null \
  || nix eval .#nixosConfigurations.hermes-fu.config.systemd.services.hermes-agent.serviceConfig.ExecStart
#   → /nix/store/.../bin/hermes gateway

nix eval .#nixosConfigurations.hermes-fu.config.users.users.agent.extraGroups
#   → [ "hermes" "docker" "wheel" ]   (order may differ)

# Full build (slow first time; no commit yet)
nix build .#nixosConfigurations.hermes-fu.config.system.build.toplevel --no-link
```

**After provisioning (service runs on the new host):**

```bash
ssh agent@<hermes-fu-ip>
systemctl is-active hermes-agent                     # → active
sudo stat -c '%a %U:%G' /var/lib/hermes/.hermes      # → 2770 hermes:hermes
which hermes                                          # → /run/current-system/sw/bin/hermes
echo "$HERMES_HOME"                                   # → /var/lib/hermes/.hermes
sudo journalctl -u hermes-agent --since "2 minutes ago" --no-pager | grep -iE 'error|exception' \
  || echo "no errors"
```

---

## What this plan deliberately leaves out (out of scope)

- **FashionUnited-specific hermes tuning.** Model choice, provider mix, allowlists (`TELEGRAM_ALLOWED_USERS` for a company shared bot — almost certainly different from loom's), MCP servers, declarative SOUL.md / documents. All explicitly punted per user directive.
- **State migration.** Unlike loom, this is a green-field host with no `~/.hermes/` to import. The module's bootstrap creates fresh state directly.
- **High-availability / multi-region.** Out of scope; single VM.
- **Per-user / multi-tenant adapters.** Out of scope; the box runs one hermes gateway with one set of credentials.
- **Tailscale `--advertise-exit-node`.** Loom advertised; hermes-fu won't (likely no need for a company AI server to be an exit node).
- **`services.repoUpdater`.** Dropped — joost's loom-side repos aren't relevant to a company server. Add later if the company wants automated repo sync for `agent`.
- **Removing the audit/migration plan docs.** `Plans/migrate-hermes-to-nix-module.md`, `Plans/post-hermes-migration-followups.md`, and `Plans/add-hermes-agent.md` stay — they're loom history and don't conflict with adding a second hermes host.

---

## Estimated effort

- Repo PR (sections A–E): **30 min** (mostly mechanical copy + grep-replace)
- Verification eval/build: **15 min** (first build pulls uv2nix deps; cachix hits should reduce this)
- Provisioning (section G, separate session, requires VM ordered): **45 min** (nixos-anywhere + tailscale + secrets re-key + switch + verify)

**Total active operator time: ~90 min** spread across two sessions, plus whatever lead time Hetzner takes to provision the VM.
