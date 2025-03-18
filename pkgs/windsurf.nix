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
  version = "1.4.6"; # "windsurfVersion"
  hash = "724a915b3b4c73cea3d2c93fc85672d6aa3961e0"; # "version"
in
  pkgs.callPackage "${pkgs.path}/pkgs/applications/editors/vscode/generic.nix" rec {
    inherit commandLineArgs useVSCodeRipgrep version;

    pname = "windsurf";

    executableName = "windsurf";
    longName = "Windsurf";
    shortName = "windsurf";

    src = fetchurl {
      url = "https://windsurf-stable.codeiumdata.com/linux-x64/stable/${hash}/Windsurf-linux-x64-${version}.tar.gz";
      hash = "sha256-EW4fzv6YMhdk9Nal42qOFigrINmUw4X9Pjgm3ZlF6PQ="; # sha256 of b39ddacf0afe6ceed41d502ad22c9d3f4f73ed92bdaef1763fb34aa063e650c3
    };

    sourceRoot = "Windsurf";

    tests = nixosTests.vscodium;

    updateScript = "nil";

    meta = {
      description = "The first agentic IDE, and then some";
    };
  }
