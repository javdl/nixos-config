# Repository index

Start with [AGENTS.md](../AGENTS.md) for operating rules and session completion.
Use the task tables below to load the relevant source and runbook. This index is
a navigation map; configuration files define the implemented behavior, and
runbooks provide procedures and context. Verify older instructions against the
target host and current source before running them.

## Find the configuration that actually applies

1. Find the host in [flake.nix](../flake.nix): `nixosConfigurations`,
   `darwinConfigurations`, or standalone `homeConfigurations`.
2. For NixOS/Darwin, follow [lib/mksystem.nix](../lib/mksystem.nix) into
   [hosts/](../hosts/) and [users/](../users/). Check `server` and `hmConfig`:
   server profiles default to `home-manager-server.nix`.
3. For standalone Omarchy, follow `mkOmarchyHome` in the flake and read the
   [Omarchy ownership rules](../AGENTS.md#omarchy-quattro-machines-arch-linux).
4. Follow imports before editing shared settings; find consumers with
   `rg -n 'settingOrModuleName' flake.nix lib modules users hosts`.

## Configure, build, and deploy

| Task | Start here | Guidance |
| --- | --- | --- |
| Understand system composition | [flake.nix](../flake.nix), [lib/mksystem.nix](../lib/mksystem.nix) | [Architecture](../AGENTS.md#architecture) |
| Add a host or change its services | [hosts/](../hosts/), [modules/](../modules/) | [Adding configurations](../AGENTS.md#adding-configurations) |
| Change user packages or settings | [users/](../users/), [shared settings](../users/shared-home-manager.nix) | Confirm the selected user profile and its imports first |
| Update a package, release binary, or hash | [lib/overlays.nix](../lib/overlays.nix), [flake.lock](../flake.lock) | [Overlay packaging](../AGENTS.md#overlay-packaging-patterns), [update-overlays skill](../skills/update-overlays/SKILL.md) |
| Build or activate a host | [Makefile](../Makefile) | [Build commands](../AGENTS.md#build-commands), [testing workflow](../AGENTS.md#testing-workflow); pass `NIXNAME` explicitly and check the OS branch |
| Provision a colleague server | [hosts/](../hosts/), [shared colleague profile](../users/colleague-lib/home-manager-server.nix) | [Colleague servers](../AGENTS.md#colleague-dev-servers) and the bootstrap procedure under [Build commands](../AGENTS.md#build-commands) |
| Provision, scale, or retire a CI runner | [Runner module](../modules/github-actions-runner.nix), [runner user](../users/github-runner/) | [Setup](github-runner-hetzner-setup.md), [EX63 provisioning](github-runner-03-provisioning.md), [decommissioning](github-runner-decommission.md) |
| Add an autonomous agent box/user | [Agent box module](../modules/agent-dev-box.nix), [shared agent profile](../users/agent-lib/home-manager.nix) | [Agent dev box setup](agent-dev-box-setup.md) |
| Change encrypted secrets or recipients | [SOPS configuration](../.sops.yaml), [secrets module](../modules/secrets.nix) | [Secrets guide](../secrets/README.md), [Bitwarden handoff rules](../AGENTS.md#bitwarden-session-handoff-for-agents) |
| Change automatic system or repository updates | [NixOS updates](../modules/nixos-auto-update.nix), [Darwin updates](../modules/darwin-auto-update.nix), [repo updater](../modules/repo-updater.nix) | Read the module and the target host's settings for schedules and activation behavior |

The Makefile currently rejects a missing `NIXNAME`; the older default-host
description in AGENTS.md is stale. Package overlays currently live in
`lib/overlays.nix`, imported by `flake.nix`; references to an `overlays/`
directory in older guidance do not describe the current layout.

## Agent services, networking, and desktops

| Task | Start here | Guidance |
| --- | --- | --- |
| Install or configure coding-agent CLIs | [Agent CLI module](../users/agent-clis.nix), [overlays](../lib/overlays.nix) | [Tool inventory](../AGENTS.md#ntm-flywheel-tools), [installation notes](../AGENTS.md#installation-notes) |
| Operate or extend the Herdr fleet | [Fleet inventory](../users/herdr-fleet.nix), [node module](../modules/herdr-fleet-node.nix) | [Command center runbook](herdr-command-center.md) |
| Change Hermes gateway deployment | [bali](../hosts/bali.nix), [loom](../hosts/loom.nix), [flake inputs](../flake.nix) | [bali/loom cutover constraints](../AGENTS.md#bali-loom-replacement); distinguish the gateway from the packaged CLI |
| Change Omarchy desktop startup | [Startup module](../users/joost/omarchy-startup.nix) | [Startup ownership](omarchy-startup.md), [Omarchy platform boundaries](../AGENTS.md#omarchy-quattro-machines-arch-linux) |
| Configure a second tailnet | [Shared service definition](../lib/tailmix-service.nix), [NixOS module](../modules/tailmix.nix) | [Tailmix on Omarchy](tailmix-omarchy.md) |
| Configure Companion or sync buttons | [Omarchy Companion module](../users/companion-omarchy.nix) | [fu137 setup](companion-omarchy.md), [Companion sync](../AGENTS.md#bitfocus-companion-config-sync) |
| Diagnose chezmoi synchronization | [Memory sync implementation](../lib/chezmoi-memory-sync.nix) | [Sync races](../AGENTS.md#chezmoi-auto-sync-races-with-manual-pushes), [Common issues](../AGENTS.md#common-issues) for locked-vault scoped apply and hook paths |
| Diagnose shell, package, or platform problems | [Common issues](../AGENTS.md#common-issues) | Includes zoxide, profile selection, package collisions, and macOS migration notes |

## Verification and maintenance

| Need | Source |
| --- | --- |
| Current CI evaluation and build checks | [Flake checker workflow](../.github/workflows/flake-checker.yml), `checks` in [flake.nix](../flake.nix) |
| Performance policy checks | [Policy test](../tests/nix-performance-policy.sh) |
| Automated dependency updates | [Lock updater workflow](../.github/workflows/lock-updater.yml) |
| Review guidance | [Review prompt](../PROMPT_review.md) |
| Commit/push completion rules | [Landing the plane](../AGENTS.md#landing-the-plane-session-completion) |
| Plan storage and staging rules | [Plans hygiene](../AGENTS.md#plans-directory-hygiene) |

## Plans, audits, and historical evidence

These documents capture proposals or observations at a point in time. Their
presence does not establish approval, completion, or current deployed state.

- [Plans/](../Plans/): implementation plans and follow-ups, including
  [repository improvements](../Plans/repo-improvements-2026-07-28.md) and
  [overlay simplification](../Plans/simplify-build-from-source-overlays.md).
- [Nix performance plan](plans/2026-08-30-nix-performance.md) and
  [Nix best-practices audit](nix-best-practices-improvements.md).
- [Security audit (2026-03-06)](security-audit-2026-03-06.md).
- [fu137 inference measurements](fu137-local-inference.md) and
  [round 2 measurements](fu137-local-inference-round2.md).
- [Legacy Hetzner rescue bootstrap](hetzner-devbox-setup.md): consult when
  working on the legacy bootstrap path; compare with current Makefile targets.
- [Historical Hermes bootstrap on loom](hermes-loom-bootstrap.md): migration
  context; read the current bali/loom constraints before using its commands.

When adding a runbook or moving an entry point, update the matching row here.
Keep procedures in their linked documents so there is one place to maintain them.
