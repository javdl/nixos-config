# Post-migration follow-ups for hermes-agent on loom

Migration commit: `237ba4a` (on `origin/main`). Service is `active (running)` but with **placeholder secrets**. Three things to do on loom.

---

## 1. Fill in real secrets

`secrets/loom.yaml` currently holds a commented-out template. Until you replace it, hermes runs but can't reach any model provider and won't accept Telegram messages.

**Option A — edit on loom (no admin key needed):**

```bash
ssh loom
cd ~/code/nixos-config   # or wherever you cloned it on loom

# sops on loom can't auto-find the SSH-host-key-derived age key.
# Pass it explicitly:
SOPS_AGE_KEY_FILE=<(sudo ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key) \
  sudo -E sops secrets/loom.yaml
```

Inside the editor, uncomment and fill in:

```
hermes-env: |
  ANTHROPIC_API_KEY=sk-ant-...
  # OR (and/or):
  OPENROUTER_API_KEY=sk-or-...

  TELEGRAM_BOT_TOKEN=...:...
  TELEGRAM_ALLOWED_USERS=<your numeric telegram user id, comma-separated for multiple>

  # Optional auxiliary keys if hermes plugins want them:
  ELEVENLABS_API_KEY=...
  APIFY_TOKEN=...
```

Save & exit; sops re-encrypts on save.

**Option B — recover existing values from joostclaw first:**

The Anthropic key and Telegram bot token used to live encrypted under `secrets/joostclaw.yaml` with the `ironclaw-*` prefix. To extract them:

```bash
ssh joost@joostclaw
cd ~/code/nixos-config
sops -d secrets/joostclaw.yaml | grep -E "^ironclaw-(anthropic-api-key|telegram-bot-token):"
```

Copy the plaintext values, then run Option A on loom.

**After editing:**

```bash
# Push the re-encrypted file
cd ~/code/nixos-config
git add secrets/loom.yaml
git commit -m "hermes-agent: populate real provider + telegram secrets"
git push

# Apply on loom (or wait for 04:00 auto-update — but immediate is better)
sudo nixos-rebuild switch --flake .#loom

# Verify the service picked up the new env
sudo journalctl -u hermes-agent --since "1 minute ago" --no-pager | tail -20

# You should NO LONGER see:
#   "WARNING gateway.run: No user allowlists configured"
#   "WARNING gateway.run: No messaging platforms enabled"
```

Test Telegram: send "hi" to your bot from the whitelisted account → bot replies.

---

## 2. Refresh `hermes` group membership in your shell

The migration added you to the `hermes` group:

```bash
$ getent group hermes
hermes:x:989:joost
```

But your current SSH session was started before that change. To pick it up:

```bash
# Easiest: reconnect
exit
ssh loom

# Or, in the current session:
newgrp hermes
```

After refresh, you can read service state directly without `sudo`:

```bash
ls /var/lib/hermes/.hermes/                # should list config.yaml, kanban.db, skills/, ...
hermes config | head                       # reads /var/lib/hermes/.hermes/ via $HERMES_HOME
hermes                                     # TUI starts; sees your migrated kanban + sessions
```

If `ls` still fails with "Permission denied" after `newgrp hermes`, check `id` — `hermes` should be in the group list.

---

## 3. Useful day-to-day commands

```bash
# Service health
systemctl status hermes-agent
sudo journalctl -u hermes-agent -f                # follow logs live
sudo journalctl -u hermes-agent --since "1h ago" | grep -iE 'error|warn'

# Restart after secret/config change
sudo nixos-rebuild switch --flake .#loom          # if Nix config changed
sudo systemctl restart hermes-agent               # if only secrets/loom.yaml changed
                                                  # (the activation script re-renders .env)

# Where state lives
sudo ls -la /var/lib/hermes/.hermes/              # mode 2770 hermes:hermes
#   config.yaml      ← Nix-managed, do not edit by hand
#   .env             ← Nix-managed, regenerated from sops at activation
#   .managed         ← marker file; presence blocks `hermes setup`/`hermes config edit`
#   state.db         ← migrated from ~/.hermes/state.db
#   kanban.db        ← migrated from ~/.hermes/kanban.db
#   SOUL.md          ← migrated; hermes self-edits this
#   skills/          ← migrated 24 skill dirs
#   sessions/, memories/, cron/, hooks/

# Block: `hermes setup` and `hermes config edit` will refuse — managed mode.
# To change provider/model: edit services.hermes-agent.settings in hosts/loom.nix,
# then nixos-rebuild switch.

# Rollback (only if needed)
git tag                                           # find pre-hermes-migration
git reset --hard pre-hermes-migration && git push --force-with-lease origin main
sudo nixos-rebuild switch --flake github:javdl/nixos-config#loom
#   …and re-install the install.sh shim per Plans/migrate-hermes-to-nix-module.md Rollback section
```

---

## Reference docs in this repo

- `Plans/migrate-hermes-to-nix-module.md` — full 7-phase plan (what was executed)
- `Plans/check-the-plan-for-misty-turtle.md` — audit findings (kept as record)
- `Plans/add-hermes-agent.md` — original install.sh plan (now superseded)
- Upstream docs: <https://hermes-agent.nousresearch.com/docs/getting-started/nix-setup>

## Known gotchas discovered during execution

These were not in the original plan and should be patched in if you re-run the migration on another host:

1. **Rsync trailing slashes spill content.** `rsync -a ~/.hermes/skills/ /var/lib/hermes/.hermes/` copies the *contents* of `skills/` into `.hermes/`, not into `.hermes/skills/`. Use `rsync -a ~/.hermes/skills /var/lib/hermes/.hermes/` (no trailing slash on source) — that places `skills/` as a subdirectory of `.hermes/`.
2. **State-dir mode regression.** The module's `systemd.tmpfiles.rules` sets `/var/lib/hermes/.hermes` to mode `2770` only at activation. After a manual `rsync` + `chown -R`, the directory mode dropped to `700`. Run `sudo chmod 2770 /var/lib/hermes/.hermes` after migration; tmpfiles will keep it consistent across reboots.
3. **`systemctl mask` on a Nix-managed unit fails** ("File '/etc/systemd/system/<unit>' already exists and is a symlink"). Use `systemctl mask --runtime <unit>` instead — creates the mask in `/run/systemd/system/`. Survives until reboot, which is enough for a migration window. The mask was reverted by the `nixos-rebuild switch` activation script restarting the timer, so re-apply after switch if you need it through the state-migration window.
4. **`tag.forceSignAnnotated = true` in git config** means `git tag <name> HEAD` fails with "no tag message?" — use `git tag -a <name> -m "..." HEAD` to create the annotated tag.
5. **Pre-existing `.sops.yaml` had a malformed indent** on the `&joostclaw` line (column 1 vs column 2 for siblings). Newer sops parses this strictly. Migration fixed it; existing encrypted files were not affected (decryption uses age keys, not yaml anchors).
