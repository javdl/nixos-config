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
  version = "1.3.10"; # "windsurfVersion"
  hash = "61d65579650f356494469f86c21fb953834289a0"; # "version"
in
  pkgs.callPackage "${pkgs.path}/pkgs/applications/editors/vscode/generic.nix" rec {
    inherit commandLineArgs useVSCodeRipgrep version;

    pname = "windsurf";

    executableName = "windsurf";
    longName = "Windsurf";
    shortName = "windsurf";

    src = fetchurl {
      url = "https://windsurf-stable.codeiumdata.com/linux-x64/stable/${hash}/Windsurf-linux-x64-${version}.tar.gz";
      hash = "sha256-mpgiPwYpsOAhnYKQK4w40Y3Qjdi2cA0nOUGaOFNE0X8="; # sha256 of b39ddacf0afe6ceed41d502ad22c9d3f4f73ed92bdaef1763fb34aa063e650c3
    };

    sourceRoot = "Windsurf";

    tests = nixosTests.vscodium;

    updateScript = "nil";

    meta = {
      description = "The first agentic IDE, and then some";
    };
  }
