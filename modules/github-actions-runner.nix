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

          # Package managers
          pipx
          poetry
          bundler
          composer

          # Database clients
          postgresql
          mysql80
          mongodb-tools
          redis
          sqlite

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
          tar
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
          netcat

          # Version control helpers
          pre-commit
          git-secrets

          # Text processing
          vim
          nano
          sed
          awk
          grep

          # Archive tools
          p7zip
          unrar

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
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = cfg.packages.core ++ cfg.packages.extra;

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
