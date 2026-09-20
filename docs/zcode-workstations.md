# ZCode workstations

ZCode 3.14.0 is packaged for x86_64 Linux using the official AppImage. Darwin
workstations use the Homebrew `zcode` cask. The headless Macs `argon` and `radon`,
server profiles, the legacy `github-runner` profile, and WSL do not receive it.

The dotfiles repository manages `~/.zcode/v2/provider_config.json` with
`private_dot_zcode/v2/modify_private_provider_config.json`. This modify script
preserves local settings and credentials without copying them into Git. It
disables and hides the eight built-in Z.ai/BigModel accounts and disables known
Chinese hosted providers identified by template or endpoint. Local models are
not excluded because of their model name or origin.

## Restriction is not enforced yet

These settings are defaults, **not a network security boundary**. ZCode can
rewrite them, users can add another provider, and the domain list cannot cover
every hosted service. Chezmoi reapplies the defaults only when it runs.
The app's own online services are also separate from model-provider settings.

Do not treat this configuration as satisfying a requirement that Chinese
providers cannot be used. An approved endpoint allowlist and an enforced
network policy are still needed before fleet activation under that requirement.
The outstanding choice is local/self-hosted endpoints only versus allowing
specific hosted providers as well.

## Validation

Run `make test NIXNAME=<darwin-workstation>` for Darwin. On a Linux builder,
build the package with:

```sh
nix build --no-link --impure --expr '
  let f = builtins.getFlake (toString ./.);
  in f.nixosConfigurations.j7.pkgs.zcode'
```

Apply only the ZCode dotfiles with `chezmoi apply ~/.zcode`. Do not add the
generated provider JSON, login credentials, session data, or logs to Git.
