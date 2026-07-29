# Desmond's home-manager (desmondroid) — thin wrapper over the shared colleague
# profile. Everything but the git identity lives in users/colleague-lib/.
import ../colleague-lib/home-manager-server.nix {
  gitName = "Desmond";
  gitEmail = "d.van.zurk@gmail.com";
  githubUser = "Desmond225";
}
