# Rajesh's home-manager (rajbot) — thin wrapper over the shared colleague
# profile. Everything but the git identity lives in users/colleague-lib/.
import ../colleague-lib/home-manager-server.nix {
  gitName = "Rajesh";
  gitEmail = "rajesh@fashionunited.com";
  githubUser = "rajpant";
}
