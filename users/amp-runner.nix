# Amp runner (https://ampcode.com/docs/cli/runners) as a systemd user
# service, so threads created on ampcode.com can run on this machine
# whenever it is on. Linger starts the user manager, and with it the
# runner, at boot instead of at login.
#
# Omarchy boxes run amp from Omarchy's mise config (amp@latest) through the
# mise shim, the same CLI as interactive shells. Other hosts run Amp's own
# binary in ~/.amp/bin, which the service downloads on first start and the
# runner then updates itself; the Nix amp-cli is read-only and lags behind.
#
# The runner needs a signed-in Amp CLI. On a new host, run `amp login` (or
# ~/.amp/bin/amp login) once before the service can register.
{ currentSystemName }:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  home = config.home.homeDirectory;
  nixosConfig = "${home}/nixos-config";
  # Each runner serves its working directory plus dirs.
  runners = {
    j9 = {
      id = "joosts-desktop-j9";
      omarchy = true;
      workDir = "${home}/code/javdl/joost";
      dirs = [ nixosConfig ];
    };
    fu137 = {
      id = "joosts-desktop-fu137";
      omarchy = true;
      workDir = "${home}/code/fuww/fashionunited";
      dirs = [ nixosConfig ];
    };
    bali = {
      id = "bali";
      omarchy = false;
      workDir = "${home}/code/javdl/joost";
      dirs = [
        "${home}/code/fuww/fashionunited"
        "${home}/code/javdl/nixos-config"
      ];
    };
  };
  runner = runners.${currentSystemName} or null;

  nativeAmp = "${home}/.amp/bin/amp";
  amp = if runner.omarchy then "${home}/.local/share/mise/shims/amp" else nativeAmp;

  # The download step of https://ampcode.com/install.sh, without its PATH and
  # shell-profile edits.
  installNativeAmp = pkgs.writeShellScript "amp-runner-install" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.curl
        pkgs.gzip
      ]
    }
    [ -x ${nativeAmp} ] && exit 0
    base=https://static.ampcode.com/cli
    platform=${if pkgs.stdenv.hostPlatform.isAarch64 then "linux-arm64" else "linux-x64"}
    version=$(curl -fsSL "$base/cli-version.txt")
    expected=$(curl -fsSL "$base/$version/$platform-amp.sha256")
    mkdir -p ${dirOf nativeAmp}
    tmp=$(mktemp ${dirOf nativeAmp}/tmp.XXXXXX)
    trap 'rm -f "$tmp"' EXIT
    curl -fsSL "$base/$version/amp-$platform.gz" | gzip -d > "$tmp"
    [ "$(sha256sum "$tmp" | cut -d' ' -f1)" = "$expected" ]
    chmod 0755 "$tmp"
    mv "$tmp" ${nativeAmp}
  '';

  path =
    if runner.omarchy then
      "${home}/.cargo/bin:${home}/.local/share/mise/shims:/usr/share/omarchy/bin:${config.home.profileDirectory}/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:${home}/.local/bin:/usr/lib/rustup/bin"
    else
      "${dirOf nativeAmp}:${home}/.local/bin:${home}/.cargo/bin:${config.home.profileDirectory}/bin:/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin";
in
lib.mkIf (runner != null) {
  systemd.user.services.amp-runner = {
    Unit.Description = "Amp runner ${runner.id}";
    Service = {
      WorkingDirectory = runner.workDir;
      ExecStartPre = lib.mkIf (!runner.omarchy) "${installNativeAmp}";
      ExecStart = lib.concatStringsSep " " (
        [
          amp
          "--no-tui"
          "--runner-id"
          runner.id
        ]
        ++ lib.concatMap (dir: [
          "--dir"
          dir
        ]) runner.dirs
      );
      # Threads inherit this environment. At boot the user manager has not
      # imported a desktop session's PATH.
      Environment = [ "PATH=${path}" ];
      Restart = "always";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # NixOS hosts set users.users.<name>.linger. On Omarchy, polkit lets a user
  # in an active session set their own linger.
  home.activation.ampRunnerLinger = lib.mkIf runner.omarchy (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ "$(/usr/bin/loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != yes ]; then
        $DRY_RUN_CMD /usr/bin/loginctl enable-linger "$USER" || \
          echo "Could not enable linger; the Amp runner starts at login instead of boot. Run: sudo loginctl enable-linger $USER" >&2
      fi
    ''
  );
}
