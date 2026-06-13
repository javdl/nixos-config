{ pkgs, inputs, ... }:

{
  # https://github.com/nix-community/home-manager/pull/2408
  environment.pathsToLink = [
    "/share/fish"
    "share/zsh"
    "share/nu"
  ];

  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  programs.fish.enable = true;
  programs.zsh.enable = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  users.users.agent = {
    isNormalUser = true;
    home = "/home/agent";
    extraGroups = [
      "docker"
      "wheel"
    ];
    shell = pkgs.zsh;
    # TODO: Generate with: mkpasswd -m sha-512
    hashedPassword = "$6$rounds=100000$PLACEHOLDER$XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX";
    openssh.authorizedKeys.keys = [
      # TODO: Paste SSH public key(s) for whoever administers agent@hermes-fu.
      # Format: "ssh-ed25519 AAAA... comment"
    ];
  };
}
