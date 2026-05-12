# Plan: Add hermes-agent to replace ironclaw + openclaw

> **Status:** queued. The teardown of ironclaw and openclaw shipped first (see PR following `replace ironclaw with hermes-agent`). This plan covers the rebuild.

## Context

`ironclaw` (nearai/ironclaw) and `openclaw` (openclaw/nix-openclaw) were both removed from this repo in one commit because we're switching the personal AI assistant stack to **NousResearch/hermes-agent** (Python TUI agent, https://hermes-agent.nousresearch.com). hermes-agent doesn't map cleanly onto the old architecture, so it needs its own design rather than a drop-in overlay swap.

After the teardown PR landed:
- `joostclaw` (Hetzner Cloud server, 91.99.10.155) runs base NixOS + Tailscale + podman + auto-update only — no application stack.
- All ironclaw/openclaw secrets (anthropic key, telegram tokens, gateway tokens, db password) remain encrypted in `secrets/joostclaw.yaml` as inert data. They can be recovered with `sops secrets/joostclaw.yaml` if their credentials are still useful for hermes-agent.

## Decisions still open

| Question | Options | Default if not decided |
|---|---|---|
| Where does hermes-agent run? | (a) joostclaw server, like ironclaw was; (b) per-user on workstations (loom, j7, j8…); (c) both | (a) — keeps joostclaw's existing role as the "remote AI box" |
| Install method | (a) curl install.sh inside a systemd user service; (b) Nix overlay using uv2nix / buildPythonApplication; (c) container (podman) running upstream's Dockerfile | (c) — least Nix coupling, follows the openclaw OCI pattern, easiest to update |
| Which Telegram bot to point at | Reuse the ironclaw or openclaw bot from sops; or register a new one | Reuse to avoid losing chat history |
| LLM backend | Anthropic via existing api key; or Nous Portal; or OpenRouter | Anthropic — secret already exists, no new account |

Ask `joost` to pick before implementing.

## Recommended approach (container on joostclaw)

The hermes-agent repo ships a `Dockerfile`. Easiest path: run it as a podman container managed by a new `services.hermesAgentOci` module that mirrors the structure of the (deleted) `services.openclawOci`.

### Files to create

| Path | Purpose |
|---|---|
| `modules/hermes-agent-oci.nix` | NixOS module: declares `services.hermesAgentOci.instances.<name>` with `enable`, `uid`/`gid`, `subUidStart`/`subGidStart`, ports, secret file paths. Generates a `virtualisation.oci-containers.containers.hermes-agent-<name>` running upstream's image. Model on the deleted `modules/openclaw-oci.nix` (its history is in git for reference). |
| `hosts/joostclaw.nix` (edit) | Re-add the module import, sops secret declarations (renamed `hermes-*`), and the `services.hermesAgentOci.instances.main` block. |
| `secrets/joostclaw.yaml` (edit via `sops`) | Rename the inert `ironclaw-*` / `openclaw-*` entries to `hermes-*` or re-encrypt fresh values. |
| `users/joost/home-manager-joostclaw.nix` (optional edit) | Add a wrapper script that opens an SSH connection to joostclaw and runs `hermes` over it, the way the OpenClaw `openclawGatewayExec` wrapper used to do. |

### Steps

1. **Pick container image source.** Either build it via `nix2container` from the upstream Dockerfile, or pull a published tag. Check `https://github.com/NousResearch/hermes-agent/pkgs/container` for a published image; if there isn't one, build locally:
   ```bash
   git clone https://github.com/NousResearch/hermes-agent.git /tmp/hermes
   cd /tmp/hermes && podman build -t hermes-agent:v2026.5.7 .
   ```

2. **Write `modules/hermes-agent-oci.nix`.** Use the deleted `modules/openclaw-oci.nix` from git history as a template — its `slirp4netns` networking, uid mapping, sops-secret-mounting, and systemd hardening all apply identically. Adjust:
   - Container image reference
   - Environment variables hermes-agent expects (read its docs at https://hermes-agent.nousresearch.com/docs/)
   - Port numbers (default to 3100 if nothing else is using it on joostclaw)
   - Persistent volume path (`/var/lib/hermes-agent/<instance>` for the agent's SQLite memory store)

3. **Wire it into joostclaw:**
   ```nix
   imports = [ ... ../modules/hermes-agent-oci.nix ];

   sops.secrets.hermes-anthropic-api-key = { owner = "hermes-main"; group = "hermes-main"; mode = "0400"; };
   sops.secrets.hermes-telegram-bot-token = { owner = "hermes-main"; group = "hermes-main"; mode = "0400"; };

   services.hermesAgentOci.instances.main = {
     enable = true;
     uid = 3030;
     gid = 3030;
     subUidStart = 130300;
     subGidStart = 130300;
     httpPort = 3100;
     anthropicKeyFile = config.sops.secrets.hermes-anthropic-api-key.path;
     telegramTokenFile = config.sops.secrets.hermes-telegram-bot-token.path;
   };
   ```

4. **Re-encrypt secrets.** Either:
   ```bash
   sops secrets/joostclaw.yaml
   # in the editor: rename ironclaw-anthropic-api-key → hermes-anthropic-api-key,
   #                rename ironclaw-telegram-bot-token → hermes-telegram-bot-token,
   #                delete the rest of the ironclaw-* and openclaw-* entries.
   ```
   Or generate fresh credentials and replace them.

5. **Validate locally:** `nix build .#nixosConfigurations.joostclaw.config.system.build.toplevel`.

6. **Deploy:**
   ```bash
   make hetzner/copy NIXADDR=91.99.10.155 NIXUSER=joost
   make hetzner/switch NIXADDR=91.99.10.155 NIXNAME=joostclaw
   ```
   Or commit, push to main, and wait for the 4 AM `nixosAutoUpdate` to apply.

7. **Smoke-test on joostclaw:**
   - `systemctl status podman-hermes-agent-main.service` — running, no restart loop
   - `curl http://localhost:3100/health` (or whatever endpoint hermes exposes)
   - Send a Telegram message to the bot — it should respond

## Out of scope

- **Renaming `joostclaw`.** The hostname has "claw" in it from the openclaw era. Renaming a host touches many places (flake.nix, sops .sops.yaml, secrets/, auto-update flake target, Tailscale machine name). Leave as `joostclaw` unless explicitly asked to rename.
- **Migrating ironclaw's database.** ironclaw stored data in a `postgres` instance on joostclaw. PostgreSQL was removed in the teardown. The data files on `/var/lib/postgresql/` on the server still exist on disk but are inaccessible. Nothing in hermes-agent needs that data. If the user wants it preserved long-term, take a manual `pg_dump` before this plan executes — once the postgres service is gone for a few weeks the data is effectively abandoned.
- **Per-workstation hermes install.** This plan covers the server install. If the user wants `hermes` available on loom / j7 / j8 as a CLI, that's a separate change: either `home.packages` with a Nix derivation (uv2nix), or just running `curl ... install.sh` manually outside Nix.

## Verification (post-implementation)

1. `nix build .#nixosConfigurations.joostclaw.config.system.build.toplevel` green locally.
2. After deploy: `ssh joost@joostclaw "systemctl status podman-hermes-agent-main"` shows `active (running)`.
3. End-to-end: send a Telegram message to the hermes bot, get a response generated by Anthropic.
4. The hermes-agent built-in skill registry initializes (logs should show a skill catalog being built on first start).
