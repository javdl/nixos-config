# NixOS configuration for music user
{ pkgs, inputs, ... }:

{
  imports = [
    # Import common system configuration
    ../common/system.nix
  ];

  # User account configuration
  users.users.music = {
    isNormalUser = true;
    home = "/home/music";
    extraGroups = [ "audio" "wheel" ];
    shell = pkgs.fish;
    hashedPassword = "$6$nJOFfAkJl1RJMxUW$DuXpYNq7rc/TE7Awuyjv7vyOyzbUnHmxN3YN1Gz1DiAw363a9GkpEU6bU9MvYa94nXaP7oTSFbZegNb8kAcUm1";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFB87It3cS6o8kgD/6r3R59KP2o1eOJz1bgLJl4syLX1 music"
    ];
  };

  # User-specific system packages
  environment.systemPackages = with pkgs; [
    # Audio tools
    jack2
    pulseaudio
    pavucontrol
    ffmpeg
  ];

  # Music-specific system services
  services = {
    # Enable JACK audio service
    jack = {
      jackd.enable = true;
      alsa.enable = true;
    };
  };

  # Use the same vim overlay as joost
  nixpkgs.overlays = import ../../lib/overlays.nix ++ [
    (import ../joost/vim.nix { inherit inputs; })
  ];
}
