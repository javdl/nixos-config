# Coding agents through Tailscale Aperture

Coding agents on the FashionUnited servers send their inference through
Tailscale Aperture (`http://ai.stargazer-duck.ts.net`, node `ai`). Aperture
attributes each request to the caller's tailnet identity, so Claude and Codex
token usage shows up per person in its dashboard and logs
([IT-297](https://linear.app/fuww/issue/IT-297/track-claude-codex-token-usage)).
Aperture passes the user's own Claude or ChatGPT login through, so nobody needs
a shared key. Logging in and refreshing tokens still go to the vendors directly.

## Where it is enabled

[`modules/aperture-agents.nix`](../modules/aperture-agents.nix), option
`services.apertureAgents`:

| Host | `users` (pi/omp files merged) |
| --- | --- |
| desmondroid, jacksonator, peterbot | the colleague (`desmond`, `jackson`, `peter`) |
| agent-jay-01 | `agent-jay`; the `rondo` unit also gets `ANTHROPIC_BASE_URL` |
| joostclaw | `joost` |
| bali, hermes-fu | none: chezmoi owns joost's omp config on bali, and hermes-fu runs no interactive agents |

The workstations (fu137 on stargazer-duck; j9, jmbp16, radon and argon on
buri-hoki) get the same settings from chezmoi in `javdl/dotfiles`, through
`.chezmoitemplates/aperture-url`.

## How each agent is pointed at Aperture

| Agent | Mechanism | Aperture route |
| --- | --- | --- |
| Claude Code | `ANTHROPIC_BASE_URL` (system environment) | `anthropic-sub` |
| omp | `ANTHROPIC_BASE_URL` for Anthropic; `~/.omp/agent/models.yml` `openai-codex.baseUrl` for ChatGPT | both |
| Codex | `/etc/codex/config.toml`: `model_provider = "aperture"`, base URL `…/codex` | `openai-sub` |
| opencode | `OPENCODE_CONFIG` → store JSON with Anthropic `baseURL` `…/v1` | `anthropic-sub` |
| pi | `~/.pi/agent/models.json` `anthropic` and `openai-codex` `baseUrl` | both |
| cursor-agent, grok, gemini | not routed: they use their vendors' own backends | n/a |

Codex reads `/etc/codex/config.toml` before the user's own config. A user's
`~/.codex/config.toml` therefore keeps its model, project trust and MCP servers,
and only inherits the provider. If a user sets `model_provider` themselves, that
user opts out of Aperture.

opencode merges `$OPENCODE_CONFIG` on top of the user's global config. Its
Anthropic client appends `/messages`, which is why it needs the `/v1` suffix.
Claude Code's `ANTHROPIC_BASE_URL` must not carry that suffix.

pi ignores `ANTHROPIC_BASE_URL`, and both pi and omp keep user settings in their
model files, so these files are not replaced. On every switch, a home-manager
activation step (`aperture-agent-config`) sets only the base URLs and leaves
all other keys, comments and the file mode unchanged. It rewrites a file only
when its content changes. It skips a file that is a symlink, and it skips omp
while a legacy `models.json` is still waiting for omp's own migration.

## Model names

Aperture routes only model IDs listed by name in a provider's `models`. An
entry such as `gpt-*` or `claude-*` is a literal ID, not a wildcard, so a model
that is not listed fails with `no route found for model "…"`. When a new model
ships, add its exact ID to `anthropic-sub` or `openai-sub` in the Aperture
configuration (`http://ai.stargazer-duck.ts.net`, admin, Configuration). Glob
patterns belong in `grants`.

## Verify on a host

```bash
echo "$ANTHROPIC_BASE_URL"                     # http://ai.stargazer-duck.ts.net
cat /etc/codex/config.toml                      # model_provider = "aperture"
jq .provider "$OPENCODE_CONFIG"
jq .providers ~/.pi/agent/models.json
cat ~/.omp/agent/models.yml
codex exec --skip-git-repo-check "Reply with exactly: ok"   # header shows provider: aperture
curl -s http://ai.stargazer-duck.ts.net/v1/models | jq -r '.data[].id'
```

The request then appears under the user's identity in the Aperture dashboard.

## Add a host

Import `../modules/aperture-agents.nix` and set
`services.apertureAgents = { enable = true; users = [ "<user>" ]; };`. A
system service that runs an agent does not see `environment.variables`, so
set `ANTHROPIC_BASE_URL=${config.services.apertureAgents.url}` in its unit,
as `hosts/agent-jay-01.nix` does for `rondo`.
