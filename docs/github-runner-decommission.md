# Decommissioning a GitHub Actions runner host

Procedure used to retire `github-runner-01` on 2026-05-21. Generalizes to any
`fuww` org runner host.

## 1. Unregister from GitHub (run from a machine with `admin:org` scope)

The fuww org token on loom only has `read:org`. Run these from **j8** (or any
machine where `gh auth status` shows `admin:org` in the token scopes).

```bash
# List the runners that would be deleted (sanity check first)
gh api /orgs/fuww/actions/runners --paginate \
  | jq -r '.runners[] | select(.name | startswith("github-runner-01-")) | "\(.id)\t\(.name)\t\(.status)"'

# Delete them
for id in $(gh api /orgs/fuww/actions/runners --paginate \
  | jq -r '.runners[] | select(.name | startswith("github-runner-01-")) | .id'); do
  gh api -X DELETE "/orgs/fuww/actions/runners/$id" && echo "deleted $id"
done
```

Adjust the `startswith("github-runner-01-")` filter to match the host being
retired (e.g. `github-runner-02-`).

If your gh token lacks `admin:org`, refresh it:

```bash
gh auth refresh -h github.com -s admin:org
```

## 2. Disable on the server side

In `hosts/github-runner-<N>.nix`, gate the runners with a local `runnersEnabled`
flag so the systemd units stop being generated:

```nix
services.github-runners =
  let runnersEnabled = false;  # flip to re-enable
  in lib.optionalAttrs runnersEnabled (lib.listToAttrs (lib.genList (i:
    # ... existing per-runner config ...
  ) 8));
```

Keeping the surrounding host config (Tailscale, sops secret, pre-job hook,
workspace tmpfiles rules) intact makes re-enabling a single boolean flip.

## 3. Stop running services + rebuild

```bash
# From loom (or wherever you control the host)
ssh joost@<runner-ip> 'sudo systemctl stop "github-runner-fuww-runner-*.service"'

git commit -am "fix(runner-<N>): disable github-runners services"
git push origin main

ssh joost@<runner-ip> 'sudo nixos-rebuild switch --flake github:javdl/nixos-config#github-runner-<N>'
```

The rebuild removes the systemd units entirely (not just `disabled`), so
they cannot come back without a config change.

## 4. Verify

```bash
ssh joost@<runner-ip> 'systemctl list-units "github-runner-fuww-runner-*.service" 2>&1 | tail -5'
# Expect: "0 loaded units listed."
```

GitHub UI: https://github.com/organizations/fuww/settings/actions/runners
should no longer show any `github-runner-<N>-*` entries.

## Reversal

To re-enable:

1. Flip `runnersEnabled = true;` in the host's `.nix` file.
2. Generate a fresh org runner registration token from
   https://github.com/organizations/fuww/settings/actions/runners/new and
   write it into `secrets/github-runner-<N>.yaml` (the existing placeholder/old
   token will be expired). The runners only need the token for first
   registration; subsequent restarts read persisted credentials from
   `/var/lib/github-runner/.runner` and `.credentials`.
3. Commit, push, rebuild.
