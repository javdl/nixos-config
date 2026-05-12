# Plan: Install hermes-agent on loom

> **Status:** in progress. Decisions locked: target host = loom (workstation), install method = upstream `install.sh`, credentials = reuse the values currently encrypted under `ironclaw-*` keys in `secrets/joostclaw.yaml`. Steps 1 and the Nix-side systemd unit are **done**; steps 2–4 are the user's manual follow-up.

## Context

We tore out `ironclaw` and `openclaw` from this repo (see commit `0b10c28` and PR #32) because we're switching the personal AI stack to **[NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)**. Initial assumption was that hermes would slot into joostclaw's old container service pattern. Investigation showed:

- **No published container image** for hermes-agent (would mean building a complex multi-stage Dockerfile on-host)
- **No PyPI package** (only GitHub source)
- **No direct `ANTHROPIC_API_KEY` env var path** — providers are configured via interactive `hermes setup` writing to `~/.hermes/config.yaml`
- **Hermes is single-user by design** — it's a personal TUI agent that grows with you, not a multi-tenant gateway

→ Architecture fits a **workstation install** better than a containerized server service. New target: **loom**.

## Decisions

| Question | Decision |
|---|---|
| Target host | **loom** (workstation), not joostclaw |
| Install method | **upstream `install.sh`** — uv + python venv + npm + playwright at `~/.hermes/` |
| Bootstrap | manual on loom (no Nix automation in this phase) |
| Credentials | **reuse** the encrypted `ironclaw-anthropic-api-key` and `ironclaw-telegram-bot-token` values from `secrets/joostclaw.yaml`; transfer them off joostclaw to loom's `~/.env.hermes` |
| Sops setup on loom | **not needed** for this phase. loom is not in `.sops.yaml`; `~/.env.hermes` lives outside Nix |

## What's already in place on loom

✅ `uv` 0.9.30 (via `users/joost/home-manager.nix`)
✅ `node` and `npm` (via home-manager)
✅ `~/.env` pattern is already established (ElevenLabs, Apify, HTTP bearer tokens live there)

No Nix changes are required to start. The bootstrap is entirely upstream-driven.

## Bootstrap steps (run on loom)

1. **Install hermes.** ✅ **DONE** — run as part of this PR:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
     | bash -s -- --skip-setup
   ```
   Installed to:
   - Code:   `~/.hermes/hermes-agent/` (uv venv)
   - Config: `~/.hermes/config.yaml`
   - Env:    `~/.hermes/.env` (template — fill in API keys at step 3)
   - Data:   `~/.hermes/cron/`, `sessions/`, `logs/`
   - Launcher: `~/.local/bin/hermes`

   The Nix-managed systemd unit `hermes-agent-gateway` was added in `users/joost/home-manager-server.nix` (gated `lib.mkIf (isLinux && currentSystemName == "loom")`). After the next `nixos-rebuild switch`, the unit will exist but be disabled until you do step 4.

2. **Recover credentials from joostclaw.** The Anthropic key and Telegram bot token are still in `secrets/joostclaw.yaml`, encrypted to joostclaw's age key. To decrypt, run on joostclaw itself (since loom is not in `.sops.yaml`):
   ```bash
   ssh joost@joostclaw
   cd ~/code/nixos-config   # or wherever the repo is cloned on joostclaw
   sops -d secrets/joostclaw.yaml | grep -E "^ironclaw-(anthropic-api-key|telegram-bot-token):"
   ```
   Copy the two plaintext values back to loom.

3. **Provision env on loom** by editing the hermes-managed file in place:
   ```bash
   $EDITOR ~/.hermes/.env
   ```
   Fill in (uncomment + paste values from step 2):
   - `ANTHROPIC_API_KEY=...`
   - `TELEGRAM_BOT_TOKEN=...`
   - `TELEGRAM_ALLOWED_USERS=<your numeric telegram user id>`

   The file is already a template hermes created at install time — has every provider's variables commented out with docs.

4. **Configure providers + activate the gateway:**
   ```bash
   hermes setup                                             # interactive: pick Anthropic, set model
   make switch NIXNAME=loom                                 # materializes the Nix-managed unit
   systemctl --user daemon-reload
   systemctl --user enable --now hermes-agent-gateway
   systemctl --user status hermes-agent-gateway             # active (running)
   ```

5. **Smoke-test:**
   - `hermes` — TUI starts, responds to "hi"
   - Send a Telegram message to the bot → bot replies
   - `journalctl --user -u hermes-agent-gateway -f` — no errors

## Optional follow-ups (separate PRs)

- **Add hermes to `update-overlays` skill scope.** Once a stable distribution channel exists (PyPI, github release tarball, or container image on GHCR), the skill can bump it automatically. For now hermes self-updates from inside (`hermes update`).
- **Per-workstation expansion.** If you also want hermes on j7 / j8 / fu137, the systemd unit currently has `currentSystemName == "loom"` — widen that guard or move the block into a per-host file. They use `users/joost/home-manager.nix` (not `home-manager-server.nix`), so the unit needs to be duplicated there or factored into a shared module.
- **Clean inert secrets.** The `ironclaw-*` and `openclaw-*` entries still live encrypted in `secrets/joostclaw.yaml`. They're inert (nothing references them in Nix) but bloat the file. To clean, run `sops secrets/joostclaw.yaml` on joostclaw and delete the unused keys.

## Out of scope

- **joostclaw rebuild.** The Hetzner box stays as it is — base NixOS + Tailscale + auto-update only. If we ever want hermes on a remote box again, that's a separate plan.
- **uv2nix / nix-packaging hermes.** Hermes is exact-pinned across ~50 Python deps + npm workspace deps + Playwright browsers. Replicating its uv-lock + Playwright-install behavior in pure Nix is days of work for marginal benefit when `install.sh` already does it correctly.
- **Renaming the `ironclaw-*` sops keys to `hermes-*`.** Only joostclaw can decrypt the file (its age key is the recipient). Renaming requires running `sops` on joostclaw itself. Not worth doing until we actually reference these secrets from Nix again.

## Verification (after bootstrap)

1. `command -v hermes` returns a path under `~/.hermes/` or `~/.local/bin/`.
2. `hermes version` reports `>= 0.13.0`.
3. `hermes` TUI launches and responds to a "hi" prompt.
4. Send a Telegram message to the bot → it replies (this confirms `TELEGRAM_BOT_TOKEN` is correct and the bot is whitelisted to your user).
5. `ls ~/.hermes/sessions/` shows at least one session DB.
