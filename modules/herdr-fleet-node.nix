{
  config,
  ...
}:

let
  fleetKeys = import ../users/herdr-fleet-keys.nix;
in
{
  # The GitHub runner service account stays isolated for CI. Herdr runs as the
  # existing joost operator account, whose Home Manager profile is intentionally
  # limited to the fleet runtime and does not replace the runner user's profile.
  users.users.joost.linger = true;

  home-manager.users.joost = import ../users/herdr-fleet.nix {
    currentSystemName = config.networking.hostName;
    provisionAgentRuntime = true;
  };

  # The exe.dev command pane reaches this node from the personal tailnet.
  # Tailscale SSH (port 22 over the tailnet) cannot admit cross-tailnet
  # sources, so OpenSSH also listens on 2222. The firewall opens only 22
  # publicly; 2222 is reachable through the trusted tailscale0 interface.
  services.openssh = {
    ports = [
      22
      2222
    ];
    openFirewall = false;
  };
  users.users.joost.openssh.authorizedKeys.keys = [ fleetKeys.cmdpane ];

  assertions = [
    {
      assertion = config.users.users ? joost;
      message = "herdr-fleet-node requires an existing joost user";
    }
    {
      assertion = builtins.elem 22 config.networking.firewall.allowedTCPPorts;
      message = "herdr-fleet-node sets openssh.openFirewall = false; the host must open port 22 itself";
    }
  ];
}
