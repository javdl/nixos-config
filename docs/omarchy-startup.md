# Omarchy startup ownership

Personal desktop startup is composed in `users/joost/omarchy-startup.nix`.
It is imported by Joost's Home Manager profile and enabled only on Omarchy.

- `hypr/autostart.lua`: Ghostty with the pinned Herdr client, ChatGPT, Zed,
  Brave Origin and Slack, assigned to workspaces 1–5 at login.
- j9 XDG autostart: native Companion, VICREO Listener and JetBrains Toolbox.
  Their existing installation paths are retained; TryExec skips missing apps.
- fu137 Companion/VICREO packaging and autostart: composed through
  `users/companion-omarchy.nix`, preserving that host's existing setup.
- Agent Mail, Moshi and Cachix remain reusable background-service modules;
  they must not also be launched from Hyprland or XDG autostart.
- Voxtype remains owned by the Omarchy setup hook and local service.

Quattro owns the shell, notifications, launcher, clipboard, input methods,
locking, audio, portals and the cursor. Home Manager hides Walker's desktop
startup and masks Elephant and Mako. A mask is needed for Mako because disabling
its unit does not prevent D-Bus from starting it. Existing package installations
are left intact; they cannot take over the session through these startup paths.

Edit the Nix module, not the generated Lua or desktop files. Do not enable an
app's own login switch when its startup is already managed here. The rest of
`~/.config/hypr` stays under Omarchy ownership. Old `.conf` and `.bak` files are
not loaded by the Lua config.

Apply on the matching machine:

```sh
make test NIXNAME=j9
make switch NIXNAME=j9
hyprctl reload
hyprctl configerrors
```

On an existing session, stop the obsolete processes once after activation:

```sh
systemctl --user stop mako.service elephant.service app-walker@autostart.service
busctl --user status org.freedesktop.Notifications
```

The notification owner must be Quickshell. It retries registration when Mako
releases the bus name. The workspace applications start at the next login;
reloading Hyprland does not relaunch them.

The package exclusions in `users/joost/home-manager.nix` apply only to Omarchy.
They include its native input libraries and iA Writer fonts. The Nix cursor and
Xresources overrides are also disabled there. Extra fonts and personal CLI tools
remain available. Herdr is an intentional exception to native package ownership:
the fleet and agent integrations use the pinned Nix version (0.9.0 at this audit),
while j9's Arch package was 0.8.2.
