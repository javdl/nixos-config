# Family Hermes agent on radon

`hosts/radon/hermes-family.nix` runs a Hermes gateway for the family on Signal,
with the family's cron jobs and three calendar MCP servers (ExecPlan
`hermes-family-mac-mini` in javdl/joost, Milestones 4 to 6). It is off until
`enableHermesFamily` is set in that file. With the gate off, radon's system is
unchanged.

This repository is public. Names, schools, addresses, phone numbers, mail
addresses and calendar ids go in the sops secrets below, never in a file here.
Every value in this README and in `tests/` is made up.

## What runs

| launchd daemon | Job | Log on the Agent volume |
| --- | --- | --- |
| `org.nixos.hermes-gateway` | prepares the state, then `hermes gateway` | `logs/hermes-gateway.log` |
| `org.nixos.hermes-signal-cli` | `signal-cli --config /Volumes/Agent/hermes/signal-cli daemon --http 127.0.0.1:18080 --no-receive-stdout` | `logs/hermes-signal-cli.log` |
| `org.nixos.hermes-run-log` | `scripts/hermes-run-log.py`, every 5 minutes | `logs/hermes-run-log.log` |

Each runs as `hermes` through the Full Disk Access launcher
(`hosts/radon/agent-launcher.nix`), because macOS refuses every other launchd
job access to the Agent volume. A daemon waits up to 120 s until `diskutil`
reports the Agent volume itself mounted at `/Volumes/Agent`, and until
`hermes-pf` has loaded the current `hermes` pf anchor in this boot (it writes
`/var/run/hermes-pf.loaded` after that).
What it prints before then goes to `/var/log/<daemon>.launch.log`. The gateway
starts the MCP servers `gcal-proposals`, `gcal-read` and `gcal-family` itself,
over stdio.

signal-cli runs in multi-account mode: Hermes names the account in every call,
so the daemon needs no account of its own. Its HTTP API has no
authentication, so the `hermes` pf anchor lets only user `hermes` connect to
`127.0.0.1:18080` and drops everyone else's connections. launchd starts
`hermes-pf` and the daemons in no particular order, which is why they wait
for it.

## No Home Manager

System activation, the nightly `darwin-auto-update` included, runs as a
launchd job and cannot write to the volume. So `hermes` has no Home Manager
configuration, and the gateway job does at each start what the upstream Home
Manager activation would do, with the upstream module's own code
(`nix/moduleCommon.nix` in the `hermes-agent` input), plus the family jobs:

1. Wait for the volume, `/Volumes/Agent/hermes` and `/run/secrets/hermes-env`.
2. Create `HERMES_HOME` (`/Volumes/Agent/hermes/.hermes`) and its state
   directories.
3. Merge the Nix settings into `config.yaml`. Nix keys replace the keys on
   disk; keys Hermes wrote at runtime stay.
4. Write `.env` (mode 0600): `SIGNAL_HTTP_URL` from the store, then the
   `hermes-env` secret.
5. Link `/Volumes/Agent/hermes/jobs` to the job scripts in the store.
6. Write `/Volumes/Agent/hermes/state/senders.txt` from `senders` in
   `hermes-family`. Without a valid list, a list of addresses only, there is
   no file, and mail-fetch reads no mail.
7. Run `jobs-sync` (see the job table). If it fails, the log says so and the
   gateway starts anyway.
8. `exec hermes gateway`.

A settings or job change changes the gateway job, so a switch restarts the
gateway, and the restart runs `jobs-sync`. A secret change alone does not;
then run `sudo launchctl kickstart -k system/org.nixos.hermes-gateway`.

`hermes-family` runs the gateway's Hermes as `hermes`, with the gateway's
environment, for checks such as `hermes-family config`,
`hermes-family fallback list` or `hermes-family cron list`.

## Secrets

`secrets/radon.yaml`, encrypted to radon and bali (`.sops.yaml`). Each key is
installed in `/run/secrets/` with owner `hermes` and mode 0400, and each tool
gets only the files it names.

| sops key | Format | Read by |
| --- | --- | --- |
| `hermes-env` | dotenv, below | the gateway, as `.env` |
| `hermes-google-mail` | `{"client_id", "client_secret", "refresh_token"}`, scope `gmail.modify` | `mail-fetch`, `notifier` |
| `hermes-google-proposals` | the same, scope `calendar.events` | MCP server `gcal-proposals` |
| `hermes-google-read` | the same, scope `calendar.readonly` | MCP servers `gcal-read` and `gcal-family`, `pickup` |
| `hermes-family` | JSON object, below | the gateway job, `jobs-sync`, `pickup`, the three MCP servers |

`hermes-env`:

| Key | Format | Example |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | the family's own Anthropic key, for `aperture-claude` | `sk-ant-api03-example` |
| `SIGNAL_ACCOUNT` | the bot's own number, E.164 | `+31600000009` |
| `SIGNAL_ALLOWED_USERS` | who may message the bot: E.164 numbers or Signal UUIDs, comma-separated | `+31600000001,+31600000002` |
| `SIGNAL_GROUP_ALLOWED_USERS` | the groups the bot answers in, by group id, comma-separated; unset means none | `ZXhhbXBsZS1ncm91cC1pZA==` |
| `SIGNAL_HOME_CHANNEL` | where jobs with deliver target `signal` post: the family group as `group:<group id>` | `group:ZXhhbXBsZS1ncm91cC1pZA==` |

In a group the bot answers only when it is mentioned (`signal.require_mention`).

`hermes-family`:

| Key | Format | Example |
| --- | --- | --- |
| `family_calendar_id` | the family Google calendar, shared read-only with the Hermes account | `abc123@group.calendar.google.com` |
| `proposals_calendar_id` | the Hermes account's own Proposals calendar | `def456@group.calendar.google.com` |
| `personal_calendar_id` | optional: Joost's calendar, shared read-only, for the evening brief | `ouder1@example.org` |
| `parents` | exactly two addresses, invited to every proposal | `["ouder1@example.org", "ouder2@example.org"]` |
| `senders` | school and daycare addresses whose mail is read | `["groep5@school.example", "planning@opvang.example"]` |
| `pickup_question` | optional: the pickup question; default `Wie haalt de kinderen vandaag op?` | `Wie haalt Kind A vandaag uit school?` |
| `personal_deliver` | where the evening brief and the digest go: one chat on a messaging platform, `<platform>:<chat>` | `signal:+31600000001` |
| `schedules` | a five-field cron expression per job in the job table, by job name; other keys are ignored | `{"family-pickup": "0 12 * * 1-5", ...}` |

```json
{
  "family_calendar_id": "abc123@group.calendar.google.com",
  "proposals_calendar_id": "def456@group.calendar.google.com",
  "personal_calendar_id": "ouder1@example.org",
  "parents": ["ouder1@example.org", "ouder2@example.org"],
  "senders": ["groep5@school.example", "planning@opvang.example"],
  "pickup_question": "Wie haalt Kind A vandaag uit school, en wie haalt Kind B van de opvang?",
  "personal_deliver": "signal:+31600000001",
  "schedules": {
    "family-pickup": "0 12 * * 1-5",
    "family-mail-parsing": "*/20 8-20 * * *",
    "family-mail-notifier": "10-59/20 8-20 * * *",
    "family-plan-ahead": "30 17 * * 4",
    "family-evening-brief": "30 21 * * *",
    "agent-tooling-digest": "0 10 * * 0"
  }
}
```

## Signal setup

The bot has its own number. Register it before the gate is on, with
`hermes-family-signal-cli` from `hosts/radon.nix`: the same signal-cli and the
same account directory as the daemon.

```bash
hermes-family-signal-cli -a +31600000009 register   # add --captcha <token> if asked
hermes-family-signal-cli -a +31600000009 verify 123-456
hermes-family-signal-cli -a +31600000009 updateProfile --given-name Hermes
```

Add the bot to the family group from a phone. Once the daemon runs, read the
group id from it:

```bash
sudo -u hermes curl -s http://127.0.0.1:18080/api/v1/rpc \
  -d '{"jsonrpc":"2.0","id":1,"method":"listGroups","params":{"account":"+31600000009"}}'
```

While the daemon runs it holds the account. To use `hermes-family-signal-cli`
on that account again, stop the daemon first with
`sudo launchctl bootout system/org.nixos.hermes-signal-cli`, and start it
again with
`sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.hermes-signal-cli.plist`.

## Google setup

1. In Google Cloud Console, under the Hermes Google account, create an OAuth
   client of type Desktop app and download its JSON. Put the consent screen in
   production: in testing mode Google expires refresh tokens after 7 days.
2. On a laptop with a browser, run
   `nix run github:javdl/nixos-config#hermes-family-google-oauth -- mail --client client.json`,
   then `proposals`, then `read`. Sign in as the Hermes account each time. Each
   run prints the JSON for one sops key.
3. Mail reaches the Hermes account through a Gmail filter on the parents'
   mailboxes, which keeps the original `From`. Mail forwarded by hand comes
   from a parent and is not in `senders`.

## Job tools

`packages.nix` is a function `{ pkgs }:` that returns one package per tool.
Each runs from one source tree, which only builds after the unit tests pass on
the build platform.

| Attribute | Command | Runs as |
| --- | --- | --- |
| `mailFetch` | `mail-fetch --credential <hermes-google-mail> --state-dir <state> --hermes-python <Hermes venv>/bin/python3 [--dry-run]` | `--script` of `family-mail-parsing` |
| `notifier` | `notifier --credential <hermes-google-mail> --state-dir <state> --hermes-home <HERMES_HOME> --run-log <runs.jsonl>` | no-agent job `family-mail-notifier` |
| `pickup` | `pickup --credential <hermes-google-read> --family <hermes-family> --run-log <runs.jsonl> [--dry-run] [--date YYYY-MM-DD]` | no-agent job `family-pickup` |
| `planAheadWeather` | `plan-ahead-weather [--today YYYY-MM-DD]` | `--script` of `family-plan-ahead` |
| `gcalMcp` | `gcal-mcp proposals --credential <hermes-google-proposals> --family <hermes-family> --state-dir <state>`, `gcal-mcp read --credential <hermes-google-read> --family <hermes-family>` and `gcal-mcp family --credential <hermes-google-read> --family <hermes-family>` | MCP servers `gcal-proposals`, `gcal-read` and `gcal-family` (stdio) |
| `googleOauth` | `google-oauth {mail,proposals,read} --client <client.json>` | you, once per credential, on a laptop |
| `jobsSync` | `jobs-sync --jobs-dir <hermesHome>/jobs --family <hermes-family> [--dry-run]` | the gateway job, at each start |

`<state>` is `/Volumes/Agent/hermes/state`.

Hermes 81a5543 runs a cron `--script` only if the path, with symlinks followed,
is inside `$HERMES_HOME/scripts/` (`cron/scheduler_script.py:323-366`). A link
into the Nix store fails that check. So `/Volumes/Agent/hermes/jobs/<name>`
runs each tool with its arguments, and `jobs-sync` writes a real two-line
`$HERMES_HOME/scripts/<name>.sh` that `exec`s it.

## Job table

`jobs-sync` owns these six jobs by name. It creates a missing job, edits a
drifted one back, and stops without changes if a name appears twice. A second
run changes nothing. Each job runs on its entry in `schedules` in
`hermes-family`; the family's routines stay out of this public repository.
Before any change, `jobs-sync` refuses a family file whose `schedules` is not
an object or lacks a five-field cron expression for one of these jobs. The
message names the job, never the expression.

| Name | Schedule | Mode | Deliver | Model | `enabled_toolsets` |
| --- | --- | --- | --- | --- | --- |
| `family-pickup` | `schedules` in hermes-family | no-agent, `pickup.sh` | `signal` (family group) | | |
| `family-mail-parsing` | `schedules` in hermes-family | agent, `mail-fetch.sh` injected | `local` | `spark/dsv41` on `aperture-local`, pinned | `gcal-proposals` |
| `family-mail-notifier` | `schedules` in hermes-family | no-agent, `notifier.sh` | `signal` (family group) | | |
| `family-plan-ahead` | `schedules` in hermes-family | agent, `plan-ahead-weather.sh` injected | `signal` (family group) | cron default | `web`, `gcal-family` |
| `family-evening-brief` | `schedules` in hermes-family | agent | `personal_deliver` | cron default | `gcal-read` |
| `agent-tooling-digest` | `schedules` in hermes-family | agent | `personal_deliver` | cron default | `web`, `skills`, `todo`, `no_mcp` |

`gcal-read` lists the family calendar and the personal calendar;
`gcal-family` lists the family calendar alone. The plan-ahead answers in the
family group, so it gets only `gcal-family`.

The evening brief reads the personal calendar, and the digest is Joost's, so
both go to `personal_deliver`, never the family group. `jobs-sync` refuses a
`personal_deliver` that names no single chat on a messaging platform: bare
`signal`, a list with a comma, and `local:`, `origin:` or any platform
outside the cron home-target list of Hermes 81a5543
(`cron/scheduler_delivery.py:41-44`) are refused, whatever follows the colon.

`hermes cron create/edit` cannot set `enabled_toolsets`. `jobs-sync` writes that
one field into `cron/jobs.json` under the store's own lock
(`cron/.jobs.lock`), creates new jobs paused with its own `paused_reason` and
resumes them only after. A job still paused with that reason, because a run
stopped in between, is resumed on the next run. A job paused with any other
reason was paused by hand: `jobs-sync` reports it and leaves it paused.

## Mail flow

1. `mail-fetch` lists inbox mail without a `hermes-*` label. Senders not in
   `senders.txt` get `hermes-ignored`. Mail whose key is in
   `mail-ledger.txt` gets `hermes-processed`. Up to 10 other mails become
   `<mail>` blocks, `Mail-Key:` first; the key is the first 32 hex characters of
   SHA-256 of the raw Message-ID. A mail without a Message-ID gets the same
   hash of a newline, `gmail-id:` and Gmail's message id, which stays the same
   across runs; a trimmed Message-ID never starts with a newline, so the two
   kinds of key cannot meet. A block's body is the mail's `text/plain`
   parts, or its `text/html` parts as text when those are missing or blank. A
   text part whose body Gmail stores as an attachment is fetched with
   `users.messages.attachments.get`. The body is cut at 8 KB. `mail-fetch`
   only reads the lines of `senders.txt` that are an address. When the file
   is missing or has no such line, it lists and labels nothing, so the mail
   is still there once the family secret has a valid sender list.
2. Each block goes through Hermes's own prompt scan,
   `_scan_cron_skill_assembled` in `tools/cronjob_prompt_scan.py`, run with the
   installed Hermes's Python. Hermes runs the same scan on the parsing job's
   prompt and refuses the whole run when it fails
   (`cron/scheduler_prompt.py:378-389`), so one such mail would block all
   school mail. A block the scan rejects is never printed. Its key, sender,
   subject and date go to `quarantine.txt` as one JSON line, its key to
   `mail-ledger.txt`, and the mail gets `hermes-quarantined`. If the scan
   cannot run, `mail-fetch` prints nothing and fails.
3. The other blocks are printed, and their keys go to `fetch-record.jsonl`.
   For a mail whose body was cut, the record also keeps its From, Subject
   and Date, so `notifier` treats it as uncertain (step 6): the model still
   proposes what it read in the first 8 KB, and the family is told to read
   the rest. With nothing to print, Hermes skips the model call.
4. The parsing job numbers the appointments in each mail in mail order and
   calls `create_proposal` once per appointment it can date, with the mail
   key, that number `n`, and a start and end that are RFC 3339 with an offset
   (`2026-11-12T15:30:00+01:00`) or dates (all-day). The tool refuses a call
   without `n`, with a date-time without an offset, or with an offset that is
   not Europe/Amsterdam's on that date. The event id is the first 32 hex
   characters of SHA-256 of `<mail key>|<start>|<n>`, with the start in UTC as
   `YYYY-MM-DDTHH:MM:SSZ`, or `YYYY-MM-DD` for an all-day event. Two
   appointments at the same time in one mail get two events, and a rerun
   that writes the same instant in another form gets 409 and creates nothing.
   A mail that also holds an appointment the model cannot
   date is listed as uncertain.
5. When Google refuses a proposal (other than 409) or does not answer,
   `gcal-mcp` appends the mail key to `proposal-failures.jsonl`.
6. `notifier` reads each new parsing run's answer (located by Hermes's length
   frames, so a JSON block quoted inside a mail is never read), takes the last
   fenced JSON block, ledgers and labels the `processed` keys that
   `fetch-record.jsonl` lists, and prints
   `Kon geen datum vinden: <from>, <subject> (<received>). Kijk de mail even na.`
   for each uncertain mail it ledgered in that pass. A cut mail the model did
   not list as uncertain gets that line from its recorded headers. A key with
   a proposal failure after `mail-fetch` last printed it stays out of the
   ledger, so the next parsing run shows that mail again. So does a key whose
   line has a sender not in `senders.txt` or a received date that does not
   parse, and that key becomes a `failed` row in `runs.jsonl`. A run with an
   answer but no valid block becomes one `failed` row too.
7. For each line `mail-fetch` added to `quarantine.txt` since its last run,
   `notifier` prints
   `Kon de mail niet lezen: <from>, <subject> (<received>). Kijk de mail even na.`
   with the same cleaning: the sender must be in `senders.txt`, and the
   subject loses URLs and control characters and is cut to 80 characters.
   When the date does not parse, the line leaves out ` (<received>)`; a
   sender not in `senders.txt` gets no line but a `failed` row.
   `quarantine-cursor` holds how many lines it has handled.

## Tests

```bash
cd hosts/radon/hermes-family
PYTHONPATH=src python3 -m unittest discover -s tests -t .
```

The calendar MCP tests need the `mcp` package; the Nix build has it. Google
calls go through `hermes_family.net.send`, which the tests replace. The
Open-Meteo and Rijkswaterstaat fixtures are recorded responses. The Gmail and
Calendar fixtures follow the API reference shapes; no live Google response was
recorded.
