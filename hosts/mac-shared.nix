{ config, pkgs, lib, currentSystem, currentSystemName,... }:

let
  # Auto-sync ~/.claude/MEMORY to the chezmoi git remote.
  # Re-adds live MEMORY into the chezmoi source repo, then commits + pushes
  # via jj if anything changed. Runs every 5 minutes via launchd.
  chezmoiMemorySync = pkgs.writeShellScript "chezmoi-memory-sync" ''
    set -u
    CHEZMOI_SRC="$HOME/.local/share/chezmoi"
    MEMORY_LIVE="$HOME/.claude/MEMORY"
    MEMORY_SRC_PATH="dot_claude/MEMORY"

    [ -d "$CHEZMOI_SRC" ] || { echo "no chezmoi source"; exit 0; }
    [ -d "$MEMORY_LIVE" ] || { echo "no live MEMORY"; exit 0; }

    # Re-add only the MEMORY tree. --keep-going skips secret-scanner false
    # positives (e.g. session titles containing "Api Key").
    chezmoi re-add --keep-going "$MEMORY_LIVE" || true

    cd "$CHEZMOI_SRC" || exit 0

    # Bail out if nothing changed under MEMORY.
    if ! jj diff --stat -- "$MEMORY_SRC_PATH" 2>/dev/null | grep -q .; then
      exit 0
    fi

    # Refuse to run if the working copy has changes outside MEMORY/.
    # Avoids accidentally bundling unrelated manual chezmoi edits into an
    # auto-commit. User must commit/discard those manually first.
    if jj diff --name-only 2>/dev/null | grep -v "^$MEMORY_SRC_PATH/" | grep -q .; then
      echo "skip: working copy has changes outside $MEMORY_SRC_PATH" >&2
      jj diff --name-only | grep -v "^$MEMORY_SRC_PATH/" >&2
      exit 0
    fi

    # Pull remote changes first to minimize conflicts.
    jj git fetch 2>/dev/null || true
    jj rebase -d main 2>/dev/null || true

    jj describe -m "chore(memory): auto-sync $(date -u +%Y-%m-%dT%H:%MZ)"
    jj bookmark set main -r @
    jj git push 2>&1
  '';
in {
  imports = [
    ../modules/cachix.nix
  ];

  # Determinate Nix includes nix.custom.conf - set restricted settings here
  # so the daemon applies them globally (avoids "not a trusted user" warnings)
  environment.etc."nix/nix.custom.conf".text = ''
    download-buffer-size = 536870912
  '';

    # Allow unfree packages
    nixpkgs.config.allowUnfree = true;
    nixpkgs.config.allowUnfreePredicate = _: true;

    nix = {
    # We use the determinate-nix installer which manages Nix for us,
    # so we don't want nix-darwin to do it.
    enable = false;

    extraOptions = ''
      experimental-features = nix-command flakes
      keep-outputs = true
      keep-derivations = true
    '';

    # Enable the Linux builder so we can run Linux builds on our Mac.
    # This can be debugged by running `sudo ssh linux-builder`
    linux-builder = {
      enable = false;
      ephemeral = true;
      maxJobs = 4;
      config = ({ pkgs, ... }: {
        # Make our builder beefier since we're on a beefy machine.
        virtualisation = {
          cores = 6;
          darwin-builder = {
            diskSize = 100 * 1024; # 100GB
            memorySize = 32 * 1024; # 32GB
          };
        };

        # Add some common debugging tools we can see whats up.
        environment.systemPackages = [
          pkgs.htop
        ];
      });
    };

  };

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
    # nix-index with pre-built database (avoids broken nix-env enumeration)
    # programs.nix-index.enable is set by nix-index-database module
    programs.nix-index-database.comma.enable = true;

    # Start VICREO Listener at login (receives keystroke commands from Bitfocus Companion)
    launchd.user.agents.vicreo-listener = {
      serviceConfig = {
        ProgramArguments = [
          "/usr/bin/open" "-a" "/Applications/VICREO-Listener.app"
        ];
        RunAtLoad = true;
      };
    };

    # Expose Nix paths to GUI apps (Companion, etc.) via launchd
    launchd.user.agents.nix-path-env = {
      serviceConfig = {
        ProgramArguments = [
          "/bin/sh" "-c"
          ''/bin/launchctl setenv PATH "/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"''
        ];
        RunAtLoad = true;
      };
    };

    # PAI Voice Server (ElevenLabs TTS on port 8888)
    launchd.user.agents.pai-voice-server = {
      serviceConfig = {
        ProgramArguments = [
          "/bin/sh" "-c"
          ''export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.bun/bin"; exec bun run "$HOME/.claude/VoiceServer/server.ts"''
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/pai-voice-server.log";
        StandardErrorPath = "/tmp/pai-voice-server.log";
      };
    };

    # Auto-sync ~/.claude/MEMORY to chezmoi git remote every 5 minutes.
    # Why: cross-machine sync of WORK PRDs and STATE without manual chezmoi re-add.
    launchd.user.agents.chezmoi-memory-sync = {
      serviceConfig = {
        ProgramArguments = [
          "/bin/sh" "-c"
          ''export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"; exec ${chezmoiMemorySync}''
        ];
        RunAtLoad = true;
        StartInterval = 300;
        StandardOutPath = "/tmp/chezmoi-memory-sync.log";
        StandardErrorPath = "/tmp/chezmoi-memory-sync.log";
      };
    };

    # Keyboard
    system.keyboard.enableKeyMapping = true;
    system.keyboard.remapCapsLockToEscape = true;

    # Add ability to used TouchID for sudo authentication
    security.pam.services.sudo_local.touchIdAuth = true;
}
