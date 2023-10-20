{ config, pkgs, lib, currentSystem, currentSystemName,... }:

let
in {
  nix = {
    # use unstable nix so we can access flakes
    package = pkgs.nixUnstable;
    extraOptions = ''
      experimental-features = nix-command flakes
      keep-outputs = true
      keep-derivations = true
    '';

    settings = {
      substituters = ["https://javdl-nixos-config.cachix.org" "https://devenv.cachix.org" "https://fashionunited-cachix-org.cachixcache?priority=10" "https://fashionunited-public-cachix-org.cachixcache?priority=10" "https://cache-nixos-org.cachixcache?priority=10" "https://cache.nixos.org https://fashionunited.cachix.org" "https://fashionunited-public.cachix.org"];
      trusted-public-keys = ["javdl-nixos-config.cachix.org-1:6xuHXHavvpdfBLQq+RzxDAMxhWkea0NaYvLtDssDJIU=" "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=" "fashionunited-public.cachix.org-1:82RcZ6X7NjwUdX5bhPlqxtPLghl5peyIXFl+TfDLxlA=" "fashionunited.cachix.org-1:6bY0k5UaK/1vBZdaUrhklJMPm1DP5prBY792HDq/Scg="];
    };
  };

}
