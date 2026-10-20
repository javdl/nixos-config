# Public keys of the Herdr fleet controllers (docs/herdr-command-center.md).
# Shared by the Home Manager fleet module (fu137's authorized_keys) and the
# NixOS/nix-darwin hosts that authorize the controllers in system config.
{
  # bali: id_ed25519_nopass, also its general headless agent key.
  bali = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEfx6qICt/nunP+X3Wv8Y6hhZtGo0AZreAp3QOThy0SD bali-herdr-command-center";
  # exe.dev command pane (personal exe.dev account, personal tailnet as
  # tag:cmdpane): ~/.ssh/herdr-cmdpane on that VM.
  cmdpane = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKy4oJZmZt8nIgQZyscwo13ZWx92JxfXu93wMSmPiyMG herdr-cmdpane";
}
