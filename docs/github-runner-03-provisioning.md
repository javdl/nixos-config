# github-runner-03 (Hetzner EX63) — Provisioning Runbook

Step-by-step to bring `github-runner-03` from a fresh Hetzner rescue boot
to a registered self-hosted runner for the `fuww` org.

Server facts:
- **Hetzner EX63** dedicated (Intel i9-9900K, 64GB RAM, 2x ~512GB NVMe)
- **IPv4** 5.9.61.40 / **IPv6** 2a01:4f8:161:6209::2
- **Rescue SSH** authorizes only the `j8 mac studio` key registered at order time.
  Run all `ssh`/`make hetzner/...` commands below **from j8** (or any machine
  that holds that private key), not from loom.

The matching NixOS config (`hosts/github-runner-03.nix`) and modules
(`modules/hetzner-dedicated-hardware.nix`, `modules/disko-hetzner-dedicated.nix`)
are already on `main`. The `secrets/github-runner-03.yaml` is encrypted to
loom's age key as a chicken-and-egg placeholder — re-keyed in step 4.

---

## 1. Pull the config on j8

```bash
cd /path/to/nixos-config
git pull --rebase
```

## 2. Sanity-check rescue (still from j8)

```bash
ssh -o StrictHostKeyChecking=no root@5.9.61.40 bash <<'EOF'
  set -e
  echo "==> Boot mode:"
  [ -d /sys/firmware/efi ] && echo "    UEFI (good — systemd-boot will work)" || echo "    BIOS (swap host config to grub before provisioning)"

  echo "==> Disks:"
  lsblk -d -o NAME,SIZE,MODEL

  echo "==> Wiping any stale MD/RAID superblocks (EX-series installimage default leaves these):"
  mdadm --stop --scan 2>/dev/null || true
  for d in /dev/nvme0n1 /dev/nvme1n1; do
    mdadm --zero-superblock --force "$d" 2>/dev/null || true
    wipefs -af "$d" || true
  done

  echo "==> Final lsblk:"
  lsblk
EOF
```

If the output says `BIOS`, stop and edit `hosts/github-runner-03.nix` to
swap `boot.loader.systemd-boot` for `boot.loader.grub` (`devices =
[ "/dev/nvme0n1" ]`, `efiSupport = false`) before continuing.

If `lsblk` shows the boot NVMe as `nvme1n1` instead of `nvme0n1`, override
in `hosts/github-runner-03.nix`:

```nix
disko.devices.disk.main.device = lib.mkForce "/dev/disk/by-id/nvme-<eui>";
```

## 3. Provision NixOS (one command)

```bash
make hetzner/provision NIXADDR=5.9.61.40 NIXNAME=github-runner-03
```

This runs `nixos-anywhere --flake .#github-runner-03 root@5.9.61.40`, which:
1. Kexecs the rescue system into a NixOS installer
2. Applies the disko layout on `/dev/nvme0n1`
3. Installs the full `github-runner-03` system closure
4. Reboots

Expected first-boot warnings (normal until step 4 & 5):
- `sops-nix` cannot decrypt `github-runner-token` (host age key ≠ loom's) →
  the 16 `github-runner@fuww-runner-N.service` units stay in `activating`/`failed`.
- `tailscaled-autoconnect` fails (no auth key yet).

Verify reachability after reboot:

```bash
ssh -o StrictHostKeyChecking=no joost@5.9.61.40 'sudo systemctl status sops-nix --no-pager | head -10'
```

(SSH host key changes on reboot — clear with `ssh-keygen -R 5.9.61.40` if needed.)

## 4. Re-key SOPS to the server's real age key

On **loom** (where `sops` and the age-derived host key match):

```bash
cd ~/nixos-config

# Derive the server's age recipient from its new SSH host key
NEW_AGE=$(ssh-keyscan 5.9.61.40 2>/dev/null | grep ed25519 | ssh-to-age)
echo "Server age key: $NEW_AGE"

# Replace the placeholder anchor in .sops.yaml
sed -i "s|^  - &github-runner-03 age1.*|  - \&github-runner-03 $NEW_AGE|" .sops.yaml
grep "&github-runner-03" .sops.yaml  # confirm

# Re-encrypt the secrets file to the new recipient
sops updatekeys secrets/github-runner-03.yaml

# Commit
jj describe -m "fix(runner-03): re-key SOPS to host age key after provisioning"
jj bookmark set main -r @
jj git push
```

## 5. Set up Tailscale

Generate a key at <https://login.tailscale.com/admin/settings/keys>, then
from j8 (or any machine with the rescue/SSH key):

```bash
make hetzner/tailscale-auth NIXADDR=5.9.61.40 TAILSCALE_AUTHKEY=tskey-auth-xxx
```

Verify:

```bash
ssh joost@5.9.61.40 'tailscale status'
```

## 6. Replace the placeholder runner token

1. Go to <https://github.com/organizations/fuww/settings/actions/runners/new>
2. Copy the `--token AAU5P4...` value (29 chars, expires in 1 hour, single-use)
3. From loom:

   ```bash
   sops secrets/github-runner-03.yaml
   # Replace the PLACEHOLDER_REPLACE_AFTER_PROVISIONING string with the new token, save.

   jj describe -m "fix(runner-03): rotate registration token"
   jj bookmark set main -r @
   jj git push
   ```

4. Deploy the new token. Either wait for the 04:00 UTC `nixosAutoUpdate`,
   or trigger immediately:

   ```bash
   ssh joost@5.9.61.40 'sudo nixos-rebuild switch --flake "github:javdl/nixos-config#github-runner-03"'
   ```

## 7. Verify the 16 runners register

```bash
ssh joost@5.9.61.40 '
  systemctl list-units "github-runner-fuww-runner-*.service" --no-pager --all
  echo "---"
  for i in $(seq 1 16); do
    systemctl is-active "github-runner-fuww-runner-$i.service"
  done
'
```

Then check the GitHub UI: <https://github.com/organizations/fuww/settings/actions/runners>.
Expect 16 entries named `github-runner-03-1` … `github-runner-03-16`, all
`Idle`, with labels `hetzner`, `nixos`, `ex63`, `self-hosted-16-cores`.

## Failure recovery

| Symptom | Likely cause | Fix |
|--------|--------------|-----|
| `nixos-anywhere` hangs on kexec | rescue kernel mismatch | Re-boot rescue from Robot, retry |
| Disko reports device busy | Stale MD array assembled at boot | Re-run step 2's wipe block, then retry |
| First boot drops to emergency shell | NVMe not visible to initrd | Add `vmd` or `nvme_core` to `boot.initrd.availableKernelModules`; rebuild |
| `tailscaled-autoconnect.service` failed | Auth key not present | Step 5 |
| Runners stuck `activating (auto-restart)` | Token undecryptable or expired | Step 4 (re-key) then step 6 (fresh token) |
| Only 1 of 16 runners registers | Registration token race | Stop all units, get fresh token (step 6), `systemctl start github-runner-fuww-runner-1` and wait until `active`, then start the rest |

## Related

- High-level setup pattern: [`github-runner-hetzner-setup.md`](github-runner-hetzner-setup.md)
- Module source: [`../modules/github-actions-runner.nix`](../modules/github-actions-runner.nix)
- Host config: [`../hosts/github-runner-03.nix`](../hosts/github-runner-03.nix)
- Cloud-VS-dedicated overview: see `AGENTS.md` → *GitHub Actions Runner*
