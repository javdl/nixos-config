{ config, lib, pkgs, ... }:

# Netdata monitoring — lightweight, auto-detecting system monitor.
# Dashboard accessible at http://<host>:19999 (only via Tailscale).

{
  services.netdata = {
    enable = true;
    config = {
      global = {
        "memory mode" = "dbengine";
        "page cache size" = 32;
        "dbengine multihost disk space" = 256;
        "update every" = 2;
        "debug log" = "none";
        "access log" = "none";
        "error log" = "syslog";
      };
      web = {
        "default port" = 19999;
        "bind to" = "localhost tailscale0";
      };
    };
  };
}
