# Mosh (mobile shell) — roaming, latency-tolerant remote shell over SSH.
#
# Wired in for every NixOS host by lib/mksystem.nix; the Darwin equivalent
# (nix-darwin has no programs.mosh option) lives there too as a plain package.
#
# There is no mosh daemon: the client SSHes in and launches `mosh-server`, so
# "running" means sshd is up, the binary is on PATH, and UDP 60000-61000 is
# reachable. programs.mosh opens that range on the public firewall by default;
# hosts that are deliberately tailnet-only set `programs.mosh.openFirewall =
# false` and rely on `trustedInterfaces = [ "tailscale0" ]` instead.
{ ... }:
{
  programs.mosh.enable = true;
}
