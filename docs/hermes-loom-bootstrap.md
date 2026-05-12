# Finishing hermes-agent bootstrap on loom

Five steps. ~10 minutes if joostclaw is reachable.

## Prerequisites (already done in PR #33)

- `~/.hermes/` populated by `install.sh`
- `~/.local/bin/hermes` launcher on PATH
- Nix-managed systemd unit `hermes-agent-gateway` defined for loom (not yet active — needs step 4)

## Step 1 — Recover credentials from joostclaw

Loom can't decrypt `secrets/joostclaw.yaml` (not a sops recipient). Do this on joostclaw itself:

```bash
ssh joost@joostclaw
cd ~/nixos-config        # or wherever you have it cloned
sops -d secrets/joostclaw.yaml | grep -E "^ironclaw-(anthropic-api-key|telegram-bot-token):"
```

Note the two values (Anthropic key + Telegram bot token). Don't paste them into chat or commit them — they're real credentials.

If you don't have the repo cloned on joostclaw: `git clone https://github.com/javdl/nixos-config ~/nixos-config` first. sops needs the file at a path it knows; the cloned repo's `secrets/joostclaw.yaml` works fine.

## Step 2 — Fill in `~/.hermes/.env` on loom

Hermes already wrote a template at `~/.hermes/.env` (22 KB, every provider commented out). Edit it:

```bash
$EDITOR ~/.hermes/.env
```

Uncomment and fill:

```env
# Native Anthropic provider (not via OpenRouter)
ANTHROPIC_API_KEY=<value from step 1>

# Telegram channel
TELEGRAM_BOT_TOKEN=<value from step 1>
TELEGRAM_ALLOWED_USERS=5654206852    # your numeric Telegram user id
```

(`5654206852` is your existing allowlist — same value `openclaw-work01` and `ironclaw-main` used. Replace if you want a different bot.)

## Step 3 — Configure providers + model

```bash
hermes setup
```

Interactive menu — pick:
- **LLM provider:** Anthropic (it'll auto-detect the key from `~/.hermes/.env`)
- **Default model:** `anthropic/claude-opus-4.6` (or whatever you want)
- **Channels:** enable Telegram

This writes `~/.hermes/config.yaml`. Sanity-check:
```bash
hermes config
```

Optional smoke-test the TUI before going daemon:
```bash
hermes
# > hi
# (Ctrl+D or `/exit` to quit)
```

## Step 4 — Activate the Nix-managed systemd unit

```bash
cd ~/nixos-config
make switch NIXNAME=loom
systemctl --user daemon-reload
systemctl --user enable --now hermes-agent-gateway
```

Verify:
```bash
systemctl --user status hermes-agent-gateway
journalctl --user -u hermes-agent-gateway -f
```

Should show `active (running)` and "telegram channel initialized" (or similar) in the logs. If you see warnings about "No messaging platforms enabled", `hermes setup` step didn't enable Telegram — re-run it.

## Step 5 — Smoke-test end-to-end

Send a message to your Telegram bot from your phone. It should reply.

If it doesn't:
- `journalctl --user -u hermes-agent-gateway --since "5 min ago"` for runtime errors
- Confirm bot is reachable: `curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getMe"` (read the token out of `~/.hermes/.env`)
- Confirm your user ID is in `TELEGRAM_ALLOWED_USERS` — hermes rejects unknown users silently

## Operational commands going forward

| Action | Command |
|---|---|
| Start | `systemctl --user start hermes-agent-gateway` |
| Stop | `systemctl --user stop hermes-agent-gateway` |
| Restart (e.g. after editing `~/.hermes/.env`) | `systemctl --user restart hermes-agent-gateway` |
| Logs (live) | `journalctl --user -u hermes-agent-gateway -f` |
| Logs (today) | `journalctl --user -u hermes-agent-gateway --since today` |
| Status | `systemctl --user status hermes-agent-gateway` |
| Update hermes | `hermes update` (in-place, no Nix involvement) |
| Edit config | `hermes config edit` or directly `$EDITOR ~/.hermes/config.yaml` |
| Edit secrets | `$EDITOR ~/.hermes/.env` then `systemctl --user restart hermes-agent-gateway` |

**Do NOT run `hermes gateway install`** — that creates a second, hermes-managed unit (`hermes-gateway.service`) that fights the Nix-managed one. The Nix unit already runs the same underlying command (`hermes gateway run`).

## Once you're confident it works

Open a separate cleanup PR to remove the now-unused `ironclaw-*` and `openclaw-*` entries from `secrets/joostclaw.yaml`. Run `sops secrets/joostclaw.yaml` on joostclaw itself (loom can't decrypt). Or leave them — they're inert.
