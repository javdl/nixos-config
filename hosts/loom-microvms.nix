# MicroVM definitions for loom server
#
# This file defines the MicroVMs that run on the loom Hetzner server.
# Each VM provides an isolated environment for Claude Code development.
#
# Management:
#   Start VM:  sudo systemctl start microvm@devvm
#   Stop VM:   sudo systemctl stop microvm@devvm
#   Status:    sudo systemctl status microvm@devvm
#   SSH:       ssh agent@192.168.83.2
#
# Setup (one-time on host):
#   mkdir -p ~/microvm/dev/ssh-host-keys
#   ssh-keygen -t ed25519 -N "" -f ~/microvm/dev/ssh-host-keys/ssh_host_ed25519_key
#   cp ~/.ssh/authorized_keys ~/microvm/dev/ssh-host-keys/
#   mkdir -p ~/claude-microvm

{ config, pkgs, lib, inputs, ... }:

{
  # Development VM for Claude Code
  microvm.vms.devvm = {
    autostart = false;  # Start manually when needed

    # Pass inputs to the VM's module system
    specialArgs = { inherit inputs; };

    config = import ../modules/microvm/base.nix {
      hostName = "devvm";
      ipAddress = "192.168.83.2/24";
      tapId = "01";
      mac = "02:00:00:00:00:01";
      workspace = "/home/joost/microvm/dev";
      vcpu = 8;
      mem = 4096;
      extraPackages = with pkgs; [
        # Add any extra packages for this VM
        nodejs
        python3
      ];
    };
  };

  # Example: Add more VMs as needed
  # microvm.vms.testvm = {
  #   autostart = false;
  #   specialArgs = { inherit inputs; };
  #   config = import ../modules/microvm/base.nix {
  #     hostName = "testvm";
  #     ipAddress = "192.168.83.3/24";
  #     tapId = "02";
  #     mac = "02:00:00:00:00:02";
  #     workspace = "/home/joost/microvm/test";
  #   };
  # };
}
