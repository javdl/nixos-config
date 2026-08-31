# tailmix on the Omarchy boxes

How to reach two tailnets at once from an Omarchy workstation (`j9`, `fu137`).

## Why this is needed

`tailscaled` serves exactly one tailnet at a time. `j9` holds a login on both:

```
$ tailscale switch --list
ID    Tailnet            Account
b793  fashionunited.com  joost@fashionunited.com
ff53  jvdlxz@gmail.com   joostvanderlaan@gmail.com*
```

`tailscale switch b793` moves the whole machine to the work tailnet and takes
`j9.buri-hoki.ts.net` away from every other personal machine, because the `j9`
SSH alias in `users/joost/home-manager.nix` resolves to that name. So switching
is not a way to have both.

tailmix is. It runs one tsnet client per extra tailnet behind a single TUN,
remaps each tailnet's peers into a local IPv4 range and answers MagicDNS with
those addresses, so the two overlapping `100.64.0.0/10` spaces stop colliding.
`bali` runs it for the mirror-image reason — see `modules/tailmix.nix`.

**Keep `tailscaled` on the personal tailnet (`buri-hoki`) and give the work
tailnet to tailmix.** That preserves `j9.buri-hoki.ts.net` for the machines that
address j9 by name.

## What Nix provides

| Piece | Where |
|---|---|
| `tailmix` / `tailmixd` binaries | `omarchyExtraPackages` in `flake.nix` |
| Rendered unit | `~/.config/tailmix/tailmixd.service` |
| Shared unit fields | `lib/tailmix-service.nix`, also used by `modules/tailmix.nix` |

`tailmixd` needs a TUN device, so it cannot be a Home Manager user service. Nix
renders the unit; installing it is a one-time root step.

## One-time setup

Everything below needs a terminal you can type a sudo password into.

### 1. Install the unit

```bash
sudo systemctl link ~/.config/tailmix/tailmixd.service
sudo systemctl daemon-reload
sudo systemctl enable --now tailmixd
systemctl status tailmixd --no-pager
```

`link` points `/etc/systemd/system/tailmixd.service` at the Home Manager
symlink, so a later `make switch` that changes the unit is picked up with a
`daemon-reload` — no re-linking.

If `systemctl link` refuses the path, copy the resolved file instead, and redo
this step whenever the unit changes:

```bash
sudo install -m644 "$(readlink -f ~/.config/tailmix/tailmixd.service)" \
  /etc/systemd/system/tailmixd.service
```

### 2. Get an auth key for the *other* tailnet

In a browser signed in to **`fashionunited.com`** (not the personal tailnet),
generate a key at <https://login.tailscale.com/admin/settings/keys>. A plain
non-ephemeral, non-reusable key is right: j9 is a user-owned device, matching
how `fu137` is registered (`users/herdr-fleet.nix` notes bali is tagged while
the workstations deliberately are not).

Write it to a root-only file on tmpfs so it does not survive a reboot, and never
paste it into a shell argument, this repo, or a chat:

```bash
umask 077
sudo mkdir -p /run/keys
sudo tee /run/keys/ts-work >/dev/null   # paste the key, then Ctrl-D
sudo chmod 600 /run/keys/ts-work
```

### 3. Add the profile

```bash
sudo tailmix profiles add work --hostname j9 --auth-key-file /run/keys/ts-work
sudo tailmix profiles list
sudo tailmix status
```

### 4. Delete the key

```bash
sudo rm -- /run/keys/ts-work
test ! -e /run/keys/ts-work
```

## Verify

Personal tailnet still direct, work tailnet via tailmix:

```bash
tailscale status | head -3     # still buri-hoki, j9 present
sudo tailmix status            # work peers listed
ping -c1 bali                  # a work-tailnet host
```

## Notes

- **`-auto-update=false` is set for you.** `tailmixd` defaults it to true, but
  Nix owns the binary and `/nix/store` is read-only, so a self-update can never
  apply. It is passed from `lib/tailmix-service.nix`, so bali gets it too.
  Upgrade by bumping `tailmixVersion` in `lib/overlays.nix`. A host that wants
  the daemon updating itself can pass `-auto-update=true` through `extraFlags`,
  which lands after this flag and wins.
- The unit reads its binary from `~/.nix-profile/bin/tailmixd`, a stable symlink
  that follows the current Home Manager generation, so `make switch` upgrades the
  daemon without touching the unit. This is the same convention
  `users/herdr-fleet.nix` uses for fu137's `remoteBin`. It does assume `/home` is
  mounted before `tailmixd` starts, which holds while `/home` is on the root
  filesystem.
- Profiles are deliberately imperative and per-host: each consumes an auth key
  that must not live in the Nix store.
