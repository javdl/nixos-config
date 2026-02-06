{ pkgs, inputs, ... }:

{
  # https://github.com/nix-community/home-manager/pull/2408
  environment.pathsToLink = [ "/share/fish" "share/zsh" "share/nu" ];

  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  # Since we're using fish as our shell
  programs.fish.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  users.users.jackson = {
    isNormalUser = true;
    home = "/home/jackson";
    extraGroups = [ "docker" "wheel" ];
    shell = pkgs.fish;
    # TODO: Generate with: mkpasswd -m sha-512
    hashedPassword = "$6$rounds=100000$PLACEHOLDER$XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPteh1Ivp8y1Psg501y1ZQLVqm9nlMN6rkTY/FJYVoBv jackson@fashionunited.com"
    ];
  };
}
