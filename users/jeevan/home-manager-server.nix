# Jeevan's home-manager (jeevanator) — thin wrapper over the shared colleague
# profile. Everything but the git identity lives in users/colleague-lib/.
import ../colleague-lib/home-manager-server.nix {
  gitName = "Jeevan";
  gitEmail = "jeevan@fashionunited.com";
  githubUser = "jeevanfu";
}
