# NVIDIA Personal AI Router (PAIR) on the Omarchy GPU boxes fu137 and j9.
# PAIR has no system service on Linux: the desktop app starts its broker and
# workers, so it autostarts at login and keeps running from the tray. Nix
# supplies the app; the firewall and the Ollama port move need root once:
#
#   nvpair-omarchy-setup
#
# Pairing is a PIN exchange in the app. See docs/nvpair-omarchy.md.
{ currentSystemName }:

{
  lib,
  pkgs,
  ...
}:

let
  enable = builtins.elem currentSystemName [
    "fu137"
    "j9"
  ];

  # PAIR's proxy takes Ollama's 11434 and expects the engine on 11435, where
  # it adopts an Ollama it did not start. Pacman's ollama.service binds 11434
  # by default, which would leave PAIR's proxy on a random port.
  ollamaEnginePort = 11435;

  setupScript = pkgs.writeShellApplication {
    name = "nvpair-omarchy-setup";
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        exec sudo "$0" "$@"
      fi

      # Peers reach each other over Tailscale only: the proxies (Ollama 11434,
      # LM Studio 1234) carry cluster inference over mutual TLS, and
      # 14318-14323 are PAIR's fixed peer services. Plaintext proxy requests
      # from non-loopback addresses are refused by PAIR itself.
      if [ -x /usr/bin/ufw ]; then
        /usr/bin/ufw allow in on tailscale0 to any port 11434 proto tcp comment nvpair-proxy
        /usr/bin/ufw allow in on tailscale0 to any port 1234 proto tcp comment nvpair-proxy
        /usr/bin/ufw allow in on tailscale0 to any port 14318:14323 proto tcp comment nvpair-peer
      else
        echo "ufw not installed; open tcp 1234, 11434, 14318-14323 on tailscale0 yourself" >&2
      fi

      if /usr/bin/systemctl cat ollama.service >/dev/null 2>&1; then
        install -d -m 755 /etc/systemd/system/ollama.service.d
        printf '[Service]\nEnvironment="OLLAMA_HOST=127.0.0.1:${toString ollamaEnginePort}"\n' \
          > /etc/systemd/system/ollama.service.d/nvpair.conf
        /usr/bin/systemctl daemon-reload
        /usr/bin/systemctl try-restart ollama.service
        echo "ollama.service now listens on 127.0.0.1:${toString ollamaEnginePort}; restart PAIR to adopt it"
      fi
    '';
  };
in
lib.mkIf enable {
  home.packages = [
    pkgs.nvpair
    setupScript
  ];

  xdg.configFile."autostart/nvpair.desktop".source =
    "${pkgs.nvpair}/share/applications/nvpair.desktop";
}
