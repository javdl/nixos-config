# Run: nix eval --impure --json --file tests/radon-worker.nix
let
  flake = builtins.getFlake (toString ../.);
  radon = flake.darwinConfigurations.radon.config;
  argon = flake.darwinConfigurations.argon.config;
in
assert
  map (cask: cask.name) radon.homebrew.casks == [
    "bitwarden"
    "blender"
    "brave-origin"
    "google-chrome"
    "nvidia-pair"
  ];
assert radon.homebrew.onActivation.cleanup == "none";
assert !radon.homebrew.onActivation.upgrade;
assert radon.services.darwinAutoUpdate.weekday == 0;
assert argon.services.darwinAutoUpdate.weekday == null;
assert !(radon.launchd.user.agents ? pai-voice-server);
assert !(radon.launchd.user.agents ? vicreo-listener);
assert argon.launchd.user.agents ? pai-voice-server;
assert
  radon.home-manager.users.joost.launchd.agents.agent-cli-update.config.StartInterval == 604800;
assert !radon.home-manager.users.joost.launchd.agents.agent-cli-update.config.RunAtLoad;
{
  passed = true;
  radon = radon.system.build.toplevel.drvPath;
  argon = argon.system.build.toplevel.drvPath;
}
