# Radon fleet health probe

Radon writes a read-only health snapshot every 15 minutes so an assistant can
see the personal-tailnet fleet without opening new ports or copying
credentials. The snapshot is a local file. Nothing is pushed off the machine.

This is independent of the compact worker profile in
[PR #79](https://github.com/javdl/nixos-config/pull/79). Do not stack it on
that branch. #79 is behind the Hermes user, Agent volume, and WebUI launch
agent this probe observes, and it already rewrites the top of
`hosts/radon.nix`. The probe is wired from `users/joost/darwin.nix` (enabled
only when the host is radon) so the two diffs do not overlap. Merge either
first. #79's weekly auto-update schedule does not change the log path the
probe tails.

The Hermes plans under `Plans/*hermes*` describe the earlier loom gateway.
Radon's family agent is the WebUI launch agent and the encrypted Agent volume
in `hosts/radon.nix`. This probe only checks that the WebUI port answers and
that the volume is mounted. It does not read Hermes config, env, or anything
under `/Volumes/Agent`.

## What it checks

curl (`/usr/bin/curl`, connect timeout 3s, total 5s, body discarded, no
credentials, `~/.curlrc` ignored):

| Check | Target | ok means |
| --- | --- | --- |
| `spark_ollama` | `http://spark.buri-hoki.ts.net:11434/v1/models` | HTTP 2xx |
| `spark_vllm` | `https://spark.buri-hoki.ts.net:8443/health` | HTTP 2xx |
| `spark2_ollama` | `http://spark2.buri-hoki.ts.net:11434/v1/models` | HTTP 2xx |
| `j9_ollama` | `http://j9.buri-hoki.ts.net:11434/v1/models` | HTTP 2xx |
| `radon_hermes_webui` | `http://127.0.0.1:8787/` | any HTTP status |
| `radon_ollama` | `http://127.0.0.1:11434/v1/models` | HTTP 2xx |
| `aperture` | `https://ai.buri-hoki.ts.net/v1/models` | any HTTP status; the code is recorded and no token is sent |

Local checks, still read-only:

| Check | What is recorded |
| --- | --- |
| `agent_volume` | whether `mount` shows `/Volumes/Agent` |
| `auto_update` | last non-empty line of `/var/log/darwin-auto-update.log`, and `launchctl print` exit code when the user agent can see it |
| `disk` | free bytes on `/` from `df -kP` (`status` and `free_bytes`). `ok` means `df` could be read |

`spark_vllm` is the tailscale-serve health URL. If spark's Ollama port returns
an HTTP status and `:8443` times out, `error` is `not reachable by policy`.
That matches a drop of `tag:hermes` to `spark:8443`. The probe does not edit
Tailscale policy. A connection refused, or a timeout while spark's Ollama port
is also down, stays a normal curl error. An HTTP status from `:8443` means the
port was reachable.

Names are MagicDNS on the personal tailnet `buri-hoki`. The work tailnet
(`stargazer-duck`, bali) is not queried. PAIR context for the `:11434`
endpoints is in [nvpair-omarchy.md](nvpair-omarchy.md).

## Where it runs

`launchd.user.agents.radon-fleet-health` (label
`org.nixos.radon-fleet-health`) in the logged-in user's gui domain. On radon
that user is joost, because FileVault unlock logs joost in at boot. It is not
a LaunchDaemon and it is not the `hermes` user. The script refuses to run as
root or hermes, and it exits without writing if the account is anyone else.

`RunAtLoad` runs one pass when the agent is loaded after
`darwin-rebuild switch`. `StartInterval` is 900 seconds. `KeepAlive` is off.
The job does not restart Hermes, Tailscale, sshd, or the auto-update daemon.

## Output

```text
/Users/joost/.local/state/radon-fleet-health/latest.json
/Users/joost/.local/state/radon-fleet-health/history/YYYY-MM-DD.jsonl
/Users/joost/.local/state/radon-fleet-health/probe.log
/Users/joost/.local/state/radon-fleet-health/.lock
```

`latest.json` is replaced atomically and is the file to read. History keeps
14 days (including today) and then deletes older day files. Directory mode
`0700`, files `0600`, owner joost. `latency` is milliseconds. Aperture's
`status` is the HTTP code only.

The Mac Mini bot already operates radon as joost, so it can read
`latest.json` directly. That is the off-tailnet path: no new listener, no
new credential, no outbound copy.

Not implemented, and not recommended over the local file:

- Pushing the JSON to a repo or gist. That needs a credential on radon and
  writes off the machine.
- Tailscale Funnel or any new HTTP server. That is a new listener.
- Copying the file onto the work tailnet. This probe does not touch it.

## Verify after darwin-rebuild

```sh
make test NIXNAME=radon
make switch NIXNAME=radon

test "$(id -un)" = joost
test -f /Library/LaunchAgents/org.nixos.radon-fleet-health.plist
test ! -f /Library/LaunchDaemons/org.nixos.radon-fleet-health.plist
launchctl print "gui/$(id -u)/org.nixos.radon-fleet-health"
launchctl kickstart "gui/$(id -u)/org.nixos.radon-fleet-health"
python3 -m json.tool /Users/joost/.local/state/radon-fleet-health/latest.json
ls /Users/joost/.local/state/radon-fleet-health/history
```

`make test` evaluates the configuration. `make switch` is the activation, and
it loads this agent; it should not be used to restart the rest of the fleet.
`kickstart` runs one extra probe. Give it a few seconds, then read
`latest.json`. `spark_vllm.error` may be `not reachable by policy` until an
HTTP status comes back; that is a recorded drop, not a failed switch.
