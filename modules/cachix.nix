{
  config,
  lib,
  pkgs,
  currentSystemUser ? null,
  isServer ? false,
  ...
}:

let
  # Push side (see lib/cachix-push-hook.nix). The post-build-hook is a
  # daemon-side (root) nix.conf setting, so enable it only for joost's machines
  # — colleague servers also import this module but must not push to joost's
  # personal cache. On Darwin nix-darwin doesn't manage nix.conf
  # (nix.enable = false), so the Mac equivalent lives in hosts/mac-shared.nix.
  cp = import ../lib/cachix-push-hook.nix pkgs;
  pushEnabled = currentSystemUser == "joost" && pkgs.stdenv.isLinux;
  desktopCaches = !isServer;
in
{
  # Install cachix CLI tool
  environment.systemPackages = [ pkgs.cachix ];

  # Configure Nix settings for caches
  nix.settings = {
    substituters = [
      "https://javdl-nixos-config.cachix.org"
    ]
    ++ lib.optionals desktopCaches [
      "https://devenv.cachix.org"
      "https://nix-community.cachix.org"
    ];

    trusted-public-keys = [
      "javdl-nixos-config.cachix.org-1:6xuHXHavvpdfBLQq+RzxDAMxhWkea0NaYvLtDssDJIU="
    ]
    ++ lib.optionals desktopCaches [
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];

    # Trust users to manage the Nix store
    trusted-users = [
      "joost"
      "root"
    ];
  }
  // lib.optionalAttrs pushEnabled {
    # Hand locally-built paths to joost's per-user cachix daemon (async upload).
    post-build-hook = "${cp.hook}";
  };
}
