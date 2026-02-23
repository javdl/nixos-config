{ pkgs, inputs, ... }:

{
  environment.pathsToLink = [ "/share/fish" "share/zsh" "share/nu" ];

  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  programs.zsh.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  users.users.github-runner = {
    isNormalUser = true;
    home = "/home/github-runner";
    extraGroups = [ "docker" "wheel" ];
    shell = pkgs.zsh;
    # TODO: Generate with: mkpasswd -m sha-512
    hashedPassword = "$6$rounds=100000$PLACEHOLDER$XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX";
  };
}
