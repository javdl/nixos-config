# Companion on fu137

`homeConfigurations.fu137` (and its `omarchy` alias) installs Companion 5.0.5
and VICREO Listener 10.3.1, matching the apps installed on j9. Both appear in
the application menu and start at graphical login. The module is
`users/companion-omarchy.nix`; j9's existing manual installation and the Macs
are not changed.

These upstream Linux desktop builds use Omarchy's native libraries. They are
not general NixOS packages. Omarchy also owns `/usr/bin/wtype`, which the j9
typing buttons use. VICREO's Linux keyboard backend uses X11 and cannot type
into native Wayland apps; VICREO remains installed for the other imported
actions.

## Apply on fu137

```bash
git pull --rebase
make test NIXNAME=fu137
make switch NIXNAME=fu137
companion
vicreo-listener
```

Companion listens on `127.0.0.1:8000`. Existing settings are preserved. On a
new installation it starts minimized, with local shell commands disabled.

## Copy j9's buttons

Export the **current j9 configuration** from Companion's Import/Export screen
and transfer the `.companionconfig` privately to fu137. Import it through
fu137's Companion UI, which handles version migrations. Do not commit the
export: it can contain private prompts and connection passwords. Do not copy
`machid` or a live SQLite database between machines.

j9's adapted layout contains 42 local `wtype` typing/Enter actions. These
require enabling **Run shell commands** in Companion's launcher settings;
this permits button actions to execute commands as your user. Home Manager
does not enable this permission automatically. Any remaining VICREO connection
should target `127.0.0.1:10001` with Bonjour selection cleared. Mac-specific
shell actions may need separate adaptation.

Keep this Wayland export separate from the Mac backup in chezmoi. Importing
the old Mac backup directly restores X11/VICREO typing actions instead.

## USB and verification

Under Surfaces, enable the built-in **Elgato Stream Deck** integration. If
Companion prompts for USB permissions, use its desktop udev installer. It
generates device-specific rules; Home Manager cannot install system udev rules.
Reconnect the decks if requested.

Verify both decks appear under Surfaces, open an empty editor, and press a
typing button followed by Enter. Log out and back in to verify startup. The
application menu and autostart entries use the same launcher and data path,
`~/.config/companion`.

VICREO's download URL is named `Latest`, but Nix pins its hash. An upstream
replacement intentionally fails the build until its version and hash are
reviewed together.
