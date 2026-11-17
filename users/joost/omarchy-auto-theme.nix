# Auto Theme (github.com/mwikala/omarchy-auto-theme): a Quattro bar plugin
# that switches between light and dark themes at sunrise and sunset, with a
# night-light schedule. Every Omarchy box gets it.
#
# The plugin is a git checkout under ~/.config/omarchy/plugins, which Quattro
# owns: `omarchy plugin add` installs it and `omarchy plugin update
# mwikala.auto-theme` updates it. Nix supplies sunwait and installs the plugin
# once per machine. Theme pair, location and Auto mode are per-machine plugin
# state in ~/.config/omarchy/auto-theme/config and stay unmanaged.
{ isOmarchy }:
{ lib, pkgs, ... }:
let
  pluginId = "mwikala.auto-theme";
  pluginUrl = "https://github.com/mwikala/omarchy-auto-theme.git";
  omarchyPath = "/usr/share/omarchy";
in
{
  config = lib.mkIf isOmarchy {
    # Upstream installs sunwait from the AUR. The plugin's engine finds it on
    # PATH, and the systemd user manager's PATH includes ~/.nix-profile/bin.
    home.packages = [ pkgs.sunwait ];

    # `omarchy plugin add` and `enable` talk to the running shell over IPC, so
    # the install waits for a graphical session. The workday auto-update runs
    # at 06:00, often with no session, and the next switch catches up. The
    # shell's plugin rescan is asynchronous, so enabling waits for discovery
    # (as `omarchy plugin add --enable` does, which cannot pick a section
    # without a TTY). Only the first install places the widget: removing it
    # from the bar later sticks. Nix's LD_LIBRARY_PATH breaks Quattro's pacman
    # binaries (qs).
    home.activation.omarchyAutoTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -e "$HOME/.config/omarchy/plugins/${pluginId}" ]; then
        omarchyEnv=(env -u LD_LIBRARY_PATH OMARCHY_PATH=${omarchyPath} PATH="${omarchyPath}/bin:/usr/bin:$PATH")
        if "''${omarchyEnv[@]}" omarchy-shell shell ping >/dev/null 2>&1; then
          if $DRY_RUN_CMD "''${omarchyEnv[@]}" omarchy-plugin-add ${pluginUrl} --yes; then
            for _ in $(seq 50); do
              "''${omarchyEnv[@]}" omarchy-plugin-list --json |
                "''${omarchyEnv[@]}" jq -e 'any(.[]; .id == "${pluginId}")' >/dev/null && break
              sleep 0.1
            done
            $DRY_RUN_CMD "''${omarchyEnv[@]}" omarchy-plugin-enable ${pluginId} --section tray ||
              echo "omarchy-auto-theme: add it to the bar with: omarchy plugin enable ${pluginId} --section tray" >&2
          else
            echo "omarchy-auto-theme: plugin install failed; retry on next switch" >&2
          fi
        else
          echo "omarchy-auto-theme: Omarchy shell not running; plugin install deferred to the next switch" >&2
        fi
      fi
    '';
  };
}
