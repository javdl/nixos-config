# Family Hermes agent on radon

`hosts/radon/hermes-family.nix` runs a Hermes gateway for the family on Signal
(ExecPlan `hermes-family-mac-mini` in javdl/joost, Milestones 4 to 6). It is off
until `enableHermesFamily` is set in that file. With the gate off, radon's
system is unchanged.

This repository is public. Names, schools, addresses, phone numbers, mail
addresses and calendar ids go in the sops secrets below, never in a file here.

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
What it prints before then goes to `/var/log/<daemon>.launch.log`.

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
(`nix/moduleCommon.nix` in the `hermes-agent` input):

1. Wait for the volume, `/Volumes/Agent/hermes` and `/run/secrets/hermes-env`.
2. Create `HERMES_HOME` (`/Volumes/Agent/hermes/.hermes`) and its state
   directories.
3. Merge the Nix settings into `config.yaml`. Nix keys replace the keys on
   disk; keys Hermes wrote at runtime stay.
4. Write `.env` (mode 0600): `SIGNAL_HTTP_URL` from the store, then the
   `hermes-env` secret.
5. `exec hermes gateway`.

A settings change changes the job, so a switch restarts the gateway. A secret
change alone does not; then run
`sudo launchctl kickstart -k system/org.nixos.hermes-gateway`.

`hermes-family` runs the gateway's Hermes as `hermes`, with the gateway's
environment, for checks such as `hermes-family config`,
`hermes-family fallback list` or `hermes-family cron list`.

## Secrets

`secrets/radon.yaml`, encrypted to radon and bali (`.sops.yaml`). Each key is
installed in `/run/secrets/` with owner `hermes` and mode 0400.

`hermes-env` is a dotenv file. The values below are made up.

| Key | Format | Example |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | the family's own Anthropic key, for `aperture-claude` | `sk-ant-api03-example` |
| `SIGNAL_ACCOUNT` | the bot's own number, E.164 | `+31600000009` |
| `SIGNAL_ALLOWED_USERS` | who may message the bot: E.164 numbers or Signal UUIDs, comma-separated | `+31600000001,+31600000002` |
| `SIGNAL_GROUP_ALLOWED_USERS` | the groups the bot answers in, by group id, comma-separated; unset means none | `ZXhhbXBsZS1ncm91cC1pZA==` |
| `SIGNAL_HOME_CHANNEL` | where jobs with deliver target `signal` post: the family group as `group:<group id>` | `group:ZXhhbXBsZS1ncm91cC1pZA==` |

In a group the bot answers only when it is mentioned (`signal.require_mention`).

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
