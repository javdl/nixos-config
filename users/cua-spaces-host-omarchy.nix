# Cua Spaces host on an Omarchy (Arch) box: the Home Manager counterpart of
# modules/cua-spaces-host.nix. Here the Spaces run as joost in Omarchy's own
# Docker (pacman), and the upstream cua-spacesd-host user unit lives in
# ~/.config/systemd/user like on the NixOS hosts. One-time join, as joost:
#
#   cua-spaces-host-setup
#
# See docs/cua-bots-fleet.md.
{ currentSystemName }:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  enable = currentSystemName == "fu137";
  maxSpaces = 4;
  # Stable path that follows Home Manager generations.
  spacesdBin = "${config.home.profileDirectory}/bin/cua-spacesd";

  setupScript = pkgs.writeShellApplication {
    name = "cua-spaces-host-setup";
    runtimeInputs = [ pkgs.cua ];
    text = ''
      # A device code: approve it on a signed-in device or at the printed URL.
      cua auth login --remote --no-onboarding
      cua host setup \
        --profile spare \
        --name ${lib.escapeShellArg currentSystemName} \
        --max-spaces ${toString maxSpaces} \
        --runner systemd \
        --driver-bin ${spacesdBin}
      # The host keeps only its machine token; drop the account session.
      cua auth logout
      cua host status
    '';
  };
in
lib.mkIf enable {
  home.packages = [
    pkgs.cua
    pkgs.cua-spacesd
    setupScript
  ];

  # The daemon that creates the Spaces; see modules/cua-spaces-host.nix.
  systemd.user.services.cua-daemon = {
    Unit.Description = "Cua daemon (creates the Spaces this host provides)";
    Service = {
      ExecStart = "${pkgs.cua}/bin/cua daemon start --foreground";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # `cua host setup --driver-bin` copies the binary unless the destination
  # already resolves to it; the link keeps upstream's unit on the current
  # generation. That unit is not Home Manager's, so restart it here when the
  # binary changes.
  home.activation.cuaSpacesHost = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run install -d -m 700 "$HOME/.cua" "$HOME/.cua/host"
    run install -d -m 755 "$HOME/.cua/host/bin"
    run ln -sfn ${lib.escapeShellArg spacesdBin} "$HOME/.cua/host/bin/cua-spacesd"
    stamp="$HOME/.cua/host/bin/.nix-spacesd"
    if [ "$(cat "$stamp" 2>/dev/null)" != "${pkgs.cua-spacesd}" ]; then
      run /usr/bin/systemctl --user try-restart cua-spacesd-host.service || true
      run sh -c 'echo "$1" > "$2"' _ ${pkgs.cua-spacesd} "$stamp"
    fi
  '';
}
