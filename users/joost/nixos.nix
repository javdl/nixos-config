{ pkgs, inputs, ... }:

{
  # https://github.com/nix-community/home-manager/pull/2408
  environment.pathsToLink = [ "/share/fish" "share/zsh" "share/nu" ];

  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  # Since we're using fish as our shell
  programs.fish.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  users.users.joost = {
    isNormalUser = true;
    home = "/home/joost";
    extraGroups = [ "docker" "wheel" ];
    shell = pkgs.fish;
    hashedPassword = "$6$nJOFfAkJl1RJMxUW$DuXpYNq7rc/TE7Awuyjv7vyOyzbUnHmxN3YN1Gz1DiAw363a9GkpEU6bU9MvYa94nXaP7oTSFbZegNb8kAcUm1";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINAQwjDkpe7I8Y6xdD5SbICFy0v5ArILxyTBXhtSOOmw joostvanderlaan@gmail.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFB87It3cS6o8kgD/6r3R59KP2o1eOJz1bgLJl4syLX1 joost"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEx6MK8mQ22KWCA0uDV6uBNvMw/NeBl70Mu4hxrX9SJ9 j8 mac studio"
    ];
  };
}
