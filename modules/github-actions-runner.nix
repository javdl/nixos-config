{ config, lib, pkgs, ... }:

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
          nodejs_20
          nodePackages.npm
          nodePackages.yarn
          nodePackages.pnpm
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
          mysql80
          mongodb-tools
          redis
          sqlite

          # Linting tools
          rumdl
          yamllint
          libxml2  # provides xmllint

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
        default = [];
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
    system.activationScripts.binbash = lib.stringAfter [ "stdio" ] ''
      mkdir -p /bin
      ln -sfn ${pkgs.bash}/bin/bash /bin/bash
    '';

    # Enable git-lfs globally so `git lfs` subcommand works in runner jobs
    programs.git.lfs.enable = true;

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
