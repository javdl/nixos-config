{
  hostName,
  inputs,
}:

{
  lib,
  pkgs,
  ...
}:

let
  # Same controller keys fu137 appends. Matched on the key blob rather than
  # the whole line: the on-box bali key is the same material as
  # users/herdr-fleet-keys.nix with a different comment (bali-agent-nopass).
  fleetKeys = builtins.attrValues (import ../herdr-fleet-keys.nix);
  joostKeys =
    (import ./nixos.nix { inherit pkgs inputs; }).users.users.joost.openssh.authorizedKeys.keys;
  authorizedKeys = joostKeys ++ fleetKeys;
in
{
  assertions = [
    {
      assertion = hostName == "spark" || hostName == "spark2";
      message = "users/joost/home-manager-spark.nix only applies to spark and spark2 (got ${hostName})";
    }
  ];

  home.username = "joost";
  home.homeDirectory = "/home/joost";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
  xdg.enable = true;

  # Headless slice of the Omarchy standalone profile.
  #
  # mkOmarchyHome imports users/joost/home-manager.nix, which is the desktop
  # profile: GUI apps, fonts, NVIDIA Sync/Nsight client tools, a chezmoi
  # activation that rewrites ~/.ssh/config, and Quattro path protections.
  # DGX OS has none of that ownership, and the Sparks already carry hand-written
  # CX7 SSH aliases, so this profile does not import it.
  #
  # What it does share:
  # - users/agent-clis.nix, imported beside this module from flake.nix, the
  #   same way mkOmarchyHome does. That is the herdr package (lib/overlays.nix)
  #   plus the agent CLIs and moshi-hook.
  # - mosh, the headless package in omarchyExtraPackages. tailmix, gollama,
  #   playerctl, thunderbird and insync are desktop or second-tailnet tools
  #   and are not installed here.
  #
  # Quattro installs the tools below from pacman (omarchyManagedPackageNames
  # in users/joost/home-manager.nix), so the Omarchy Nix layer omits them.
  # DGX OS has no Quattro set; Nix installs them. tmux is also requested
  # explicitly. iperf3 is requested and is not an Omarchy package.
  home.packages = with pkgs; [
    mosh
    tmux
    iperf3

    bat
    btop
    eza
    fd
    fzf
    jq
    ripgrep
    zoxide

    curl
    delta
    gh
    git
    git-lfs
    htop
    rsync
    tree
    unzip
    watch
    wget
  ];

  # Point-to-point ConnectX-7 SSH. The same aliases exist on both nodes.
  # IdentityFile is the on-box key (~/.ssh/id_ed25519_cx7, mode 600). The
  # private key is not in this repo and this module does not write it.
  # Included from ~/.ssh/config so a Home Manager symlink does not replace
  # the rest of that file (same reason fu137 appends authorized_keys).
  home.file.".ssh/config.d/dgx-spark-cx7".text = ''
    # ${hostName}: CX7 link SSH. Aliases are identical on spark and spark2.
    Host spark-cx7 192.168.100.10
      User joost
      IdentityFile ~/.ssh/id_ed25519_cx7
      IdentitiesOnly yes
      IdentityAgent none

    Host spark2-cx7 192.168.100.11
      User joost
      IdentityFile ~/.ssh/id_ed25519_cx7
      IdentitiesOnly yes
      IdentityAgent none
  '';

  home.activation.sparkCx7SshInclude = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ssh_dir="$HOME/.ssh"
    ssh_config="$ssh_dir/config"
    include_line="Include config.d/dgx-spark-cx7"

    $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -d -m 0700 "$ssh_dir"
    if [ -L "$ssh_config" ]; then
      echo "Refusing to modify symlinked $ssh_config; migrate it to a regular file first." >&2
      exit 1
    fi
    if [ ! -e "$ssh_config" ]; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 /dev/null "$ssh_config"
    fi
    if [ -n "$DRY_RUN_CMD" ]; then
      echo "Would ensure '$include_line' is the first line of $ssh_config"
    elif ! ${pkgs.gnugrep}/bin/grep -qxF "$include_line" "$ssh_config" 2>/dev/null; then
      tmp="$(${pkgs.coreutils}/bin/mktemp)"
      printf '%s\n' "$include_line" | ${pkgs.coreutils}/bin/cat - "$ssh_config" > "$tmp"
      ${pkgs.coreutils}/bin/mv "$tmp" "$ssh_config"
      ${pkgs.coreutils}/bin/chmod 0600 "$ssh_config"
    fi
  '';

  # Append public keys this repo already publishes. Never replaces the file,
  # so the CX7 from= restrictions (not in the repo; see docs/dgx-spark.md)
  # stay put. Matches on the key blob so a different comment is not appended
  # as a second copy of the same key.
  home.activation.sparkAuthorizedKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    auth_dir="$HOME/.ssh"
    auth_file="$auth_dir/authorized_keys"

    $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -d -m 0700 "$auth_dir"
    if [ -L "$auth_file" ]; then
      echo "Refusing to modify symlinked $auth_file; migrate it to a regular file first." >&2
      exit 1
    fi
    if [ ! -e "$auth_file" ]; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 /dev/null "$auth_file"
    fi
    for pubkey in ${lib.escapeShellArgs authorizedKeys}; do
      blob="$(printf '%s\n' "$pubkey" | ${pkgs.gawk}/bin/awk '{print $2}')"
      if ! ${pkgs.gnugrep}/bin/grep -qF "$blob" "$auth_file" 2>/dev/null; then
        if [ -n "$DRY_RUN_CMD" ]; then
          echo "Would append a public key to $auth_file"
        else
          printf '%s\n' "$pubkey" >> "$auth_file"
        fi
      fi
    done
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod 0600 "$auth_file"
  '';
}
