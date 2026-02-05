# Hetzner Dev Box Setup Guide

Complete guide for provisioning a new NixOS development server on Hetzner Cloud.

## Prerequisites

- Hetzner Cloud account with a CPX32 (or similar) server ordered
- This nixos-config repository cloned locally
- SSH key pair on your local machine
- Tailscale account and auth key (generate at https://login.tailscale.com/admin/settings/keys)

## Overview

The setup has 4 phases:

1. **Prepare config** - Add Nix configuration files for the new server
2. **Bootstrap0** - Partition disk, install base NixOS (from Hetzner rescue mode)
3. **Bootstrap** - Copy full config, apply it, set up secrets
4. **Tailscale** - Connect to Tailscale mesh network

## Phase 0: Prepare Configuration

### 1. Choose a hostname

Pick a robot/AI-themed name (convention for colleague servers). Examples: `desmondroid`, `jacksonator`, `peterbot`.

### 2. Create host config

Create `hosts/<hostname>.nix` based on an existing colleague server config (e.g., `hosts/peterbot.nix`). Key things to customize:

- `networking.hostName` - set to your hostname
- `services.nixosAutoUpdate.flake` - update to `github:javdl/nixos-config#<hostname>`
- `services.repoUpdater.user` - set to the colleague's username
- `services.repoUpdater.projectsDir` - set to `/home/<username>/code`
- `users.users.<username>.shell` line near the bottom (zsh force)
- Remove or comment out IPv6 config until you have the address

### 3. Create hardware config

Create `hosts/hardware/<hostname>.nix`. You can copy from an existing CPX32 server (they're all the same hardware). The bootstrap process will generate the real one, which you can fetch later with:

```bash
make hetzner/fetch-hardware NIXADDR=<ip> NIXNAME=<hostname>
```

### 4. Create user configs

Create three files for the new user:

- `users/<username>/nixos.nix` - NixOS user definition (groups, shell, SSH keys, password hash)
- `users/<username>/home-manager-server.nix` - Home Manager config (packages, shell config, git config)

Copy from an existing user (e.g., `users/desmond/`) and customize:
- Username, email, home directory
- SSH authorized keys
- Password hash (generate with `mkpasswd -m sha-512`)
- Git username/email

### 5. Add to flake.nix

Add the new system configuration to `flake.nix`:

```nix
nixosConfigurations.<hostname> = mkSystem "<hostname>" {
  system = "x86_64-linux";
  user   = "<username>";
  server = true;
};
```

### 6. Commit and push

The auto-update service pulls from GitHub, so the config must be pushed:

```bash
jj file track .
jj describe -m "feat: add NixOS server config for <hostname>"
jj git push
```

## Phase 1: Bootstrap0 (Base NixOS Install)

### 1. Enable rescue mode

In Hetzner Cloud Console:
1. Go to your server
2. Click "Rescue" tab
3. Enable rescue mode (Linux 64-bit)
4. Note the **root password** shown
5. Power cycle the server (Actions > Power Off, then Power On)

Wait ~30 seconds for it to boot into rescue mode.

### 2. SSH into rescue system

```bash
# Test connectivity first
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@<ip>
# Enter the rescue password when prompted
```

> **Note**: If SSH times out, check that the server's firewall allows port 22 in the Hetzner Cloud Console (Networking > Firewalls).

### 3. Run bootstrap0

The bootstrap0 script partitions the disk, installs Nix, and installs a base NixOS system.

**Option A: Using the Makefile** (if you have SSH agent working):
```bash
make hetzner/bootstrap0 NIXADDR=<ip> NIXNAME=<hostname>
```

**Option B: Manual script** (if SSH agent isn't available, e.g., from Claude Code):

Create a local script `/tmp/bootstrap0.sh`:

```bash
#!/bin/bash
set -e

echo '==> Detecting primary disk...'
DISK=$(lsblk -d -o NAME,SIZE --noheadings | grep -E 'nvme|sd' | head -1 | awk '{print "/dev/" $1}')
echo "==> Using disk: $DISK"

echo '==> Partitioning disk...'
parted -s $DISK -- mklabel gpt
parted -s $DISK -- mkpart primary 512MB -8GB
parted -s $DISK -- mkpart primary linux-swap -8GB 100%
parted -s $DISK -- mkpart ESP fat32 1MB 512MB
parted -s $DISK -- set 3 esp on
sleep 2

echo '==> Formatting partitions...'
mkfs.ext4 -F -L nixos ${DISK}p1 || mkfs.ext4 -F -L nixos ${DISK}1
mkswap -L swap ${DISK}p2 || mkswap -L swap ${DISK}2
mkfs.fat -F 32 -n boot ${DISK}p3 || mkfs.fat -F 32 -n boot ${DISK}3
sleep 1

echo '==> Mounting filesystems...'
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot
swapon /dev/disk/by-label/swap

echo '==> Installing Nix package manager...'
curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

echo '==> Installing NixOS install tools...'
nix-channel --add https://nixos.org/channels/nixos-25.11 nixos
nix-channel --update
nix-env -iE "_: with import <nixpkgs> {}; with pkgs; [ nixos-install-tools ]"

echo '==> Generating hardware config...'
nixos-generate-config --root /mnt

echo '==> Configuring initial NixOS...'
sed --in-place '/system\.stateVersion = .*/a \
  nix.package = pkgs.nixVersions.latest;\n \
  nix.extraOptions = "experimental-features = nix-command flakes";\n \
  nix.settings.substituters = ["https://javdl-nixos-config.cachix.org" "https://cache.nixos.org"];\n \
  nix.settings.trusted-public-keys = ["javdl-nixos-config.cachix.org-1:6xuHXHavvpdfBLQq+RzxDAMxhWkea0NaYvLtDssDJIU=" "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="];\n \
  services.openssh.enable = true;\n \
  services.openssh.settings.PasswordAuthentication = true;\n \
  services.openssh.settings.PermitRootLogin = "yes";\n \
  users.users.root.initialPassword = "nixos";\n \
' /mnt/etc/nixos/configuration.nix

echo '==> Installing NixOS (this takes a while)...'
nixos-install --no-root-passwd

echo '==> Installation complete! Rebooting...'
reboot
```

Run it remotely:
```bash
# With password auth (using sshpass):
nix-shell -p sshpass --run "sshpass -p '<rescue-password>' ssh \
  -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no \
  -o PubkeyAuthentication=no \
  root@<ip> 'bash -s' < /tmp/bootstrap0.sh"
```

> **Important**: The Hetzner rescue system is Debian-based, NOT NixOS. That's why we install Nix and `nixos-install-tools` separately before running `nixos-generate-config` and `nixos-install`.

### 4. Wait for reboot

The server will reboot into NixOS. Wait ~60 seconds, then test:

```bash
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
  -o PubkeyAuthentication=no root@<ip>
# Password: nixos
```

## Phase 2: Bootstrap (Full Config)

### 1. Copy configuration

```bash
# With SSH agent:
make hetzner/copy NIXADDR=<ip> NIXUSER=root

# Without SSH agent (password auth):
RSYNC_RSH='sshpass -p nixos ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PubkeyAuthentication=no' \
  rsync -av \
  --exclude='vendor/' --exclude='.git/' --exclude='.git-crypt/' \
  --exclude='.jj/' --exclude='.beads/' --exclude='iso/' \
  ./ root@<ip>:/nix-config
```

### 2. Apply NixOS configuration

```bash
# With SSH agent:
make hetzner/switch NIXADDR=<ip> NIXUSER=root NIXNAME=<hostname>

# Without SSH agent:
nix-shell -p sshpass --run "sshpass -p 'nixos' ssh \
  -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no \
  -o PubkeyAuthentication=no \
  root@<ip> \
  'NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --flake /nix-config#<hostname>'"
```

> **Warning**: This takes 5-15 minutes on first build. SSH may drop during `systemd-networkd` restart. This is normal. The build will continue on the server.

### 3. Reboot

After the build completes (or after SSH drops), reboot the server:

```bash
ssh root@<ip> 'reboot'
```

Or use the Hetzner Cloud Console to power cycle.

> **Important**: After `nixos-rebuild switch`, SSH and Tailscale connections may drop because `systemd-networkd` restarts. A reboot is needed to restore full connectivity. Use `nixos-rebuild boot` + `reboot` for future updates to avoid mid-switch network loss.

## Phase 3: Tailscale Setup

### 1. Set up Tailscale auth key

Generate an auth key at https://login.tailscale.com/admin/settings/keys (use reusable + ephemeral for testing, or single-use for production).

```bash
# With SSH agent:
make hetzner/tailscale-auth NIXADDR=<ip> TAILSCALE_AUTHKEY=tskey-auth-xxxxx

# Without SSH agent:
nix-shell -p sshpass --run "sshpass -p 'nixos' ssh \
  -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no \
  -o PubkeyAuthentication=no \
  root@<ip> \
  'mkdir -p /etc/tailscale && echo tskey-auth-xxxxx > /etc/tailscale/authkey && chmod 600 /etc/tailscale/authkey && systemctl restart tailscaled'"
```

### 2. Reboot for Tailscale to connect

```bash
ssh root@<ip> 'reboot'
```

### 3. Verify Tailscale

After reboot, check the Tailscale admin console (https://login.tailscale.com/admin/machines) to see the new machine. Also check locally:

```bash
tailscale status | grep <hostname>
```

### 4. Add SSH config entry

Add to your `~/.ssh/config`:

```
Host <hostname>
  HostName <tailscale-ip-or-hostname>
  User <username>
  ForwardAgent yes
```

## Phase 4: Post-Setup

### 1. Fetch real hardware config

The bootstrap0 generated a hardware config on the server. Fetch it:

```bash
make hetzner/fetch-hardware NIXADDR=<tailscale-ip> NIXNAME=<hostname>
```

Review `hosts/hardware/<hostname>.nix` and commit it.

### 2. Copy secrets (optional)

If the user needs GPG/SSH keys:

```bash
make hetzner/secrets NIXADDR=<tailscale-ip>
```

### 3. Set user password

SSH in and set the user's password:

```bash
ssh root@<hostname>  # via Tailscale
passwd <username>
```

Or generate a hash and add it to the user's `nixos.nix`:

```bash
mkpasswd -m sha-512
```

### 4. Add user's SSH keys

Add the user's public SSH key(s) to `users/<username>/nixos.nix` in the `openssh.authorizedKeys.keys` list.

### 5. Future updates

Once Tailscale is running, use the Tailscale IP or hostname for all future operations:

```bash
# Copy updated config
make hetzner/copy NIXADDR=<tailscale-ip> NIXNAME=<hostname>

# Apply changes (use boot + reboot to avoid SSH drops)
ssh root@<hostname> 'nixos-rebuild boot --flake /nix-config#<hostname> && reboot'
```

The server also has automatic updates configured (`services.nixosAutoUpdate`) that pull from GitHub daily at 04:00 UTC.

## Troubleshooting

### SSH times out on public IP
- Check Hetzner Cloud firewall allows port 22
- Use Tailscale IP instead (once Tailscale is set up)
- Check if server is still booting (use Hetzner console)

### SSH drops during nixos-rebuild switch
- This is normal - `systemd-networkd` restart kills SSH connections
- Reboot the server to restore connectivity
- Use `nixos-rebuild boot` + `reboot` instead to avoid this

### UEFI Shell instead of NixOS
- Server has no OS installed yet — needs full bootstrap from rescue mode
- Follow Phase 1 (Bootstrap0) from the beginning

### Nix flake evaluation errors about unsupported file types
- Usually caused by `.beads/bd.sock` (Unix socket) in the config directory
- The Makefile rsync already excludes `.beads/`
- If running rsync manually, add `--exclude='.beads/'`

### Server not appearing on Tailscale
- Check auth key is saved: `cat /etc/tailscale/authkey`
- Check Tailscale service: `systemctl status tailscaled`
- Restart Tailscale: `systemctl restart tailscaled`
- Auth key may have expired — generate a new one

## Server Inventory

| Hostname | User | IP | Hetzner Plan |
|----------|------|----|-------------|
| loom | joost | 91.99.204.187 | CPX32 |
| desmondroid | desmond | 91.99.228.135 | CPX32 |
| jacksonator | jackson | 49.13.202.212 | CPX32 |
| peterbot | peter | 91.98.229.173 | CPX32 |
