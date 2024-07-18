{ config, pkgs, lib, currentSystem, currentSystemName,... }:

let


in {

    # Keep in async with vm-shared.nix. (todo: pull this out into a file)
    nix = {
        # We need to enable flakes
        extraOptions = ''
            experimental-features = nix-command flakes
            keep-outputs = true
            keep-derivations = true
        '';

        # public binary cache that I use for all my derivations. You can keep
        # this, use your own, or toss it. Its typically safe to use a binary cache
        # since the data inside is checksummed.
        settings = {
            extra-substituters = ["https://javdl-nixos-config.cachix.org"];
            trusted-public-keys = ["javdl-nixos-config.cachix.org-1:6xuHXHavvpdfBLQq+RzxDAMxhWkea0NaYvLtDssDJIU="];
        };

        # Automate garbage collection / Make sure boot does not get full
        gc = {
          automatic = true;
          randomizedDelaySec = "14m";
          options = "--delete-older-than 10d";
        };
    };

    # nix.trustedUsers = [
    #     "@admin"
    # ];

    # # Auto upgrade nix package and the daemon service.
    services.nix-daemon.enable = true;

    # zsh is the default shell on Mac and we want to make sure that we're
    # configuring the rc correctly with nix-darwin paths.
    programs.zsh.enable = true;
    programs.zsh.shellInit = ''
      # Nix
      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi
      # End Nix
      '';

    programs.fish.enable = true;
    programs.fish.shellInit = ''
      # Nix
      if test -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish'
        source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish'
      end
      # End Nix
      '';

    environment.shells = with pkgs; [ bashInteractive zsh fish ];
    environment.systemPackages = with pkgs; [
        cachix
        kitty
        terminal-notifier
    ];

    # https://github.com/nix-community/home-manager/issues/423
    # environment.variables = {
    #     TERMINFO_DIRS = "${pkgs.kitty.terminfo.outPath}/share/terminfo";
    # };
    programs.nix-index.enable = true;

    # Keyboard
    system.keyboard.enableKeyMapping = true;
    system.keyboard.remapCapsLockToEscape = true;

    # Add ability to used TouchID for sudo authentication
    security.pam.enableSudoTouchIdAuth = true;
}
