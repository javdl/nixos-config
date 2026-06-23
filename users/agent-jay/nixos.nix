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
    # Password-login disabled; SSH-key login only (admin `joost` can also
    # `sudo -iu agent-jay`). Set a hash with `mkpasswd -m sha-512` if console
    # login is ever needed.
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [
      # Generated keypair for agent jay (private half held by the operator).
      # Fingerprint: SHA256:hDJ1Zn6sn/CRgv36uLHom3irMNKqqz+Ph5jh2cOQd1I
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIphfnisYvIVqlAvLqjGkIKe1OO5mgCvdmgYTyKkW2Rh agent-jay@agent-jay-01"
    ];
  };
}
