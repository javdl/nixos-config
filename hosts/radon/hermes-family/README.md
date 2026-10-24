# Family Hermes jobs on radon

Scripts and MCP servers for the family Hermes gateway (ExecPlan
`hermes-family-mac-mini`, Milestones 5 and 6). `packages.nix` is a function
`{ pkgs }:` that returns one package per tool. Each package runs from one source
tree, and that tree only builds after the unit tests pass on the build platform.

| Attribute | Command | Runs as |
| --- | --- | --- |
| `mailFetch` | `mail-fetch --credential <hermes-google-mail> --state-dir <state> [--dry-run]` | `--script` of `family-mail-parsing` |
| `notifier` | `notifier --credential <hermes-google-mail> --state-dir <state> --hermes-home <HERMES_HOME> --run-log <runs.jsonl>` | no-agent job `family-mail-notifier` |
| `pickup` | `pickup --credential <hermes-google-read> --family <hermes-family> --run-log <runs.jsonl> [--dry-run] [--date YYYY-MM-DD]` | no-agent job `family-pickup` |
| `planAheadWeather` | `plan-ahead-weather [--today YYYY-MM-DD]` | `--script` of `family-plan-ahead` |
| `gcalMcp` | `gcal-mcp proposals --credential <hermes-google-proposals> --family <hermes-family>` and `gcal-mcp read --credential <hermes-google-read> --family <hermes-family>` | MCP servers `gcal-proposals` and `gcal-read` (stdio) |
| `googleOauth` | `google-oauth {mail,proposals,read} --client <client.json>` | you, once per credential, on a laptop |
| `jobsSync` | `jobs-sync --jobs-dir <hermesHome>/jobs --personal-deliver telegram:<your user id>` | user `hermes`, `HERMES_HOME` set, through `hermes-family-jobs-sync` |

`<state>` is `${hermesHome}/state`. The credential and family files are the sops
secrets in `/run/secrets/`. Each tool gets only the files it names.
`hosts/radon/hermes-family.nix` wires these command lines into the jobs links,
the `gcal-proposals` and `gcal-read` MCP servers, and the system command
`hermes-family-jobs-sync`.

## How a job reaches its script

Hermes 81a5543 runs a cron `--script` only if the path, with symlinks followed,
is inside `$HERMES_HOME/scripts/` (`cron/scheduler_script.py:323-366`). A Home
Manager link into the Nix store fails that check. So the host module links each
job command, with its arguments, to `${hermesHome}/jobs/<name>`
(`mail-fetch`, `notifier`, `pickup`, `plan-ahead-weather`), and `jobs-sync`
writes a real two-line `$HERMES_HOME/scripts/<name>.sh` that `exec`s it.

## One-time setup

1. In Google Cloud Console, under the Hermes Google account, create an OAuth
   client of type Desktop app and download its JSON. Put the consent screen in
   production: in testing mode Google expires refresh tokens after 7 days.
2. Run `google-oauth mail --client client.json`, then `proposals`, then
   `read`. Sign in as the Hermes account each time. Each run prints the JSON for
   one sops key (`hermes-google-mail`, `hermes-google-proposals`,
   `hermes-google-read`).
3. Write `hermes-family` as
   `{"family_calendar_id": ..., "proposals_calendar_id": ..., "personal_calendar_id": ..., "parents": [joost, maartje]}`.
   Leave `personal_calendar_id` out until your personal calendar is shared with
   the Hermes account.
4. Put the school and daycare sender addresses in `${hermesHome}/state/senders.txt`,
   one per line. A missing file allows nobody. The check uses the `From`
   address, so forward with a Gmail filter (which keeps `From`), not by hand.
5. After the first switch, run `hermes-family-jobs-sync --personal-deliver
   telegram:<your user id> --dry-run` and read the plan, then run it without
   `--dry-run`. It runs `jobs-sync` as `hermes` (through `sudo`) with the
   gateway's `HERMES_HOME` and `PATH`. Run it again after every change to the
   job table.

## Job table

`jobs-sync` owns these six jobs by name. It creates a missing job, edits a
drifted one back, and stops without changes if a name appears twice.

| Name | Schedule | Mode | Deliver | Model | `enabled_toolsets` |
| --- | --- | --- | --- | --- | --- |
| `family-pickup` | `0 14 * * 1-5` | no-agent, `pickup.sh` | `telegram` (family group) | | |
| `family-mail-parsing` | `*/15 7-21 * * *` | agent, `mail-fetch.sh` injected | `local` | `spark/dsv41` on `aperture-local`, pinned | `gcal-proposals` |
| `family-mail-notifier` | `5-59/15 7-21 * * *` | no-agent, `notifier.sh` | `telegram` (family group) | | |
| `family-plan-ahead` | `0 16 * * 5` | agent, `plan-ahead-weather.sh` injected | `telegram` (family group) | cron default | `web`, `gcal-read` |
| `family-evening-brief` | `0 20 * * *` | agent | `--personal-deliver` | cron default | `gcal-read` |
| `agent-tooling-digest` | `0 9 * * 6` | agent | `--personal-deliver` | cron default | `web`, `skills`, `todo`, `no_mcp` |

The evening brief reads your personal calendar, and the digest is yours, so both
go to your DM, never the family group by default. `--personal-deliver` is
required and refuses `telegram`, `local` and `origin`. No user id is committed;
pass yours when you run `jobs-sync`.

`hermes cron create/edit` cannot set `enabled_toolsets`. `jobs-sync` writes that
one field into `cron/jobs.json` under the store's own lock
(`cron/.jobs.lock`), creates new jobs paused and resumes them only after.

## Mail flow

1. `mail-fetch` lists inbox mail without a `hermes-*` label. Senders not in
   `senders.txt` get `hermes-ignored`. Mail whose key is in
   `mail-ledger.txt` gets `hermes-processed`. Up to 10 other mails print as
   `<mail>` blocks, `Mail-Key:` first; the key is the first 32 hex characters of
   SHA-256 of the raw Message-ID. The printed keys go to `fetch-record.jsonl`.
   With nothing to print, Hermes skips the model call.
2. The parsing job calls `create_proposal` once per appointment it can date. A
   mail can hold several appointments, so the event id is the first 32 hex
   characters of SHA-256 of `<mail key>|<start>`, with the start as local
   `YYYY-MM-DDTHH:MM`, or `YYYY-MM-DD` for an all-day event. A rerun with the
   same start gets 409 and creates nothing. A mail that also holds an
   appointment the model cannot date is listed as uncertain. The ledger and
   the JSON block keep the mail key.
3. `notifier` reads each new parsing run's answer (located by Hermes's length
   frames, so a JSON block quoted inside a mail is never read), takes the last
   fenced JSON block, ledgers and labels the `processed` keys that
   `fetch-record.jsonl` lists, and prints
   `Could not date: <from>, <subject> (<received>). Please check the mail.` for
   each valid uncertain mail it ledgered in that pass. A run with an answer but
   no valid block becomes one `failed` row in `runs.jsonl`.

## Tests

```bash
cd hosts/radon/hermes-family
PYTHONPATH=src python3 -m unittest discover -s tests -t .
```

Google calls go through `hermes_family.net.send`, which the tests replace.
The Open-Meteo and Rijkswaterstaat fixtures are recorded responses. The Gmail
and Calendar fixtures follow the API reference shapes; no live Google response
was recorded.
