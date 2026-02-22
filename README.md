# NixOS System Configurations

[![Build 🏗️ and Cache ❄️](https://github.com/javdl/nixos-config/actions/workflows/fh.yml/badge.svg)](https://github.com/javdl/nixos-config/actions/workflows/fh.yml)
[![Dependabot Updates](https://github.com/javdl/nixos-config/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/javdl/nixos-config/actions/workflows/dependabot/dependabot-updates)
[![Flake ❄️ Checker ✅](https://github.com/javdl/nixos-config/actions/workflows/flake-checker.yml/badge.svg)](https://github.com/javdl/nixos-config/actions/workflows/flake-checker.yml)
[![Flake ❄️ Lock 🔒️ Updater ✨](https://github.com/javdl/nixos-config/actions/workflows/lock-updater.yml/badge.svg)](https://github.com/javdl/nixos-config/actions/workflows/lock-updater.yml)

This repository contains my NixOS system configurations. This repository
isn't meant to be a turnkey solution to copying my setup or learning Nix,
so I want to apologize to anyone trying to look for something "easy". I've
tried to use very simple Nix practices wherever possible, but if you wish
to copy from this, you'll have to learn the basics of Nix, NixOS, etc.

I don't claim to be an expert at Nix or NixOS, so there are certainly
improvements that could be made! Feel free to suggest them, but please don't
be offended if I don't integrate them, I value having my config work over
having it be optimal.

This is an adaptation of [Mitchell Hashimoto's nixos-config repo](https://github.com/mitchellh/nixos-config)

Some things I have added or changed:

- my own cachix cache
- AMD NVidia support on bare metal host

TODO

- CUDA / CuDNN support on bare metal
- Window manager i3 from the original repo does not seem to work, it uses Gnome by default. Maybe want to set up i3 or Hyprland.

### Manual install

Software that cannot (yet) be installed via Nix or Brew or Mac App Store:

- [DaVinci Resolve Studio](https://www.blackmagicdesign.com/support/family/davinci-resolve-and-fusion)
- [Switch Spotlight hotkey to Raycast](https://manual.raycast.com/hotkey) - Raycast is a must to find GUI apps installed via Nix. Regular spotlight does not find them because it doesn't work with symlinks.
- `skhd --install-service && skhd --start-service`
- [VICREO Listener](https://vicreo-listener.com/downloads) - Receives keystroke commands from Bitfocus Companion (see below)

### Bitfocus Companion

We use [Bitfocus Companion](https://bitfocus.io/companion) to send keystrokes for triggering prompts and other automations. Companion sends keystroke commands over the network to the target machine, where [VICREO Listener](https://vicreo-listener.com/downloads) receives and executes them. It runs as a background service, listens on a local port, and types into whatever app is focused. Works identically on macOS and Linux.

**Setup steps:**

1. Install [VICREO Listener](https://vicreo-listener.com/downloads) manually on each target machine (not available as a Nix package)
2. Install Bitfocus Companion on the controller machine
3. In Companion, add a **Generic - TCP/UDP** connection with host `127.0.0.1`, port `10001`, protocol TCP
4. On your button, add a **Send Command** action with the following JSON:
   ```json
   {"key":"ultrathink","type":"string","password":"d41d8cd98f00b204e9800998ecf8427e"}
   ```
   Change `"key"` to whatever string you want typed. The password is the MD5 hash of an empty string (default). If you set a password in VICREO Listener, MD5 hash that password instead.
5. Companion configs are stored in `users/joost/companion/` in this repo

> **Note:** The dedicated VICREO - Listener module (`vicreo-hotkey`) has no compatible build for macOS aarch64, so we use the Generic TCP/UDP approach instead — it's what that module does under the hood anyway. Works identically on macOS and Linux. Nix paths are exposed to GUI apps via a LaunchAgent in `mac-shared.nix`.

> **Note:** Bitfocus Companion requires Node.js to be installed or accessible in the environment. Without it, certain modules (e.g. Generic - TCP/UDP) will show "no version available" even though a compatible version exists. On NixOS/nix-darwin systems, ensure Companion can access the Nix-managed Node.js — either by installing Node globally or by exposing the Nix environment to the application.

> **Tip:** For button icons (PNG), [Flaticon](https://www.flaticon.com/search?word=github) has a large library of free icons you can use.

> **TODO:** Explore loading Companion configs automatically via Nix (e.g. symlink or activation script into Companion's data directory).

### Bitwarden SSH Agent (macOS)

To use Bitwarden as your SSH agent on macOS:

1. Enable SSH Agent in Bitwarden Desktop app settings
2. Set the socket path for the current session (needed for launchd services):
   ```bash
   export SSH_AUTH_SOCK=$HOME/.bitwarden-ssh-agent.sock

   # alternative
   launchctl setenv SSH_AUTH_SOCK "$HOME/.bitwarden-ssh-agent.sock"

   # test
   ssh-add -L
   ```

The `SSH_AUTH_SOCK` environment variable is already configured in the Nix config for all shells (zsh, bash, fish, nushell).

#### Known Issues
App Store macOS version has socket bugs—use DMG/brew install instead. 

## How I Work

I like to use macOS as the host OS and NixOS within a VM as my primary
development environment. I use the graphical applications on the host
(browser, calendars, mail app, iMessage, etc.) but I do almost everything
dev-related in the VM (editor, compilation, databases, etc.).

Inevitably I get asked **why?** I genuinely like the macOS application
ecosystem, and I'm pretty "locked in" to their various products such as
iMessage. I like the Apple hardware, and I particularly like that my hardware
always Just Works with excellent performance, battery life, and service.
However, I prefer the Linux environment for almost all my dev work. I find
that modern computers are plenty fast enough for the best of both worlds.

Here is what it ends up looking like:

![Screenshot](https://raw.githubusercontent.com/javdl/nixos-config/main/.github/images/screenshot.png)
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fjavdl%2Fnixos-config.svg?type=shield)](https://app.fossa.com/projects/git%2Bgithub.com%2Fjavdl%2Fnixos-config?ref=badge_shield)

Note that I usually full screen the VM so there isn't actually a window,
and I three-finger swipe or use other keyboard shortcuts to active that
window.

### Common Questions Related To This Workflow

**How does web application development work?** I use the VM's IP. Even
though it isn't strictly static, it never changes since I rarely run
other VMs. You just have to make sure software in the VM listens
on `0.0.0.0` so that it isn't only binding to loopback.

**Does copy/paste work?** Yes.

**Do you use shared folders?** I set up a shared folder so I can access
the home directory of my host OS user, but I very rarely use it. I primarily
only use it to access browser downloads. You can see this setup in these
Nix files.

**Do you ever launch graphical applications in the VM?** Sometimes, but rarely.
I'll sometimes do OAuth flows and stuff using FireFox in the VM. Most of the
time, I use the host OS browser.

**Do you have graphical performance issues?** For the types of graphical
applications I run (GUIs, browsers, etc.), not really. VMware (and other
hypervisors) support 3D acceleration on macOS and I get really smooth
rendering because of it.

**This can't actually work! This only works on a powerful workstation!**
I've been doing this since late 2020, and I've developed
[a lot of very real software](https://www.hashicorp.com/). It works for me.
I also use this VM on a MacBook Pro (to be fair, it is maxed out on specs),
and I have no issues whatsoever.

**Does this work with Apple Silicon Macs?** Yes, I use VMware Fusion
but my configurations also work for Parallels and UTM. Folder syncing,
clipboards, and graphics acceleration all work. I've been using an
Apple Silicon Mac full time since Nov 2021 with this setup.

**Does this work on Windows?** Yes, I've tested this setup with both
Hyper-V and VMware Workstation Pro and it works great in either case.

## Setup (VM)

Video: <https://www.youtube.com/watch?v=ubDMLoWz76U>

**Note:** This setup guide will cover VMware Fusion because that is the
hypervisor I use day to day. The configurations in this repository also
work with UTM (see `vm-aarch64-utm`) and Parallels (see `vm-aarch64-prl`) but
I'm not using that full time so they may break from time to time. I've also
successfully set up this environment on Windows with VMware Workstation and
Hyper-V.

You can download the NixOS ISO from the
[official NixOS download page](https://nixos.org/download.html#nixos-iso).
There are ISOs for both `x86_64` and `aarch64` at the time of writing this.

Create a VMware Fusion VM with the following settings. My configurations
are made for VMware Fusion exclusively currently and you will have issues
on other virtualization solutions without minor changes.

- ISO: NixOS 23.05 or later.
- Disk: SATA 150 GB+
- CPU/Memory: I give at least half my cores and half my RAM, as much as you can.
- Graphics: Full acceleration, full resolution, maximum graphics RAM.
- Network: Shared with my Mac.
- Remove sound card, remove video camera, remove printer.
- Profile: Disable almost all keybindings
- Boot Mode: UEFI

Boot the VM, and using the graphical console, change the root password to "root":

```
$ sudo su
$ passwd
# change to root
```

At this point, verify `/dev/sda` exists. This is the expected block device
where the Makefile will install the OS. If you setup your VM to use SATA,
this should exist. If `/dev/nvme` or `/dev/vda` exists instead, you didn't
configure the disk properly. Note, these other block device types work fine,
but you'll have to modify the `bootstrap0` Makefile task to use the proper
block device paths.

Also at this point, I recommend making a snapshot in case anything goes wrong.
I usually call this snapshot "prebootstrap0". This is entirely optional,
but it'll make it super easy to go back and retry if things go wrong.

Run `ifconfig` and get the IP address of the first device. It is probably
`192.168.58.XXX`, but it can be anything. In a terminal with this repository
set this to the `NIXADDR` env var:

```
export NIXADDR=<VM ip address>
```

The Makefile assumes an Intel processor by default. If you are using an
ARM-based processor (M1, etc.), you must change `NIXNAME` so that the ARM-based
configuration is used:

```
export NIXNAME=vm-aarch64
```

**Other Hypervisors:** If you are using Parallels, use `vm-aarch64-prl`.
If you are using UTM, use `vm-aarch64-utm`. Note that the environments aren't
_exactly_ equivalent between hypervisors but they're very close and they
all work.

Perform the initial bootstrap. This will install NixOS on the VM disk image
but will not setup any other configurations yet. This prepares the VM for
any NixOS customization:

```
make vm/bootstrap0
```

After the VM reboots, run the full bootstrap, this will finalize the
NixOS customization using this configuration:

```
make vm/bootstrap
```

You should have a graphical functioning dev VM.

At this point, I never use Mac terminals ever again. I clone this repository
in my VM and I use the other Make tasks such as `make test`, `make switch`, etc.
to make changes my VM.

If there is repos cloned to the host system, this will copy all from `~/git` folder to the VM.

```
make vm/copyrepos
```

## Setup (macOS/Darwin)

**THIS IS OPTIONAL AND UNRELATED TO THE VM WORK.** I recommend you ignore
this unless you're interested in using Nix to manage your Mac too.

I share some of my Nix configurations with my Mac host and use Nix
to manage _some_ aspects of my macOS installation, too. This uses the
[nix-darwin](https://github.com/LnL7/nix-darwin) project. I don't manage
_everything_ with Nix, for example I don't manage apps, some of my system
settings, Homebrew, etc. I plan to migrate some of those in time.

To utilize the Mac setup, first install Nix using some Nix installer.
There are two great installers right now:
[nix-installer](https://github.com/DeterminateSystems/nix-installer)
by Determinate Systems and [Flox](https://floxdev.com/). The point of both
for my configs is just to get the `nix` CLI with flake support installed.

Once installed, clone this repo and run `make`. If there are any errors,
follow the error message (some folders may need permissions changed,
some files may need to be deleted). That's it.

**WARNING: Don't do this without reading the source.** This repository
is and always has been _my_ configurations. If you blindly run this,
your system may be changed in ways that you don't want. Read my source!

### Quick start (MacOS/Darwin) bare metal

Install Nix with the Nix installer from Determinate Systems:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --determinate
```

Clone this repo and run `make switch`, replace the NIXNAME with the configuration name you want to use:

If you get errors: "ignoring untrusted substituter 'https://javdl-nixos-config.cachix.org', you are not a trusted user."
make sure to run `make` before running `make switch` to add the cachix cache.

### Login to use FlakeHub Cache

```bash
determinate-nixd login
```

**Initial setup.**

```bash
cd ~
git clone https://github.com/javdl/nixos-config.git
cd nixos-config
mkdir -p ~/.config/nix/
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
```

**Run it.**

```bash
export NIXNAME=mac-studio-m1
sudo nixos-rebuild switch --flake ".#${NIXNAME}" # See also the Makefile. We
# cannot use make switch however since it is not yet installed.
```

**Updates / changes** after the first install.

```bash
export NIXNAME=mac-studio-m1
make switch
```

### Brew

Brew casks can be configured in `/users/joost/darwin.nix`

## Setup (NixOS) bare metal

**The below is partially tested**, it might need (tiny) changes.

- Create install USB with latest NixOS
- For systems with Nvidia GPU, choose `nomodeset` option for the installer
- After install finished:
- `sudo nano /etc/nixos/configuration.nix` and add `nix.settings.experimental-features = [ "nix-command" "flakes" ];`
- `sudo nixos-rebuild switch`
- `nix-shell -p git gnumake`
- `git clone https://github.com/javdl/nixos-config.git`
- `cp /etc/nixos/configuration.nix ~/nixos-config/hosts/HOSTNAME.nix` and
  `cp /etc/nixos/hardware-configuration.nix ~/nixos-config/hosts/hardware/HOSTNAME.nix`
- Edit the copied `configuration.nix` to make the include correct to `hardware/HOSTNAME.nix` folder
- Edit `~/nixos-config/flake.nix` to add an entry for the new host.
- `git add .` to add the newly created files to git. Files must be in git for Nix to work with them. Commiting them is not necessary though.

```bash
export NIXNAME=HOSTNAME
make switch
# Or
sudo nixos-rebuild switch --flake ".#${NIXNAME}" # same command as in Makefile
# Example with host J7
cd ~/nixos-config && export NIXPKGS_ALLOW_INSECURE=1 && sudo nixos-rebuild switch --flake ".#j7"
```

- Copy the GPG key and SSH key onto the machine from an existing one (only the keys are needed, not other files in the `~/.ssh` or `~/.gnupg` folder) `cp /run/media/joost/usbdrive/id_ed25519 /home/joost/.ssh/`
- The GPG `.asc` file can also be downloaded from secure storage and then imported. `gpg --import Joost_secret_key.asc` for both public and private keys.
- Before the GPG key works with git, you might need to do a `gpgconf --kill gpg-agent` before it will pick up the new settings. (I've got a `signing failed: no pinentry` error.
- Before the SSH key works you need to set permissions `chmod 600 ~/.ssh/id_ed25519`
- Commit the changes and publish to git with the new host added.
  `git remote set-url origin git@github.com:javdl/nixos-config.git`
  and `git add . && git commit -m "add HOSTNAME" && git push`
- On subsequent changes, you can use `make switch` instead of the nixos-rebuild command.

## Setup (WSL)

**THIS IS OPTIONAL AND UNRELATED TO THE VM WORK.** I recommend you ignore
this unless you're interested in using Nix to manage your WSL
(Windows Subsystem for Linux) environment, too.

I use Nix to build a WSL root tarball for Windows. I then have my entire
Nix environment on Windows in WSL too, which I use to for example run
Neovim amongst other things. My general workflow is that I only modify
my WSL environment outside of WSL, rebuild my root filesystem, and
recreate the WSL distribution each time there are system changes. My system
changes are rare enough that this is not annoying at all.

To create a WSL root tarball, you must be running on a Linux machine
that is able to build `x86_64` binaries (either directly or cross-compiling).
My `aarch64` VMs are all properly configured to cross-compile to `x86_64`
so if you're using my NixOS configurations you're already good to go.

Run `make wsl`. This will take some time but will ultimately output
a tarball in `./result/tarball`. Copy that to your Windows machine.
Once it is copied over, run the following steps on Windows:

```
$ wsl --import nixos .\nixos .\path\to\tarball.tar.gz
...

$ wsl -d nixos
...

# Optionally, make it the default
$ wsl -s nixos
```

After the `wsl -d` command, you should be dropped into the Nix environment.
_Voila!_

## Hetzner Dev Servers

Colleague development servers (Hetzner CPX32, Nuremberg):

| Colleague | Hostname       | Flake Target     | User Config                             |
|-----------|----------------|------------------|-----------------------------------------|
| Desmond   | desmondroid    | `#desmondroid`   | `users/desmond/home-manager-server.nix` |
| Jackson   | jacksonator    | `#jacksonator`   | `users/jackson/home-manager-server.nix` |
| Jeevan    | jeevanator     | `#jeevanator`    | `users/jeevan/home-manager-server.nix`  |
| Peter     | peterbot       | `#peterbot`      | `users/peter/home-manager-server.nix`   |
| Rajesh    | rajbot         | `#rajbot`        | `users/rajesh/home-manager-server.nix`  |

All servers auto-update from `main` at 4 AM UTC daily via the `nixosAutoUpdate` module.

### Making changes to your own server

You can customise your dev server by editing your config and rebuilding. Here's how (using Jackson / `jacksonator` as an example — substitute your own name and hostname):

**1. Clone the repo on your server:**

```bash
git clone https://github.com/javdl/nixos-config.git ~/nixos-config
cd ~/nixos-config
```

**2. Edit your config:**

Your personal config lives in `users/jackson/home-manager-server.nix`. This controls your shell, git settings, tmux, installed packages, and more.

```bash
# Open your config in your preferred editor
nano users/jackson/home-manager-server.nix
```

Common things you might want to change:
- **Add packages**: find the `home.packages` list and add entries like `pkgs.htop` or `pkgs.nodejs`
- **Git config**: update `programs.git.userName`, `userEmail`, or `github.user`
- **Shell aliases**: add aliases in the zsh or bash configuration section
- **Tmux settings**: change prefix key, mouse mode, etc. under `programs.tmux`

The host-level config (networking, system services, etc.) is in `hosts/jacksonator.nix` — you probably don't need to touch this.

**3. Apply your changes:**

```bash
# Test first (builds without activating)
sudo nixos-rebuild test --flake ".#jacksonator"

# If that works, apply for real
sudo nixos-rebuild switch --flake ".#jacksonator"
```

**4. (Optional) Contribute your changes back:**

If you want your changes to persist across auto-updates, push them to the repo:

```bash
cd ~/nixos-config
git add users/jackson/home-manager-server.nix
git commit -m "jackson: add nodejs to packages"
git push
```

If you don't push, your local changes will be overwritten on the next auto-update at 4 AM.

### Finding packages

```bash
# Search for a package
nix search nixpkgs python

# Check what's already installed
grep "pkgs\." users/jackson/home-manager-server.nix
```

## Zellij Work Layout

The dev servers have a zellij work layout pre-configured at `~/.config/zellij/layouts/work.kdl`. You can use it in two ways:

**On the server (SSH first, then launch zellij):**

```bash
ssh <hostname>
zellij --layout work
```

**From your local machine (one command):**

```bash
ssh -t <hostname> "zellij --layout work"
```

The `-t` flag allocates a pseudo-terminal, which zellij requires. To attach to an existing session instead of creating a new one:

```bash
ssh -t <hostname> "zellij attach --layout work --create"
```

This attaches to the default session if it exists, or creates a new one with the work layout if it doesn't.

**Joost's layout** (`users/joost/zellij-work.kdl`) opens tabs for each project (fuww, about, deploy, developer, jlnl, whisky) plus a btop monitor tab. Colleague layouts use `users/zellij-work-fuww.kdl`.

## Passwords

Create hashed password with `mkpasswd` to put in `users/joost/nixos.nix`
(Google Cloud Shell has it installed by default)
[NixOS Docs on User Management](https://nixpkgs-manual-sphinx-markedown-example.netlify.app/configuration/user-mgmt.xml.html)

```
mkpasswd -m sha-512
```

## No GPG keys folder fix (SSH keys also not copied)

I had no GPG key installed on the host machine, so the copy of secrets errored out. To fix this, first install the GPG keys on the host machine. Then re-run the copy of the secrets to the VM.

```
export NIXADDR=<VM ip address>
make vm/secrets
```

## Git commands give a keychain error?

The copied ssh config from the MacOS host can contain keychain settings.
Lines with UseKeychain should look like:

```conf
IgnoreUnknown UseKeychain
UseKeychain yes
```

Source: [https://www.unixtutorial.org/ssh-bad-configuration-option-usekeychain/](https://www.unixtutorial.org/ssh-bad-configuration-option-usekeychain/)

## How to install a new package?

Go to `home-manager.nix` in `users/joost`

add, for examaple `pkgs.vscode`. You can look for packages with `nix search` or `nix --extra-experimental-features "nix-command flakes" search nixpkgs firefox
`

then run `make switch` from this repo's folder.

The full command to update host `j7`, for example:

```bash
cd ~/nixos-config && sudo nixos-rebuild switch --flake ".#j7"
```

## What to do when there is a collision between two packages with the same name but different hash?

Start with trying:

```
 sudo nix-store --verify --check-contents --repair
```

## How to update the system?

```
# Update flake.lock
nix flake update

# Apply the updates
sudo nixos-rebuild switch --flake ".#j7"
```

## How to upgrade to latest nixos?

In short, change references of 23.05 to 23.11 for the sources in flake.nix, then rebuild.

[An example commit can be seen here](https://github.com/mitchellh/nixos-config/commit/2056c76904c2b1f38c139ed645522bbdffa394a5)

More generic info: [https://nixos.org/manual/nixos/stable/index.html#sec-upgrading](https://nixos.org/manual/nixos/stable/index.html#sec-upgrading)

```bash
nix flake update
make switch
```

## Hyprland

Certain software **must** be installed for Hyprland to work properly.
[https://wiki.hyprland.org/Useful-Utilities/Must-have/](https://wiki.hyprland.org/Useful-Utilities/Must-have/)

## License
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fjavdl%2Fnixos-config.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2Fjavdl%2Fnixos-config?ref=badge_large)

## MacOS 15 Sequoia upgrade

When getting the error: `error: the user '_nixbld1' in the group 'nixbld' does not exist`

Use this script to fix it:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://github.com/NixOS/nix/raw/master/scripts/sequoia-nixbld-group-migration.sh | bash -s
```

Source: [https://discourse.nixos.org/t/macos-15-sequoia-update-clobbers-nixbld1-4-users/52223](https://discourse.nixos.org/t/macos-15-sequoia-update-clobbers-nixbld1-4-users/52223)

## git folder symlink to external disk

```bash
ln -s /Volumes/4TBMacData/git $HOME/git
```

## AI Coding Agent Stack

| Problem              | Solution                                                  |
| -------------------- | --------------------------------------------------------- |
| User Interviews      | Granola                                                   |
| AI Model             | Claude Opus 4.5 / GPT-5.2                                 |
| Model Harness        | Claude Code / Cursor / Codex                              |
| Team Conventions     | Agents.md / .cursorrules                                  |
| Workflow Process     | Ralph Wiggum Pattern                                      |
| Task Tracking        | Beads / Linear                                            |
| File Conflicts       | AgentMail / Git Worktrees                                 |
| Context Search       | CASS / grepai                                             |
| Context Compression  | CASS Memory                                               |
| Operating Procedures | Skills                                                    |
| Task Optimization    | DSPy                                                      |
| Progress Saving      | GitHub                                                    |
| Cloud Sandbox        | TMUX + Docker + Tailscale / Claude on the Web / Codex Web |

### Install Claude Code

```bash
# Native install (recommended)
curl -fsSL https://claude.ai/install.sh | bash

# Or via Homebrew on macOS
brew install --cask claude-code
```

## Tutorials

https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/tutorials](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/tutorials)

## Context priming
Read README.md, CLAUDE.md docs/*, and run git ls-files to understand this codebase.

## Add commits from the "OG" repo from Mitchell Hashimoto

```bash
git remote add upstream git@github.com:mitchellh/nixos-config.git
git fetch upstream
git log upstream/main
git cherry-pick <commit>

# example
git cherry-pick 1fa2c834308e061e60a459f607d684740fc7fcd4
git cherry-pick 1fa2c8
```

## Check where dependencies come from

```bash
nix why-depends .#darwinConfigurations.mac-studio-m2.system pkgs.nodejs_20
```

## Use GitHub authentication with Nix to prevent rate limiting

To use GitHub authentication with Nix, you need to:

  1. Create a GitHub personal access token:
    - Go to https://github.com/settings/tokens
    - Create a new token with read:packages scope
  2. Add it to your nix configuration:

```conf
 #~/.config/nix/nix.conf
 access-tokens = github.com=ghp_YOUR_GITHUB_TOKEN_HERE
 ```

## Use Chezmoi for dotfiles management

I've setup Chezmoi for dotfiles management and syncing across machines. The repo [github.com/javdl/dotfiles.git](https://github.com/javdl/dotfiles.git) can be initialized via chezmoi like this:

```bash
chezmoi init git@github.com:javdl/dotfiles.git
chezmoi diff
chezmoi apply

# or all in one
chezmoi init --apply --verbose git@github.com:javdl/dotfiles.git

# Add new
chezmoi add ~/.claude/commands
chezmoi add ~/.claude/settings.json

chezmoi cd  # Enter the chezmoi repository
jj st       # Check status
jj commit -m "Add Claude Code commands"  # Commit
jj bookmark set main -r @-  # Set main bookmark to the latest commit
jj git push
```

For more details on adding new dotfiles, making changes, see the [Chezmoi documentation](https://www.chezmoi.io/quick-start/).

## Omarchy

[https://github.com/basecamp/omarchy/discussions/987](https://github.com/basecamp/omarchy/discussions/987)

```bash1
curl -fsSL https://install.determinate.systems/nix | sh -s -- install

determinate-nixd login

NIXNAME=omarchy make switch
```

## Dicklesworthstone AI Agent Tooling

Tools from [Jeffrey Emanuel](https://github.com/Dicklesworthstone) included in this config:

| Tool | Command | Source | Description |
|------|---------|--------|-------------|
| beads | `bd` | [steveyegge/beads](https://github.com/steveyegge/beads) | Git-backed issue tracker for AI coding agents |
| beads_rust | `br` | [beads_rust](https://github.com/Dicklesworthstone/beads_rust) | Fast Rust port of beads with SQLite backend |
| beads_viewer | `bv` | [beads_viewer](https://github.com/Dicklesworthstone/beads_viewer) | Graph-aware TUI for beads: kanban, DAG visualization, PageRank |
| cass | `cass` | [coding_agent_session_search](https://github.com/Dicklesworthstone/coding_agent_session_search) | Unified TUI to index and search AI coding agent session history (Homebrew) |
| cass_memory | `cm` | [cass_memory_system](https://github.com/Dicklesworthstone/cass_memory_system) | Procedural memory for AI agents: cross-agent persistent memory (Linux only) |
| mcp_agent_mail | `am` | [mcp_agent_mail](https://github.com/Dicklesworthstone/mcp_agent_mail) | MCP server for multi-agent coordination: inboxes, threads, file leases (install script) |
| dcg | `dcg` | [destructive_command_guard](https://github.com/Dicklesworthstone/destructive_command_guard) | Safety hook that blocks dangerous git/shell commands from AI agents |
| grepai | `grepai` | [grepai](https://github.com/yoanbernabeu/grepai) | Semantic code search CLI for AI coding assistants |
| ntm | `ntm` | [ntm](https://github.com/Dicklesworthstone/ntm) | Named Tmux Manager: spawn and coordinate AI agents across tmux panes |
| repo_updater | `ru` | [repo_updater](https://github.com/Dicklesworthstone/repo_updater) | CLI for keeping GitHub repos in sync with parallel clone/pull |
| ubs | `ubs` | [ultimate_bug_scanner](https://github.com/Dicklesworthstone/ultimate_bug_scanner) | Static analysis catching 1000+ bug patterns across languages |

## Ralph loops with beads

```bash
./loop.sh                      # Default build mode
./loop.sh plan -n 5            # Plan mode, 5 iterations
./loop.sh -i --no-push         # Interactive, no git push
./loop.sh resume               # Resume last session
./loop.sh list                 # Show sessions
./loop.sh report               # Generate markdown report
```
