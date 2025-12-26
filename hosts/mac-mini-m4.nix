{ config, pkgs, ... }: {
  # Set in Sept 2024 as part of the macOS Sequoia release.
  system.stateVersion = 5;

  # This makes it work with the Determinate Nix installer
  ids.gids.nixbld = 30000;

  # Set the primary user for homebrew and other user-specific settings
  system.primaryUser = "joost";

  # Don't let nix-darwin manage nix configuration since we use Determinate
  nix.settings = {};

  # Prevent nix-darwin from managing nix.conf
  environment.etc."nix/nix.conf".enable = false;

  imports =
    [
      ./mac-shared.nix
    ];

  # services = {
  #   github-runners = {
  #     # We suggest using the fine-grained PATs
  #       # https://search.nixos.org/options?channel=24.05&show=services.github-runners.%3Cname%3E.tokenFile&from=0&size=50&sort=relevance&type=packages&query=services.github-runner
  #       # The file should contain exactly one line with the token without any newline.
  #       # https://github.com/settings/personal-access-tokens/new
  #       # echo -n 'TOKEN' > $HOME/.github-runner-token
  #       # echo -n 'TOKEN' > $HOME/.fuww-github-runner-token
  #       # Give it “Read and Write access to organization/repository self hosted runners”, depending on whether it is organization wide or per-repository.
  #       # JL: op personal account heb je die niet, daar een classic PAT maken met `manage_runners:org` AND `repo` access.
  #       # For classic PATs:
  #       # Make sure the PAT has a scope of admin:org for organization-wide registrations or a scope of repo for a single repository.
  #       # voor een personal account beide geven. Daar kun je nl. alleen per repo
  #       # een url instellen, niet voor je hele username. https://github.com/javdl
  #       # werkt dus niet.
  #     runner1 = {
  #       enable = true;
  #       name = "j7-runner-nixos-config";
  #       tokenFile = "$HOME/.github-runner-token";
  #       url = "https://github.com/javdl/nixos-config";
  #     };
  #     runner2 = {
  #       enable = true;
  #       name = "j7-runner-top200-rs";
  #       tokenFile = "$HOME/.github-runner-token";
  #       url = "https://github.com/javdl/top200-rs";
  #     };
  #     runner2fuww = { # will show in systemctl as github-runner-runner2fuww.service
  #       enable = true;
  #       name = "j7-fuww-runner";
  #       tokenFile = "$HOME/.fuww-github-runner-token";
  #       url = "https://github.com/fuww";
  #     };
  #   };
  # };

  # Enable tailscale. We manually authenticate when we want with
  # "sudo tailscale up". If you don't use tailscale, you should comment
  # out or delete all of this.
  # services.tailscale.enable = true; # do not add here, it will recompile each time
}
