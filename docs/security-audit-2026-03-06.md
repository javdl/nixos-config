# Security Audit Report: nixos-config

**Date:** 2026-03-06
**Scope:** Full project audit — all host configs, user configs, modules, secrets, supply chain, and deployment
**Team:** 4 specialized auditors (hosts/firewall, users/privileges, secrets/supply-chain, services/runners) + 7 false-positive filter agents
**Methodology:** Each domain audited independently, findings deduplicated, then filtered through parallel false-positive verification agents. Only findings with confidence >= 8/10 after FP filtering are included.

---

## Critical Attack Chain

Before the individual findings, note the most dangerous attack chain spanning multiple findings:

> **Malicious PR → Runner root → Fleet-wide compromise**
> 1. Attacker submits PR to any `fuww` org repo (Finding 1)
> 2. Workflow runs on self-hosted runner, escalates to root via `sudo` or Docker (Finding 1)
> 3. Uses Tailscale (Findings 6, 7) to reach all other hosts on the tailnet
> 4. OR: Pushes malicious commit to `javdl/nixos-config` (Finding 3)
> 5. Auto-update deploys malicious config as root to all 8+ servers within 24 hours (Finding 3)
> 6. `curl|bash` installs would also execute on next rebuild (Finding 2)

---

## HIGH Severity Findings

### Vuln 1: GitHub Runner Has Root-Equivalent Access (Passwordless Sudo + Docker)

* **Severity:** HIGH | **Confidence:** 10/10 | **Priority:** P0
* **Files:** `users/github-runner/nixos.nix:16`, `hosts/github-runner-01.nix:99`, `hosts/github-runner-02.nix:99,252-255`
* **Description:** The `github-runner` user has `extraGroups = [ "docker" "wheel" ]` and both runner hosts set `security.sudo.wheelNeedsPassword = false`. The runner service also has `DOCKER_HOST = "unix:///var/run/docker.sock"`. This gives any GitHub Actions workflow TWO independent root escalation paths: `sudo su -` and `docker run -v /:/host --privileged`.
* **Exploit Scenario:** A malicious PR to any `fuww` org repo triggers a workflow. The job runs `sudo su -` or `docker run --privileged -v /:/host ubuntu chroot /host` and has full root. The attacker reads SOPS-decrypted secrets, installs backdoors, or pivots via Tailscale.
* **Recommendation:** (1) Remove `wheel` from `github-runner` user. (2) If specific sudo commands are needed, use `security.sudo.extraRules` with command whitelisting. (3) Consider rootless Docker or `--userns-remap` for CI jobs.

---

### Vuln 2: Unverified Remote Code Execution via `curl|bash` on All Servers

* **Severity:** HIGH | **Confidence:** 8/10 | **Priority:** P0
* **Files:** `users/jackson/home-manager-server.nix:101`, `users/desmond/home-manager-server.nix:101`, `users/joost/home-manager.nix:278`, `users/joost/home-manager-server.nix:113`, and 4 more user configs
* **Description:** `curl -fsSL https://claude.ai/install.sh | bash` runs as a home-manager activation script on every user account. This executes during `nixos-rebuild switch`, including during the **unattended daily auto-update at 4 AM**. There is no hash pinning, no version pinning, and no signature verification. Whatever is served at that URL at rebuild time gets executed.
* **Exploit Scenario:** If `claude.ai` is compromised, DNS is poisoned, or a CDN edge is tampered with, arbitrary code executes as each user on every server. The daily 4 AM auto-update provides a recurring attack window without human oversight.
* **Recommendation:** Pin Claude Code to a specific version with a hash, or use a Nix package. The `if [ ! -f ... ]` guard only prevents re-install, not MITM on first install of new servers.

---

### Vuln 3: Auto-Update Pulls Unverified Config from GitHub as Root

* **Severity:** HIGH | **Confidence:** 9/10 | **Priority:** P1
* **Files:** `modules/nixos-auto-update.nix:87-105`, `hosts/github-runner-01.nix:62`, `hosts/github-runner-02.nix:62`, `hosts/desmondroid.nix:61`, and all Hetzner colleague hosts
* **Description:** All servers use `services.nixosAutoUpdate` pulling from `github:javdl/nixos-config#<hostname>` and running `nixos-rebuild switch` as root daily at 4 AM. If the `javdl` GitHub account is compromised, the attacker can push a malicious NixOS config that auto-deploys as root to every server within 24 hours. No commit signing, no branch protection enforcement at the Nix level, no approval gate.
* **Exploit Scenario:** Attacker compromises the `javdl` GitHub account (phishing, session hijack, leaked PAT). Pushes commit adding a reverse shell systemd service. All 8+ servers rebuild with malicious config at 4 AM.
* **Recommendation:** (1) Enable branch protection requiring PR reviews. (2) Consider pinning auto-updates to signed tags. (3) Add a two-phase deploy (build first, manual approval for switch). (4) Consider SSH-authenticated private flake URLs.

---

### Vuln 4: SSH Password Authentication Enabled on Bare-Metal Servers

* **Severity:** HIGH | **Confidence:** 8/10 | **Priority:** P1
* **File:** `hosts/bare-metal-shared-linux.nix:229`
* **Description:** `services.openssh.settings.PasswordAuthentication = true` is set in the shared bare-metal config, imported by `fu137.nix` and `j7.nix`. The Hetzner cloud servers correctly disable password auth. These bare-metal servers may be internet-facing, enabling SSH brute-force attacks.
* **Exploit Scenario:** Attacker brute-forces SSH password for any user account. Combined with `wheel` group membership and passwordless sudo on these hosts, a cracked password yields root.
* **Recommendation:** Set `PasswordAuthentication = false` in `bare-metal-shared-linux.nix`. SSH key-based auth is already configured for all users.

---

### Vuln 5: Plaintext GitHub Runner Tokens on Bare-Metal Hosts

* **Severity:** HIGH | **Confidence:** 9/10 | **Priority:** P1
* **Files:** `hosts/fu137.nix:167`, `hosts/j7.nix:246,252,258`
* **Description:** Runner `tokenFile` points to plaintext files in joost's home directory (`/home/joost/.fuww-github-runner-token`, `/home/joost/.github-runner-token`). Unlike the Hetzner runners which use SOPS encryption, these are unencrypted on disk.
* **Exploit Scenario:** Any process running as `joost` (or root) can read the token. A compromised workflow or rogue package exfiltrates the token, gaining runner registration or API access to the GitHub org.
* **Recommendation:** Migrate to SOPS-encrypted secrets like `github-runner-01/02` use, or at minimum set file permissions to `0400` owned by root.

---

## MEDIUM Severity Findings

### Vuln 6: Tailscale `trustedInterfaces` Bypasses Entire Firewall

* **Severity:** MEDIUM | **Confidence:** 9/10 | **Priority:** P2
* **Files:** `hosts/loom.nix:244`, `hosts/hetzner-dev.nix:253`, all Hetzner colleague hosts, `hosts/github-runner-01.nix`, `hosts/github-runner-02.nix`
* **Description:** Every Hetzner server sets `networking.firewall.trustedInterfaces = [ "tailscale0" ]`, bypassing the NixOS firewall entirely for all Tailscale traffic. Any service on any port is accessible to any tailnet device.
* **Exploit Scenario:** A compromised runner (via Finding 1) uses `tailscale status` to discover all hosts, then accesses every listening port on every server — databases, debug ports, development servers — without firewall filtering.
* **Recommendation:** Replace `trustedInterfaces` with explicit port allowlisting for Tailscale traffic. Use Tailscale ACLs to segment runners from colleague servers.

---

### Vuln 7: Tailscale Exit Node on Runners Enables Lateral Movement

* **Severity:** MEDIUM | **Confidence:** 9/10 | **Priority:** P2
* **Files:** `hosts/github-runner-01.nix:220`, `hosts/github-runner-02.nix:220`
* **Description:** Runner hosts advertise as Tailscale exit nodes (`--advertise-exit-node`). Combined with root access from Finding 1, a compromised runner can route traffic through the tailnet and reach all other hosts.
* **Exploit Scenario:** Attacker gains root on runner, uses Tailscale to pivot to colleague dev servers and admin machines.
* **Recommendation:** Remove `--advertise-exit-node` from runners. CI runners should not be exit nodes. Restrict Tailscale ACLs to prevent runners from reaching colleague servers.

---

### Vuln 8: Git Credentials Stored in Plaintext on All Servers

* **Severity:** MEDIUM | **Confidence:** 9/10 | **Priority:** P2
* **Files:** `users/joost/home-manager.nix:764`, `users/joost/home-manager-server.nix:229`, `users/desmond/home-manager-server.nix:212`, and all colleague home-manager configs
* **Description:** `credential.helper = "store"` saves GitHub tokens as plaintext in `~/.git-credentials` on every user account. On servers where all users have root access (via docker/sudo), any user can read anyone's tokens.
* **Exploit Scenario:** User A escalates to root via Docker, reads `/home/userB/.git-credentials`, obtains their GitHub token for private repo access or code push.
* **Recommendation:** Switch to `credential.helper = "cache --timeout=3600"` (in-memory) or use `gh auth` with scoped fine-grained PATs stored in a keyring.

---

### Vuln 9: No Ephemeral Cleanup Between Runner Jobs

* **Severity:** MEDIUM | **Confidence:** 8/10 | **Priority:** P2
* **Files:** `hosts/github-runner-01.nix:244-256`, `hosts/github-runner-02.nix:244-256`
* **Description:** Runners are persistent services with no cleanup of work directories, Docker images/volumes, or `/tmp` between workflow runs. One job's artifacts and credentials may persist for subsequent jobs.
* **Exploit Scenario:** Workflow A stores AWS credentials during deployment. Workflow B from a different repo reads those leftover credentials.
* **Recommendation:** Add `ExecStopPost` to clean runner work directories and prune Docker artifacts. Consider `ephemeral = true` so each job gets a fresh runner.

---

### Vuln 10: SSH Host Key Verification Disabled in Deployment

* **Severity:** MEDIUM | **Confidence:** 8/10 | **Priority:** P3
* **File:** `Makefile:14,198`
* **Description:** Both `SSH_OPTIONS` and `HETZNER_SSH_OPTIONS` use `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null`. VM SSH options also use `-o PubkeyAuthentication=no` (forcing password auth).
* **Exploit Scenario:** ARP spoofing or DNS poisoning between admin workstation and Hetzner server allows MITM of SSH connection. The entire NixOS config (including SOPS secrets) is sent to the attacker.
* **Recommendation:** After initial bootstrap, add server host keys to `known_hosts` and use normal SSH options for ongoing operations.

---

### Vuln 11: Offensive Security Tools Pre-Installed on Runners

* **Severity:** MEDIUM | **Confidence:** 8/10 | **Priority:** P3
* **File:** `modules/github-actions-runner.nix:112-114`
* **Description:** Runner hosts have `strace`, `tcpdump`, `nmap`, and `netcat-openbsd` installed system-wide, providing a ready-made post-exploitation toolkit.
* **Exploit Scenario:** After gaining root via Finding 1, attacker uses `nmap` for tailnet reconnaissance, `tcpdump` for credential sniffing, and `netcat` for reverse shells — no downloads needed.
* **Recommendation:** Remove `nmap`, `netcat-openbsd`, `strace`, `tcpdump` from default runner packages. Install on-demand via `nix-shell` if specific workflows need them.

---

## Findings Filtered Out (< 8 confidence after FP review)

| Finding | FP Score | Reason Filtered |
|---------|:--------:|----------------|
| Same password hash across all hosts | 2/10 | SSH password auth disabled on affected Hetzner hosts; not exploitable via SSH |
| Unsigned pre-built binaries with hash pinning | 3/10 | SHA-256 hashes pinned at build time provide integrity; design choice |
| No admin recovery key in SOPS | — | Operational risk, not exploitable |
| Placeholder age key for hetzner-dev | — | Deployment failure, not a security exploit |
| Placeholder passwords for colleagues | — | Invalid hash format, cannot authenticate |
| Nix trusted-users includes regular user | — | Standard single-developer practice |
| Ollama/Open-WebUI exposure | 7/10 | Desktop workstation, conditional on Tailscale |

---

## Summary

| # | Severity | Finding | Priority |
|---|----------|---------|:--------:|
| 1 | **HIGH** | Runner user has passwordless sudo + Docker = root | **P0** |
| 2 | **HIGH** | `curl\|bash` on all servers during unattended auto-update | **P0** |
| 3 | **HIGH** | Auto-update from GitHub with no commit verification | **P1** |
| 4 | **HIGH** | SSH password auth on bare-metal servers | **P1** |
| 5 | **HIGH** | Plaintext runner tokens on bare-metal hosts | **P1** |
| 6 | MEDIUM | Tailscale trustedInterfaces bypasses firewall | **P2** |
| 7 | MEDIUM | Tailscale exit node on runners | **P2** |
| 8 | MEDIUM | Git credentials in plaintext on all servers | **P2** |
| 9 | MEDIUM | No ephemeral runner cleanup | **P2** |
| 10 | MEDIUM | SSH host key verification disabled in Makefile | **P3** |
| 11 | MEDIUM | Offensive tools pre-installed on runners | **P3** |

**Overall risk posture:** The most critical risk is the **runner-to-fleet attack chain** (Findings 1→7→6→3). A single malicious PR can escalate from CI job → runner root → tailnet lateral movement → GitHub account compromise → auto-update deployment to all servers. Fixing Finding 1 (removing `wheel` from `github-runner`) breaks the easiest link in this chain.
