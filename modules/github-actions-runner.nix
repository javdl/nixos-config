{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.github-actions-runner;
in
{
  options.services.github-actions-runner = {
    enable = mkEnableOption "GitHub Actions runner packages";

    packages = {
      core = mkOption {
        type = types.listOf types.package;
        default = with pkgs; [
          # Core tools
          git
          gh
          git-lfs
          mercurial
          subversion
          diffutils
          coreutils
          findutils
          bash

          # Build essentials
          gcc
          gnumake
          cmake
          autoconf
          automake
          libtool
          pkg-config
          glibc.bin # provides ldd; jdx/mise-action probes libc with it

          # Container tools
          docker
          docker-compose
          podman
          buildah
          skopeo

          # Cloud CLI tools
          google-cloud-sdk
          awscli2
          azure-cli
          doctl

          # Programming languages
          python3
          python3Packages.pip
          python3Packages.virtualenv
          nodejs_22 # was nodejs_20; Node 20 reached EOL / flagged insecure in nixpkgs 26.05
          # npm ships bundled with nodejs; standalone nodePackages.npm
          # was removed in nixpkgs 26.05
          yarn
          pnpm
          go
          rustc
          cargo
          dotnet-sdk_8
          openjdk17
          ruby
          php
          elixir
          erlang

          # Package managers
          pipx
          poetry
          uv
          bundler
          phpPackages.composer

          # Database clients
          postgresql
          mysql84 # mysql80 reached EOL and was removed in nixpkgs 26.05
          mongodb-tools
          redis
          sqlite

          # Linting tools
          rumdl
          yamllint
          libxml2 # provides xmllint

          # Development tools
          jq
          yq
          ripgrep
          fd
          bat
          httpie
          curl
          wget
          unzip
          zip
          gzip
          gnutar
          rsync
          openssh
          openssl
          gnupg

          # Testing tools
          chromium
          firefox
          geckodriver
          chromedriver

          # Kubernetes tools
          kubectl
          kubernetes-helm
          minikube
          k9s
          kustomize

          # Infrastructure as Code
          terraform
          packer

          # Monitoring and debugging
          htop
          iotop
          strace
          tcpdump
          nmap
          netcat-openbsd

          # Version control helpers
          pre-commit
          git-secrets

          # Text processing
          vim
          nano
          gnused
          gawk
          gnugrep

          # Archive tools
          p7zip
          unrar
          xz

          # Network tools
          dnsutils
          iputils
          iproute2
          net-tools
        ];
        description = "Core packages for GitHub Actions runner";
      };

      extra = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Additional packages to install";
      };

      forRunner = mkOption {
        type = types.listOf types.package;
        default = cfg.packages.core ++ cfg.packages.extra;
        readOnly = true;
        description = "Combined package list for use in runner extraPackages";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = cfg.packages.core ++ cfg.packages.extra;

    # Create /bin/bash symlink for GitHub Actions scripts that use #!/bin/bash
    # NixOS doesn't have /bin/bash by default, which breaks third-party actions
    system.activationScripts.binbash = {
      text = ''
        mkdir -p /bin
        ln -sfn ${pkgs.bash}/bin/bash /bin/bash
      '';
    };

    # Enable git-lfs globally so `git lfs` subcommand works in runner jobs
    programs.git.lfs.enable = true;

    # Normalize runner checkout file permissions.
    # The upstream services.github-runners module defaults each runner unit to
    # UMask=0066, so actions/checkout writes files 0600 (owner-only). Docker
    # `COPY` preserves those modes, baking owner-only files into images whose
    # runtime user is non-root — which then hit "permission denied" at runtime
    # (this broke ALL product-database-feeds jobs, OPS-2326). 0022 matches the
    # GitHub-hosted runner default (files 0644, dirs 0755) and applies to every
    # runner defined on the host.
    systemd.services = mapAttrs' (
      name: _:
      nameValuePair "github-runner-${name}" {
        serviceConfig.UMask = mkForce "0022";
      }
    ) config.services.github-runners;

    # Clean stale /tmp directories (self-hosted runners persist across jobs)
    systemd.tmpfiles.rules = [
      "d /tmp 1777 root root 2d"
    ];

    # Enable Docker daemon
    virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
    };

    # Enable containerd
    virtualisation.containerd.enable = true;

    # Add common CA certificates
    security.pki.certificateFiles = [
      "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    ];
  };
}
