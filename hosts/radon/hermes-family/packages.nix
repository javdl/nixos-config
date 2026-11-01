{ pkgs }:

# The family job scripts and MCP servers for radon's family Hermes gateway.
# Every package runs from one source tree, and that tree only builds after
# the unittest suite has passed against it on the target platform.
let
  inherit (pkgs) lib;

  python = pkgs.python3.withPackages (ps: [ ps.tzdata ]);
  mcpPython = pkgs.python3.withPackages (ps: [
    ps.mcp
    ps.tzdata
  ]);

  source = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      (lib.fileset.fileFilter (file: file.hasExt "py") ./src)
      (lib.fileset.fileFilter (file: file.hasExt "py") ./tests)
      ./tests/fixtures
    ];
  };

  tested =
    pkgs.runCommand "hermes-family-src"
      {
        # The google-oauth test serves its loopback redirect on 127.0.0.1.
        __darwinAllowLocalNetworking = true;
      }
      ''
        cd ${source}
        PYTHONPATH=${source}/src ${mcpPython.interpreter} -B -s -m unittest discover -s tests -t . \
          || { echo "hermes-family: unit tests failed" >&2; exit 1; }
        cp -r ${source}/src $out
      '';

  tool =
    name: module: interpreter:
    pkgs.writeShellScriptBin name ''
      exec ${interpreter} -I -c 'import sys; sys.path.insert(0, "${tested}"); from hermes_family.${module} import main; sys.exit(main())' "$@"
    '';
in
{
  mailFetch = tool "mail-fetch" "mailfetch" python.interpreter;
  notifier = tool "notifier" "notifier" python.interpreter;
  pickup = tool "pickup" "pickup" python.interpreter;
  planAheadWeather = tool "plan-ahead-weather" "weather" python.interpreter;
  gcalMcp = tool "gcal-mcp" "gcal_mcp" mcpPython.interpreter;
  googleOauth = tool "google-oauth" "oauth" python.interpreter;
  jobsSync = tool "jobs-sync" "jobs_sync" python.interpreter;
  modelHealth = tool "model-health" "model_health" python.interpreter;
  xBookmarks = tool "x-bookmarks" "xbookmarks" python.interpreter;
  xBookmarksDigest = tool "x-bookmarks-digest" "xdigest" python.interpreter;
}
