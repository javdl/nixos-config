{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.companionOmarchy;

  # These are native Arch desktop binaries, deliberately not autoPatchelf'd:
  # Omarchy supplies the graphics/GTK/USB libraries and the ELF interpreter.
  companion =
    pkgs.runCommand "companion-omarchy-5.0.5"
      {
        src = pkgs.fetchurl {
          url = "https://cf-pub.bitfocus.io/companion/companion/companion-linux-x64-5.0.5-9736-stable-0293f0d1ee.tar.gz";
          hash = "sha256-jRY66m1ZKV30H1qLPNUYcbw+qEoNeZma4KFjVeAprmY=";
        };
      }
      ''
        mkdir -p "$out/lib/companion" "$out/bin" "$out/share/applications" \
          "$out/share/icons/hicolor/256x256/apps"
        tar -xzf "$src" --strip-components=1 -C "$out/lib/companion"
        makeWrapper() {
          printf '#!${pkgs.runtimeShell}\nexec "%s" --gtk-version=3 "$@"\n' \
            "$out/lib/companion/companion-launcher" > "$out/bin/companion"
          chmod +x "$out/bin/companion"
        }
        makeWrapper
        ln -s "$out/lib/companion/companion_headless.sh" "$out/bin/companion-headless"
        sed -e "s|@EXEC_PATH@|$out/bin/companion|g" -e 's|@ICON_NAME@|companion|g' \
          "$out/lib/companion/companion.desktop.in" > "$out/share/applications/companion.desktop"
        cp "$out/lib/companion/icon.png" "$out/share/icons/hicolor/256x256/apps/companion.png"
      '';

  vicreo =
    pkgs.runCommand "vicreo-listener-omarchy-10.3.1"
      {
        src = pkgs.fetchurl {
          # Upstream only publishes a moving Linux URL; the hash pins its contents.
          # A changed upstream download must fail rather than silently updating.
          url = "https://vicreolistener.s3.eu-west-2.amazonaws.com/VICREO-Listener/VICREO-Listener-Linux-Latest-amd64.deb";
          hash = "sha256-MzYzaRl9PcEOpElHQt3kW/ABOWKPvQplF2u1aitZPKM=";
        };
        nativeBuildInputs = [
          pkgs.binutils
          pkgs.zstd
        ];
      }
      ''
        ar x "$src"
        tar -xf data.tar.zst
        mkdir -p "$out/lib" "$out/bin" "$out/share/applications" \
          "$out/share/icons/hicolor/256x256/apps"
        cp -a usr/lib/vicreo-listener "$out/lib/"
        printf '#!${pkgs.runtimeShell}\nexec "%s" --gtk-version=3 "$@"\n' \
          "$out/lib/vicreo-listener/VICREO-Listener" > "$out/bin/vicreo-listener"
        chmod +x "$out/bin/vicreo-listener"
        sed "s|Exec=vicreo-listener|Exec=$out/bin/vicreo-listener|" \
          usr/share/applications/vicreo-listener.desktop > "$out/share/applications/vicreo-listener.desktop"
        cp usr/share/pixmaps/vicreo-listener.png "$out/share/icons/hicolor/256x256/apps/"
      '';
in
{
  options.programs.companionOmarchy.enable = lib.mkEnableOption "Companion and VICREO on an Omarchy desktop";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "companionOmarchy requires an x86_64 Omarchy host with native Arch desktop libraries.";
      }
    ];

    home.packages = [
      companion
      vicreo
    ];

    xdg.configFile."autostart/companion.desktop".source =
      "${companion}/share/applications/companion.desktop";
    xdg.configFile."autostart/vicreo-listener.desktop".source =
      "${vicreo}/share/applications/vicreo-listener.desktop";

    # Seed only: Companion owns its mutable settings and database. In particular,
    # never overwrite a user's shell-command consent or their machine identity.
    home.activation.seedCompanionSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -e "${config.xdg.configHome}/companion/config.json" ]; then
        run mkdir -p "${config.xdg.configHome}/companion"
        run install -m 600 ${
          pkgs.writeText "companion-defaults.json" (
            builtins.toJSON {
              bind_ip = "127.0.0.1";
              http_port = 8000;
              start_minimised = true;
              enable_shell_command_support = false;
            }
          )
        } "${config.xdg.configHome}/companion/config.json"
      fi
    '';
  };
}
