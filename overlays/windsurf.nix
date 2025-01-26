final: prev: {
  windsurf = final.callPackage ../pkgs/windsurf.nix {
    pkgs = prev;
  };
}
