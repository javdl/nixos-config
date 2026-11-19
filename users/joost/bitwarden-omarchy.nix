{ isOmarchy }:
{
  lib,
  pkgs,
  ...
}:

# Bitwarden desktop (pacman) leaks renderer memory until V8 aborts with
# "V8 javascript OOM" after about a week (bitwarden/clients#20960). The main
# process survives, so the window stays blank until Bitwarden is restarted.
#
# Bitwarden starts from the XDG autostart entry below, so systemd runs it as
# app-bitwarden@autostart.service and its output reaches the journal. The
# watchdog follows that output and, on the OOM abort, stops every Bitwarden
# process (a copy started from the launcher holds the single-instance lock
# too) and starts the unit again. The app starts to tray, so a restart only
# costs a vault unlock.
let
  unit = "app-bitwarden@autostart.service";
  watchdog = pkgs.writeShellApplication {
    name = "bitwarden-renderer-watchdog";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.procps
    ];
    text = ''
      app=/usr/lib/bitwarden/app.asar
      /usr/bin/journalctl --user --follow --lines=0 --output=cat \
        --identifier=bitwarden-desktop --grep='V8 javascript OOM' |
        while read -r _; do
          echo "Bitwarden renderer ran out of memory; restarting Bitwarden"
          /usr/bin/systemctl --user stop ${unit} || true
          pkill -f "$app" || true
          for _ in $(seq 20); do
            pgrep -f "$app" >/dev/null || break
            sleep 0.5
          done
          pkill -KILL -f "$app" || true
          /usr/bin/systemctl --user start ${unit}
        done
    '';
  };
in
lib.mkIf isOmarchy {
  xdg.configFile."autostart/bitwarden.desktop" = {
    force = true;
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Bitwarden
      TryExec=/usr/bin/bitwarden-desktop
      Exec=/usr/bin/bitwarden-desktop
      StartupNotify=false
      Terminal=false
    '';
  };

  systemd.user.services.bitwarden-renderer-watchdog = {
    Unit = {
      Description = "Restart Bitwarden when its renderer runs out of memory";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${watchdog}/bin/bitwarden-renderer-watchdog";
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
