{
  config,
  ...
}:

{
  # The GitHub runner service account stays isolated for CI. Herdr runs as the
  # existing joost operator account, whose Home Manager profile is intentionally
  # limited to the fleet runtime and does not replace the runner user's profile.
  users.users.joost.linger = true;

  home-manager.users.joost = import ../users/herdr-fleet.nix {
    currentSystemName = config.networking.hostName;
    provisionAgentRuntime = true;
  };

  assertions = [
    {
      assertion = config.users.users ? joost;
      message = "herdr-fleet-node requires an existing joost user";
    }
  ];
}
