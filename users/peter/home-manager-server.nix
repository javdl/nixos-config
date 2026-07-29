# Peter's home-manager (peterbot) — thin wrapper over the shared colleague
# profile. Peter runs the light Rose Pine "dawn" palette; everything else lives
# in users/colleague-lib/.
import ../colleague-lib/home-manager-server.nix {
  gitName = "Peter";
  gitEmail = "peter@fashionunited.com";
  githubUser = "koszta";
  rosePineVariant = "dawn";
}
