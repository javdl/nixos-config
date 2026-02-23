{ config, lib, pkgs, ... }:

# SOPS secrets management module
# Uses SSH host key for decryption - no separate age key needed
#
# Setup for a new host:
#   1. Get host's age public key: ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
#      (sops and ssh-to-age are installed system-wide by this module)
#   3. Add the key to .sops.yaml under keys section
#   4. Create/encrypt secrets: sops secrets/<hostname>.yaml
#   5. Reference secrets in your config: sops.secrets.example = {};
#
# Example secret usage in a host config:
#   sops.secrets.my-api-key = {};
#   # Secret available at: config.sops.secrets.my-api-key.path

{
  # Use SSH host key for automatic decryption
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # Don't use a separate age key file - rely on SSH host key
  sops.age.keyFile = lib.mkDefault null;
  sops.age.generateKey = false;

  # Add sops CLI tool for managing secrets
  environment.systemPackages = [ pkgs.sops pkgs.ssh-to-age ];
}
