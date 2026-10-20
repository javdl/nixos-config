# Workstation Codex and Claude updates

Joost's workstation Home Manager profile imports
[`users/joost/agent-cli-updates.nix`](../users/joost/agent-cli-updates.nix).
This covers fu137, j9, mba, the configured Macs, and Joost's NixOS/WSL
workstation profiles. The legacy `github-runner` output is explicitly excluded;
server and colleague profiles do not import it.

## Ownership and schedule

- Chezmoi owns `~/.config/mise/config.toml`. Its global tools must include
  `codex = "latest"` and `claude = "latest"`.
- Nix owns the updater, launchers, and schedule. Omarchy still provides
  `/usr/bin/mise`; other platforms use the Nix mise package.
- NixOS workstation profiles enable `nix-ld` for upstream dynamically linked
  binaries such as Claude. Omarchy and macOS already provide native loaders.
- Linux runs a user timer at 00:00, 06:00, 12:00, and 18:00, with up to
  15 minutes of jitter and a catch-up after missed runs. macOS runs a launchd
  user agent at login and every six hours while loaded.
- Every Home Manager activation also runs the updater after chezmoi sync.
  It applies the secret-free mise config separately, so a locked Bitwarden
  vault need not block this update. Updater failures warn without failing switch.
- Only Codex and Claude update. Node, Bun, gh, Playwright, and project configs
  are outside this schedule. Releases must be at least 24 hours old.

The command is `mise --cd / install codex@latest claude@latest --yes
--minimum-release-age 24h`. `install` retains old versions and does not rewrite
the global config. This works with the Nix-pinned mise 2026.5.12, whose
`upgrade` command does not yet support `--no-prune`.

## Command selection and failures

The updater takes a nonblocking file lock shared by scheduled and switch runs.
After installation, it checks the actual binaries using `--version` and
`codex exec --help` / `claude auth --help`. Only when both pass does it publish
their resolved, versioned paths under `~/.local/state/agent-cli-update/bin/`.
An install or verification failure leaves those published paths unchanged.

Nix profile commands and `~/.local/bin/{codex,claude}` use these paths, falling
back to the pinned Nix packages before the first successful update. Home Manager
backs up pre-existing local launchers using its normal backup extension. Moshi's
service PATH includes the profile commands. An interactive shell with mise
activation may select mise's binaries directly; these normally match the
published versions, but bypass the publication check after a failed verification.
Explicit project-level mise overrides continue to take precedence in such shells.

Old versions are retained so existing processes and their installation paths
are not removed by this job. It does not restart running agent sessions.
Retained versions consume disk space; cleanup is a separate manual operation.

## Operate and validate

```bash
agent-cli-update
codex --version
claude --version

# Linux
systemctl --user status agent-cli-update.timer
journalctl --user -u agent-cli-update.service -n 50
systemctl --user start agent-cli-update.service

# macOS
launchctl print gui/$(id -u)/org.nix-community.home.agent-cli-update
tail -50 ~/Library/Logs/agent-cli-update.log

# Repository tests
python3 tests/test_agent_cli_update.py
make test NIXNAME=fu137
```

Activate on a workstation with `make switch NIXNAME=<its-flake-name>` after
pulling this repository. Chezmoi must also have the updated global mise source.
An offline workstation receives the automation on its next successful switch;
committing this module alone does not activate a timer on that machine.
