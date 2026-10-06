# Package refresh — 2026-10-06

All changed release assets were downloaded and hashed for every configured
platform. Claude Code retains the nixpkgs native package and overrides only
its release manifest. No flake inputs were updated.

| Package | Previous | Updated/current | Result |
| --- | --- | --- | --- |
| grepai | 0.37.0 | 0.37.0 | Already current |
| grok | 1.0.41 | 1.0.46 | Linux version/help passed |
| herdr | 0.9.1 | 0.9.3 | Linux version/help passed |
| posthogCli | 0.18.9 | 0.18.9 | Already current |
| moshiHook | 0.4.6 | 0.4.18 | Linux version/help passed |
| tailmix | 0.1.12 | 0.1.12 | Already current |
| bv | 0.25.0 | 0.25.2 | Linux version/help passed |
| cass | 0.9.0 | 0.10.0 | Linux version/help passed |
| slb | 0.5.2 | 0.5.2 | Already current |
| csctf | 0.4.6 | 0.4.6 | Already current |
| brenner | 0.4.1 | 0.4.1 | Already current |
| toon | 0.2.4 | 0.2.5 | Linux version/help passed |
| ms | 0.2.2 | 0.2.3 | Linux version/help passed |
| gws | 0.22.5 | 0.22.5 | Already current |
| br | 0.7.0 | 0.7.4 | Linux version/help passed |
| ntm | 1.35.1 | 1.36.1 | Linux version/help passed |
| dcg | 0.14.4 | 0.15.2 | Linux version/help passed |
| caam | 0.1.18 | 0.1.22 | Linux version/help passed |
| agentBrowser | 0.38.1 | 0.38.2 | Linux version/help passed |
| pi | 0.6.1 | 0.7.1 | Linux version/help passed |
| xf | 0.4.1 | 0.4.2 | Linux version/help passed |
| mcpAgentMail | 0.3.36 | 0.3.37 | Linux version/help passed |
| casr | 0.4.1 | 0.4.1 | Already current |
| s2p | 0.3.4 | 0.3.4 | Already current |
| omp | 18.4.4 | 18.6.1 | Linux version/help passed |
| pt | 2.1.0 | 2.2.1 | Linux version/help passed |
| rch | 2.1.5 | 2.1.16 | Linux version/help passed |
| cua | 0.2.0 | 0.4.1 | Linux version/help passed |
| cuaSpacesd | 0.1.3 | 0.5.3 | Linux version/help passed |
| codex | 0.159.1 | 0.160.1 | Linux version/help passed |
| ru | 1.3.1 | 1.5.0 | Linux version/help passed |
| giil | 3.2.1 | 3.2.1 | Already current |
| gemini-cli | 0.61.0 | 0.62.0 | Linux version/help passed |
| claude-code | 2.1.223 | 2.1.291 | Linux version/help passed |

UBS, CM, and CCO retain their source pins under the exclusions in the
[update-overlays skill](../skills/update-overlays/SKILL.md).
Pi 0.7.1 changed its archive layout to a root-level `pi`; its install path
was updated after checking both Linux and macOS archives.
Cua CLI 0.4.1 pins daemon 0.5.3 in its tagged `libs/cua-spacesd/VERSION`.

## Validation limits

All 24 changed Linux executables passed version and help checks.
Other platforms were downloaded and hashed but not executed.
`make test NIXNAME=bali` selects an unavailable Home Manager output on
fu137. The direct Bali NixOS build first caught the Pi archive layout
change. After that correction, the broad build was stopped at the user's
request to avoid unrelated source builds. No full system build or
activation is claimed.

## Sitegeist

[Sitegeist v1.0.0](https://github.com/badlogic/sitegeist/releases/tag/v1.0.0)
is packaged from the prebuilt extension ZIP. `lib/sitegeist-models.py` limits
its Codex subscription catalog to GPT-6.1 Sol, GPT-6 Sol/Luna/Astra, and
GPT-5.6 Sol/Terra/Luna, as requested on 2026-10-06.
These use the ChatGPT subscription provider, not API keys.
The existing client supports reasoning through xhigh; max/ultra are not
added to its UI. Older Codex models are removed from this catalog.

Both JavaScript bundles pass syntax checks, the exact seven model entries were
verified, and their minimal-to-low reasoning normalization was executed.
No authenticated model request or browser rendering was tested.

On fu137, the extension files are ready at:

```
/home/joost/.local/share/sitegeist
```

Home Manager provides `~/.local/share/sitegeist` on joost's workstation
profiles: fu137, j9, mba, all configured Macs, and NixOS desktops. Server
profiles (including bali) and the legacy github-runner output are excluded.
Other workstations receive the files on their next configuration activation;
they have not been remotely activated as part of this change. On macOS the
path is under `/Users/joost` rather than `/home/joost`.
A local GC root on fu137 keeps its current package available until the next
Home Manager activation.

Browser activation remains manual because no browser-control connection
was available. In Chromium, Chrome, Brave, and Brave Origin separately:

1. Open `chrome://extensions` (or `brave://extensions`).
2. Enable Developer mode, choose **Load unpacked**, and select `~/.local/share/sitegeist` on that machine.
3. In extension details, enable **Allow user scripts** and **Allow access to file URLs**.
4. Open Sitegeist and connect the ChatGPT subscription provider.

See the [upstream installation guide](https://sitegeist.ai/install.html).
The extension is prepared, not confirmed loaded in these browsers.

## DataGrip on fu137 and j9

JetBrains' prebuilt DataGrip 2026.2.6 (build DB-262.10968.148) is installed
under `~/.local/opt/datagrip-2026.2.6` on both machines, with the bundled
JetBrains Runtime. The source download passed the AUR recipe's checksum.
Native package installation required a sudo password, so the verified
vendor archive was installed under the user account instead.

- Executable: `~/.local/bin/datagrip`
- Application launcher: `~/.local/share/applications/jetbrains-datagrip.desktop`
- Version/help, bundled Java, and desktop-entry validation passed on both hosts.
- GUI launch and JetBrains account/license activation were not tested.

DataGrip is user-installed, not Nix- or pacman-managed. No complete
Home Manager activation was needed. j9 was reached at its Tailscale address
100.115.211.110 because the configured DNS alias did not resolve.
