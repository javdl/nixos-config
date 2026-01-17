# Connectivity info for Linux VM
NIXADDR ?= unset
NIXPORT ?= 22
NIXUSER ?= joost

# Get the path to this Makefile and directory
MAKEFILE_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# The name of the nixosConfiguration in the flake
NIXNAME ?= vm-intel

# SSH options that are used. These aren't meant to be overridden but are
# reused a lot so we just store them up here.
SSH_OPTIONS=-o PubkeyAuthentication=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no

# We need to do some OS switching below.
UNAME := $(shell uname)
# Detect if we're on Ubuntu (or other non-NixOS Linux with Nix)
IS_NIXOS := $(shell if [ -f /etc/NIXOS ]; then echo "yes"; else echo "no"; fi)
# Detect distribution name for non-NixOS systems
DISTRO := $(shell if [ -f /etc/os-release ]; then . /etc/os-release && echo $$ID; else echo "unknown"; fi)

switch:
ifeq ($(UNAME), Darwin)
	nix build --extra-experimental-features nix-command --extra-experimental-features flakes ".#darwinConfigurations.${NIXNAME}.system"
	sudo ./result/sw/bin/darwin-rebuild switch --flake "$$(pwd)#${NIXNAME}"
else ifeq ($(IS_NIXOS), yes)
	sudo NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --flake ".#${NIXNAME}"
else
	# For Ubuntu/non-NixOS systems, use home-manager directly
	@echo "Detected non-NixOS system ($(DISTRO)), using home-manager switch..."
	nix run home-manager/release-25.11 -- switch -b backup --flake ".#${NIXNAME}"
endif

test:
ifeq ($(UNAME), Darwin)
	nix build ".#darwinConfigurations.${NIXNAME}.system"
	sudo ./result/sw/bin/darwin-rebuild test --flake "$$(pwd)#${NIXNAME}"
else ifeq ($(IS_NIXOS), yes)
	sudo NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild test --flake ".#$(NIXNAME)"
else
	# For Ubuntu/non-NixOS systems, use home-manager build to test
	@echo "Detected non-NixOS system ($(DISTRO)), testing home-manager configuration..."
	nix build ".#homeConfigurations.${NIXNAME}.activationPackage"
endif

# This builds the given configuration and pushes the results to the
# cache. This does not alter the current running system. This requires
# cachix authentication to be configured out of band.
cache:
ifeq ($(UNAME), Darwin)
	nix build '.#darwinConfigurations.$(NIXNAME).system' --json \
		| jq -r '.[].outputs | to_entries[].value' \
		| cachix push javdl-nixos-config
else
	nix build '.#nixosConfigurations.$(NIXNAME).config.system.build.toplevel' --json \
		| jq -r '.[].outputs | to_entries[].value' \
		| cachix push javdl-nixos-config
endif

# Backup secrets so that we can transer them to new machines via
# sneakernet or other means.
.PHONY: secrets/backup
secrets/backup:
	tar -czvf $(MAKEFILE_DIR)/backup.tar.gz \
		-C $(HOME) \
		--exclude='.gnupg/.#*' \
		--exclude='.gnupg/S.*' \
		--exclude='.gnupg/*.conf' \
		--exclude='.ssh/environment' \
		.ssh/ \
		.gnupg

.PHONY: secrets/restore
secrets/restore:
	if [ ! -f $(MAKEFILE_DIR)/backup.tar.gz ]; then \
		echo "Error: backup.tar.gz not found in $(MAKEFILE_DIR)"; \
		exit 1; \
	fi
	echo "Restoring SSH keys and GPG keyring from backup..."
	mkdir -p $(HOME)/.ssh $(HOME)/.gnupg
	tar -xzvf $(MAKEFILE_DIR)/backup.tar.gz -C $(HOME)
	chmod 700 $(HOME)/.ssh $(HOME)/.gnupg
	chmod 600 $(HOME)/.ssh/* || true
	chmod 700 $(HOME)/.gnupg/* || true

# bootstrap a brand new VM. The VM should have NixOS ISO on the CD drive
# and just set the password of the root user to "root". This will install
# NixOS. After installing NixOS, you must reboot and set the root password
# for the next step.
#
# NOTE(mitchellh): I'm sure there is a way to do this and bootstrap all
# in one step but when I tried to merge them I got errors. One day.
vm/bootstrap0:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) root@$(NIXADDR) " \
		parted /dev/nvme0n1 -- mklabel gpt; \
		parted /dev/nvme0n1 -- mkpart primary 512MB -8GB; \
		parted /dev/nvme0n1 -- mkpart primary linux-swap -8GB 100\%; \
		parted /dev/nvme0n1 -- mkpart ESP fat32 1MB 512MB; \
		parted /dev/nvme0n1 -- set 3 esp on; \
		sleep 1; \
		mkfs.ext4 -L nixos /dev/nvme0n1p1; \
		mkswap -L swap /dev/nvme0n1p2; \
		mkfs.fat -F 32 -n boot /dev/nvme0n1p3; \
		sleep 1; \
		mount /dev/disk/by-label/nixos /mnt; \
		mkdir -p /mnt/boot; \
		mount /dev/disk/by-label/boot /mnt/boot; \
		nixos-generate-config --root /mnt; \
		sed --in-place '/system\.stateVersion = .*/a \
			nix.package = pkgs.nixUnstable;\n \
			nix.extraOptions = \"experimental-features = nix-command flakes\";\n \
			nix.settings.substituters = [\"https://javdl-nixos-config.cachix.org\"];\n \
			nix.settings.trusted-public-keys = [\"javdl-nixos-config.cachix.org-1:6xuHXHavvpdfBLQq+RzxDAMxhWkea0NaYvLtDssDJIU="];\n \
  			services.openssh.enable = true;\n \
			services.openssh.settings.PasswordAuthentication = true;\n \
			services.openssh.settings.PermitRootLogin = \"yes\";\n \
			users.users.root.initialPassword = \"root\";\n \
		' /mnt/etc/nixos/configuration.nix; \
		nixos-install --no-root-passwd && reboot; \
	"

# after bootstrap0, run this to finalize. After this, do everything else
# in the VM unless secrets change.
vm/bootstrap:
	NIXUSER=root $(MAKE) vm/copy
	NIXUSER=root $(MAKE) vm/switch
	$(MAKE) vm/secrets
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
		sudo reboot; \
	"

# copy our secrets into the VM
vm/secrets:
	# GPG keyring
	rsync -av -e 'ssh $(SSH_OPTIONS)' \
		--exclude='.#*' \
		--exclude='S.*' \
		--exclude='*.conf' \
		$(HOME)/.gnupg/ $(NIXUSER)@$(NIXADDR):~/.gnupg
	# SSH keys
	rsync -av -e 'ssh $(SSH_OPTIONS)' \
		--exclude='environment' \
		$(HOME)/.ssh/ $(NIXUSER)@$(NIXADDR):~/.ssh

vm/copyrepos:
	rsync -av -e 'ssh $(SSH_OPTIONS)' \
		$(HOME)/git/ $(NIXUSER)@$(NIXADDR):~/git

# copy the Nix configurations into the VM.
vm/copy:
	rsync -av -e 'ssh $(SSH_OPTIONS) -p$(NIXPORT)' \
		--exclude='vendor/' \
		--exclude='.git/' \
		--exclude='.git-crypt/' \
		--exclude='.jj/' \
		--exclude='iso/' \
		--rsync-path="sudo rsync" \
		$(MAKEFILE_DIR)/ $(NIXUSER)@$(NIXADDR):/nix-config

# run the nixos-rebuild switch command. This does NOT copy files so you
# have to run vm/copy before.
vm/switch:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
		sudo NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --flake \"/nix-config#${NIXNAME}\" \
	"

# =============================================================================
# Hetzner Dedicated Server Bootstrap
# =============================================================================
#
# Prerequisites:
#   1. Order a Hetzner dedicated server
#   2. Boot into Rescue System (Linux 64-bit) from Hetzner Robot
#   3. Note the IP address
#
# Bootstrap process:
#   make hetzner/bootstrap0 NIXADDR=<ip>   # Partition, install NixOS, reboot
#   make hetzner/bootstrap NIXADDR=<ip>    # Copy config, apply, copy secrets
#
# After bootstrap:
#   make hetzner/switch NIXADDR=<ip>       # Copy config and apply changes
#   make hetzner/tailscale-auth NIXADDR=<ip> TAILSCALE_AUTHKEY=<key>  # Set up Tailscale
#   ssh hetzner-dev                        # Connect via SSH
#
# Once Tailscale is set up:
#   ssh joost@hetzner-dev                  # Via Tailscale SSH (no keys needed)

HETZNER_SSH_OPTIONS=-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no

# Initial NixOS installation on Hetzner rescue system
# This partitions drives, installs NixOS, and reboots
hetzner/bootstrap0:
	@echo "==> Bootstrapping NixOS on Hetzner ($(NIXADDR))"
	@echo "==> This will WIPE ALL DATA on the server!"
	@echo "==> Press Ctrl+C within 5 seconds to abort..."
	@sleep 5
	ssh $(HETZNER_SSH_OPTIONS) root@$(NIXADDR) " \
		set -e; \
		echo '==> Detecting primary disk...'; \
		DISK=$$(lsblk -d -o NAME,SIZE --noheadings | grep -E 'nvme|sd' | head -1 | awk '{print \"/dev/\" \$$1}'); \
		echo \"==> Using disk: \$$DISK\"; \
		echo '==> Partitioning disk...'; \
		parted \$$DISK -- mklabel gpt; \
		parted \$$DISK -- mkpart primary 512MB -8GB; \
		parted \$$DISK -- mkpart primary linux-swap -8GB 100%; \
		parted \$$DISK -- mkpart ESP fat32 1MB 512MB; \
		parted \$$DISK -- set 3 esp on; \
		sleep 2; \
		echo '==> Formatting partitions...'; \
		mkfs.ext4 -L nixos \$${DISK}p1 || mkfs.ext4 -L nixos \$${DISK}1; \
		mkswap -L swap \$${DISK}p2 || mkswap -L swap \$${DISK}2; \
		mkfs.fat -F 32 -n boot \$${DISK}p3 || mkfs.fat -F 32 -n boot \$${DISK}3; \
		sleep 1; \
		echo '==> Mounting filesystems...'; \
		mount /dev/disk/by-label/nixos /mnt; \
		mkdir -p /mnt/boot; \
		mount /dev/disk/by-label/boot /mnt/boot; \
		swapon /dev/disk/by-label/swap; \
		echo '==> Generating hardware config...'; \
		nixos-generate-config --root /mnt; \
		echo '==> Configuring initial NixOS...'; \
		sed --in-place '/system\.stateVersion = .*/a \
			nix.package = pkgs.nixVersions.latest;\n \
			nix.extraOptions = \"experimental-features = nix-command flakes\";\n \
			nix.settings.substituters = [\"https://javdl-nixos-config.cachix.org\" \"https://cache.nixos.org\"];\n \
			nix.settings.trusted-public-keys = [\"javdl-nixos-config.cachix.org-1:6xuHXHavvpdfBLQq+RzxDAMxhWkea0NaYvLtDssDJIU=\" \"cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=\"];\n \
			services.openssh.enable = true;\n \
			services.openssh.settings.PasswordAuthentication = true;\n \
			services.openssh.settings.PermitRootLogin = \"yes\";\n \
			users.users.root.initialPassword = \"nixos\";\n \
		' /mnt/etc/nixos/configuration.nix; \
		echo '==> Installing NixOS (this takes a while)...'; \
		nixos-install --no-root-passwd; \
		echo '==> Installation complete! Rebooting...'; \
		reboot; \
	"

# After bootstrap0, copy our config and apply it
hetzner/bootstrap:
	@echo "==> Copying configuration to Hetzner..."
	NIXUSER=root $(MAKE) hetzner/copy
	@echo "==> Applying NixOS configuration..."
	NIXUSER=root $(MAKE) hetzner/switch NIXNAME=hetzner-dev
	@echo "==> Copying secrets..."
	$(MAKE) hetzner/secrets
	@echo "==> Bootstrap complete! Rebooting..."
	ssh $(HETZNER_SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) "sudo reboot" || true

# Copy configuration to Hetzner server
hetzner/copy:
	rsync -av -e 'ssh $(HETZNER_SSH_OPTIONS) -p$(NIXPORT)' \
		--exclude='vendor/' \
		--exclude='.git/' \
		--exclude='.git-crypt/' \
		--exclude='.jj/' \
		--exclude='iso/' \
		--rsync-path="sudo rsync" \
		$(MAKEFILE_DIR)/ $(NIXUSER)@$(NIXADDR):/nix-config

# Apply NixOS configuration on Hetzner
hetzner/switch:
	ssh $(HETZNER_SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
		sudo NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --flake \"/nix-config#$(NIXNAME)\" \
	"

# Copy secrets (SSH keys, GPG) to Hetzner
hetzner/secrets:
	@echo "==> Copying GPG keyring..."
	rsync -av -e 'ssh $(HETZNER_SSH_OPTIONS) -p$(NIXPORT)' \
		--exclude='.#*' \
		--exclude='S.*' \
		--exclude='*.conf' \
		$(HOME)/.gnupg/ $(NIXUSER)@$(NIXADDR):~/.gnupg
	@echo "==> Copying SSH keys..."
	rsync -av -e 'ssh $(HETZNER_SSH_OPTIONS) -p$(NIXPORT)' \
		--exclude='environment' \
		$(HOME)/.ssh/ $(NIXUSER)@$(NIXADDR):~/.ssh

# Set up Tailscale auth key on Hetzner
# Generate key at: https://login.tailscale.com/admin/settings/keys
# Use: make hetzner/tailscale-auth NIXADDR=<ip> TAILSCALE_AUTHKEY=tskey-auth-xxx
hetzner/tailscale-auth:
ifndef TAILSCALE_AUTHKEY
	$(error TAILSCALE_AUTHKEY is required. Generate at https://login.tailscale.com/admin/settings/keys)
endif
	@echo "==> Setting up Tailscale auth key on Hetzner..."
	ssh $(HETZNER_SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
		sudo mkdir -p /etc/tailscale && \
		echo '$(TAILSCALE_AUTHKEY)' | sudo tee /etc/tailscale/authkey > /dev/null && \
		sudo chmod 600 /etc/tailscale/authkey && \
		echo 'Auth key saved. Restarting Tailscale...' && \
		sudo systemctl restart tailscaled \
	"
	@echo "==> Tailscale auth key configured!"
	@echo "==> Check status with: ssh $(NIXUSER)@$(NIXADDR) 'tailscale status'"

# Fetch hardware config from Hetzner (run after bootstrap0, before bootstrap)
hetzner/fetch-hardware:
	@echo "==> Fetching hardware configuration from Hetzner..."
	scp $(HETZNER_SSH_OPTIONS) -P$(NIXPORT) root@$(NIXADDR):/mnt/etc/nixos/hardware-configuration.nix \
		$(MAKEFILE_DIR)/hosts/hardware/hetzner-dev.nix
	@echo "==> Hardware config saved to hosts/hardware/hetzner-dev.nix"
	@echo "==> Review and commit this file to git"

# =============================================================================

# Build a WSL installer
.PHONY: wsl
wsl:
	 nix build ".#nixosConfigurations.wsl.config.system.build.installer"
