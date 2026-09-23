# Overlay release audit — 2026-09-23

Scope: every package definition in `lib/overlays.nix`. Independent release pins were checked against GitHub latest releases, the npm latest tag, or the documented vendor version endpoint. Prereleases were not selected.

| Package | Previous pin | Latest checked | Result |
| --- | --- | --- | --- |
| grepai | 0.36.1 | 0.37.0 | Updated; Linux build and version/help checks pass |
| herdr | 0.9.0 | 0.9.1 | Updated; Linux build and version/help checks pass |
| tailmix | 0.1.12 | 0.1.12 | Already current |
| bv | 0.24.1 | 0.25.0 | Updated; Linux build and version/help checks pass |
| cass | 0.7.1 | 0.8.0 | Updated; Linux build and version/help checks pass |
| slb | 0.4.1 | 0.4.1 | Already current |
| csctf | 0.4.6 | 0.4.6 | Already current |
| brenner | 0.4.1 | 0.4.1 | Already current |
| toon | 0.2.4 | 0.2.4 | Already current |
| ms | 0.2.2 | 0.2.2 | Already current |
| gws | 0.22.5 | 0.22.5 | Already current |
| br | 0.5.11 | 0.6.0 | Updated; Linux build and version/help checks pass |
| ntm | 1.33.0 | 1.35.1 | Updated; Linux build and version/help checks pass |
| dcg | 0.14.1 | 0.14.4 | Updated; Linux build and version/help checks pass |
| caam | 0.1.18 | 0.1.18 | Already current |
| agentBrowser | 0.37.0 | 0.38.1 | Updated; Linux build and version/help checks pass |
| pi | 0.3.0 | 0.5.1 | Retained: Linux release requires unavailable GLIBC 2.43 |
| xf | 0.4.1 | 0.4.1 | Already current |
| mcpAgentMail | 0.3.34 | 0.3.36 | Updated; Linux build and version/help checks pass |
| casr | 0.4.1 | 0.4.1 | Already current |
| s2p | 0.3.4 | 0.3.4 | Already current |
| omp | 18.2.11 | 18.2.11 | Already current |
| pt | 2.1.0 | 2.1.0 | Already current |
| rch | 1.0.64 | 2.0.0 | Updated; Linux build and version/help checks pass |
| ru | 1.3.1 | 1.3.1 | Already current |
| giil | 3.2.1 | 3.2.1 | Already current |
| gemini-cli | 0.58.0 | 0.60.0 | Updated; Linux build and version/help checks pass |
| ubs | 5.3.13 | 5.4.9 | Retained: multi-file packaging excluded by update-overlays skill |
| cm | 0.2.14 | 0.2.14 | Already current |
| cco | 68f92e899738f91a2646674c82c7a44946fcf74d | 26927b88 (HEAD, 2026-09-12) | Retained: source packaging excluded by update-overlays skill |
| grok | 1.0.13 | 1.0.41 | Updated; Linux build and version/help checks pass |
| moshiHook | 0.3.13 | 0.3.27 | Updated; Linux build and version/help checks pass |
| codex | 0.156.1 | 0.156.1 | Already current |

## Other overlay definitions

- `caut` remains disabled (`null`); upstream has no latest release. Enabling it would add a component rather than refresh an existing package.
- `hermes-agent` is supplied by its flake input. `lmstudio`, `gh`, `nushell`, and `google-cloud-sdk` come from the locked unstable nixpkgs input. Their input revisions were not changed in this release-pin update.
- `direnv`, `pipx`, and `github-runner` modify packages supplied by nixpkgs rather than declaring independent versions. Those overrides remain intact.
- Pre-existing changes to `flake.lock` were left outside this commit. The system build used the working-tree lock.

## Verification

- Downloaded and hashed every configured platform asset for each updated release.
- Built all 13 updated x86_64-linux derivations and ran their version and help commands successfully (`grepai version`, other tools `--version`).
- `herdr --version` printed `herdr 0.9.1`; `herdr agent --help` succeeded.
- `make test NIXNAME=bali` passed after retaining the previous Pi pin.
- `git diff --check` passed.
- Other operating systems and architectures were not executed. No running host was activated.

## Follow-ups

[Issue #72](https://github.com/javdl/nixos-config/issues/72) tracks Pi, UBS, and CCO. Pi 0.5.1 was tested from both its tarball and standalone Linux release asset; both require GLIBC 2.43. Stable and unstable inputs currently provide 2.42.

The [update-overlays skill](../skills/update-overlays/SKILL.md) explicitly says of UBS, CM, and CCO: “Do not edit anything for these packages.” CM is already current; UBS and CCO require a separate packaging update.
