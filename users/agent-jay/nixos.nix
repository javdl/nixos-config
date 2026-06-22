{ pkgs, ... }:

# System-level account for agent "jay". Reused across every agent-jay machine.
# Adding a new agent = copy this directory, change the username + SSH keys + git
# identity (in home-manager-server.nix).
{
  # Link shell completion/data dirs for fish/zsh/nu
  environment.pathsToLink = [
    "/share/fish"
    "share/zsh"
    "share/nu"
  ];

  # Add ~/.local/bin to PATH (native claude installer drops the binary there)
  environment.localBinInPath = true;

  users.users.agent-jay = {
    isNormalUser = true;
    home = "/home/agent-jay";
    extraGroups = [
      "docker"
      "wheel"
    ];
    shell = pkgs.zsh;
    # Locked until a real password hash is set (SSH-key login only for now).
    # Generate with: mkpasswd -m sha-512
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [
      # TODO: paste agent jay's SSH public key(s) so they can log in directly.
      # Until then, admin user `joost` (from modules/agent-dev-box.nix) can reach
      # the box and `sudo -iu agent-jay`.
      # Format: "ssh-ed25519 AAAA... comment"
    ];
  };
}
