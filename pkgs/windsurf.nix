{ lib
, stdenv
, fetchurl
, nixosTests
, pkgs
, commandLineArgs ? ""
, useVSCodeRipgrep ? stdenv.hostPlatform.isDarwin
}:

# https://windsurf-stable.codeium.com/api/update/linux-x64/stable/latest
let
  version = "1.3.4"; # "windsurfVersion"
  hash = "ff5014a12e72ceb812f9e7f61876befac66725e5"; # "version"
in
  pkgs.callPackage "${pkgs.path}/pkgs/applications/editors/vscode/generic.nix" rec {
    inherit commandLineArgs useVSCodeRipgrep version;

    pname = "windsurf";

    executableName = "windsurf";
    longName = "Windsurf";
    shortName = "windsurf";

    src = fetchurl {
      url = "https://windsurf-stable.codeiumdata.com/linux-x64/stable/${hash}/Windsurf-linux-x64-${version}.tar.gz";
      hash = "sha256-6dcf686038c6587410b25dd041a748a59593164b6c3ffb31935abef1325bfa8c"; # sha256 of b39ddacf0afe6ceed41d502ad22c9d3f4f73ed92bdaef1763fb34aa063e650c3
    };

    sourceRoot = "Windsurf";

    tests = nixosTests.vscodium;

    updateScript = "nil";

    meta = {
      description = "The first agentic IDE, and then some";
    };
  }
