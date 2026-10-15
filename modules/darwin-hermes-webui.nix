# Nix-managed WebUI with the same sealed Python environment as Hermes.
{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  agent = pkgs.hermes-agent;
  webui = inputs.hermes-webui.packages.${pkgs.stdenv.hostPlatform.system}.default;
  agentDir = "${agent.hermesVenv}/${agent.python.sitePackages}";
  # WebUI requires PyYAML, while Hermes uses ruamel.yaml. Match the agent's
  # interpreter instead of mixing Python versions from two flake inputs.
  yaml = agent.python.pkgs.pyyaml;
  pythonPath = lib.makeSearchPath agent.python.sitePackages [ yaml ];
  launcher = pkgs.writeShellScriptBin "hermes-webui-nix" ''
    export HERMES_WEBUI_AGENT_DIR=${agentDir}
    export HERMES_WEBUI_PYTHON=${agent.hermesVenv}/bin/python3
    export HERMES_WEBUI_DISABLE_LOCAL_VENV=1
    export HERMES_INSTALL_ROOT=${agent}/share/hermes-agent
    export HERMES_BUNDLED_SKILLS=${agent}/share/hermes-agent/skills
    export HERMES_OPTIONAL_SKILLS=${agent}/share/hermes-agent/optional-skills
    export HERMES_BUNDLED_PLUGINS=${agent}/share/hermes-agent/plugins
    export HERMES_BUNDLED_LOCALES=${agent}/share/hermes-agent/locales
    export HERMES_OPTIONAL_MCPS=${agent}/share/hermes-agent/optional-mcps
    export PYTHONPATH=${pythonPath}
    export PATH=${
      lib.makeBinPath [
        agent
        pkgs.cua
        pkgs.agent-browser
        pkgs.nodejs_22
        pkgs.ffmpeg
        pkgs.git
        pkgs.openssh
        pkgs.uv
      ]
    }:"$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    # Keep CuaDriver.app's signed identity/TCC permissions, not an unsigned
    # copy under /nix/store. The existing driver owns its lifecycle.
    export CUA_DRIVER_PATH=/Applications/CuaDriver.app/Contents/MacOS/cua-driver
    exec ${agent.hermesVenv}/bin/python3 ${webui}/hermes-webui/bootstrap.py \
      --foreground --no-browser --skip-agent-install "$@"
  '';
in
{
  environment.systemPackages = [ launcher ];
  launchd.user.agents.hermes-webui.serviceConfig = {
    Label = "com.parantoux.hermes-webui";
    ProgramArguments = [ "${launcher}/bin/hermes-webui-nix" ];
    WorkingDirectory = "/Users/joost/workspace";
    EnvironmentVariables = {
      HOME = "/Users/joost";
      HERMES_HOME = "/Users/joost/.hermes";
      HERMES_WEBUI_STATE_DIR = "/Users/joost/.hermes/webui";
      HERMES_WEBUI_HOST = "127.0.0.1";
      HERMES_WEBUI_PORT = "8787";
      CUA_TELEMETRY = "0";
    };
    RunAtLoad = true;
    KeepAlive = true;
    ThrottleInterval = 30;
    StandardOutPath = "/Users/joost/.hermes/webui.log";
    StandardErrorPath = "/Users/joost/.hermes/webui.log";
  };
}
