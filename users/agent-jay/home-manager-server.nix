# Agent "jay" home-manager — thin wrapper over the shared agent profile.
# Reused across every machine owned by agent-jay (agent-jay-01, -02, ...).
import ../agent-lib/home-manager.nix {
  gitName = "Agent Jay";
  gitEmail = "jay@fashionunited.com"; # TODO: confirm the address rondo should commit as
  githubUser = "agent-jay"; # TODO: set the GitHub account rondo pushes with
}
