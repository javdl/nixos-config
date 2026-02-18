{ pkgs, inputs, ... }:

{
  # https://github.com/nix-community/home-manager/pull/2408
  environment.pathsToLink = [ "/share/fish" "share/zsh" "share/nu" ];

  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  # Since we're using fish as our shell
  programs.fish.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  users.users.lennard = {
    isNormalUser = true;
    home = "/home/lennard";
    extraGroups = [ "docker" "wheel" ];
    shell = pkgs.fish;
    # TODO: Generate with: mkpasswd -m sha-512
    hashedPassword = "$6$rounds=100000$PLACEHOLDER$XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX";
    openssh.authorizedKeys.keys = [
      # TODO: Add Lennard's SSH public key
      # "ssh-ed25519 AAAA... lennard@example.com"
    ];
  };
}
