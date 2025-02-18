{ config, pkgs, ... }: {

  system.stateVersion = 5;

  # Mac Studio M1 office desk Joost
  networking.hostName = "fu146";

  nix.useDaemon = true;
  nix.enable = false;

  # Don't let nix-darwin manage nix configuration since we use Determinate
  nix.settings = {};
  nix.configureBuildUsers = false;

  # Prevent nix-darwin from managing nix.conf
  environment.etc."nix/nix.conf".enable = false;

  imports =
    [
      ./mac-shared.nix
    ];

    services.tailscale.enable = true;

    # services = {
    #   github-runners = {
    #     runner = {
    #       enable = true;
    #       name = "fu146-aarch64-darwin-runner";
    #       # We suggest using the fine-grained PATs https://search.nixos.org/options?channel=24.05&show=services.github-runners.%3Cname%3E.tokenFile&from=0&size=50&sort=relevance&type=packages&query=services.github-runner
    #       # The file should contain exactly one line with the token without any newline.
    #       # https://github.com/settings/personal-access-tokens/new
    #       # echo -n 'token' > ~/.fuww-github-runner-token
    #       # Give it “Read and Write access to organization/repository self hosted runners”, depending on whether it is organization wide or per-repository.
    #       tokenFile = "/home/joost/.fuww-github-runner-token";
    #       url = "https://github.com/fuww";
    #     };
    #   };
    # };
}
