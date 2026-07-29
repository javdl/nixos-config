# Jackson's home-manager (jacksonator) — thin wrapper over the shared colleague
# profile. jacksonator needs its tmux server to survive tailscaled restarts (see
# the comments at the usage sites in colleague-lib); everything else is shared.
import ../colleague-lib/home-manager-server.nix {
  gitName = "Jackson";
  gitEmail = "jackson@fashionunited.com";
  githubUser = "jacksonfu14";
  persistentTmuxServer = true;
}
