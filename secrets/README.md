# Secrets Management with SOPS

This directory contains encrypted secrets for each host using [sops-nix](https://github.com/Mic92/sops-nix).

## Setup

### 1. Install required tools

```bash
nix-shell -p sops ssh-to-age age
```

### 2. Get the host's age public key

SSH to the target host and run:

```bash
# On the target host
cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age
```

Or remotely:

```bash
ssh user@host 'cat /etc/ssh/ssh_host_ed25519_key.pub' | ssh-to-age
```

### 3. Update .sops.yaml

Add the age key to `../.sops.yaml`:

```yaml
keys:
  - &hetzner-dev age1abc123...  # Replace with actual key

creation_rules:
  - path_regex: secrets/hetzner-dev\.yaml$
    key_groups:
      - age:
          - *hetzner-dev
```

### 4. Create/Edit secrets

```bash
# Create new secrets file
sops secrets/hetzner-dev.yaml

# Edit existing secrets
sops secrets/hetzner-dev.yaml
```

Example secrets file content:

```yaml
example-api-key: sk-secret123
database/password: supersecret
tailscale/authkey: tskey-auth-xxx
```

### 5. Reference secrets in NixOS config

```nix
# In hosts/hetzner-dev.nix
{
  # Set the secrets file for this host
  sops.defaultSopsFile = ../secrets/hetzner-dev.yaml;

  # Define secrets to decrypt
  sops.secrets.tailscale-authkey = {};
  sops.secrets."database/password" = {};

  # Use the secret (available at runtime)
  services.tailscale.authKeyFile = config.sops.secrets.tailscale-authkey.path;
}
```

## File Structure

```
secrets/
├── README.md          # This file
├── hetzner-dev.yaml   # Encrypted secrets for hetzner-dev
└── <hostname>.yaml    # Add more hosts as needed
```

## Security Notes

- Secrets are encrypted in git using age
- Only hosts with matching SSH keys can decrypt their secrets
- Never commit unencrypted secrets
- The SSH host key must exist before deployment
