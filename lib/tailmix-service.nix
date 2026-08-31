# Shared tailmixd service definition.
#
# tailmixd needs a TUN device, so it runs as a system service wherever it runs.
# Two consumers need the same unit but have different init layers:
#
#   - modules/tailmix.nix builds a NixOS systemd.services entry (bali).
#   - users/joost/home-manager.nix renders a plain unit file for the Omarchy
#     boxes, which are Arch and have no NixOS module layer to hook into.
#
# Both mirror upstream's service/tailmixd.service.in from the v0.1.9 release
# tarball (state in /var/lib/tailmix, socket dir /run/tailmix). Keeping the
# fields in one place is what stops the two from drifting apart.
{ lib }:

rec {
  description = "Tailmix multi-tailnet networking daemon";
  documentation = "https://github.com/maisem/tailmix";

  # Flags are shared too: the state and socket paths are what `tailmix profiles`
  # and `tailmix status` look for, so a client talking to a daemon started with
  # different ones silently finds no profiles.
  execStartArgs =
    {
      tailmixd,
      extraFlags ? [ ],
    }:
    [
      tailmixd
      "-state=/var/lib/tailmix/state.json"
      "-socket-dir=/run/tailmix"
    ]
    ++ extraFlags;

  execStart = args: lib.concatStringsSep " " (execStartArgs args);

  # StateDirectory/RuntimeDirectory let systemd create both paths with the right
  # modes, so neither consumer has to ship a tmpfiles rule.
  serviceConfig = {
    Type = "simple";
    Restart = "on-failure";
    RestartSec = "5s";
    StateDirectory = "tailmix";
    StateDirectoryMode = "0700";
    RuntimeDirectory = "tailmix";
    RuntimeDirectoryMode = "0755";
  };
}
