"""Update only the global workstation agent CLIs, then publish verified paths."""

import fcntl
import os
from pathlib import Path
import subprocess
import sys
import tomllib


def main():
    mise = sys.argv[1]
    home = Path.home()
    config = home / ".config/mise/config.toml"
    state = home / ".local/state/agent-cli-update"
    state.mkdir(parents=True, exist_ok=True)
    with (state / "lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Agent CLI update already running; skipping.", flush=True)
            return

        with config.open("rb") as source:
            tools = tomllib.load(source).get("tools", {})
        for tool in ("codex", "claude"):
            if tools.get(tool) != "latest":
                raise ValueError(f"Expected {tool} = 'latest' in {config}; update the chezmoi source first")

        env = os.environ.copy()
        env["MISE_GLOBAL_CONFIG_FILE"] = str(config)
        env["MISE_MINIMUM_RELEASE_AGE"] = "24h"
        # / has no project config. Never resolve tools from the caller's repo.
        command = [mise, "--cd", "/"]
        subprocess.run(
            # install @latest refreshes without pruning on both the Nix-pinned
            # mise and newer Omarchy releases (older upgrade lacks --no-prune).
            command + ["install", "codex@latest", "claude@latest", "--yes",
                       "--minimum-release-age", "24h"],
            env=env, check=True, timeout=900,
        )

        verified = {}
        for tool in ("codex", "claude"):
            # Older mise registries don't expose the newer Codex bin/ layout
            # through `which`; resolve the installation itself on both versions.
            result = subprocess.run(command + ["where", tool], env=env, check=True,
                                    capture_output=True, text=True, timeout=30)
            install = Path(result.stdout.strip()).resolve(strict=True)
            binary = next((candidate.resolve(strict=True)
                           for candidate in (install / "bin" / tool, install / tool)
                           if candidate.is_file() and os.access(candidate, os.X_OK)), None)
            if binary is None:
                raise ValueError(f"No executable {tool} found in {install}")
            # Do not publish a shim or a fallback from PATH (which could recurse).
            installs = (home / ".local/share/mise/installs").resolve()
            if not binary.is_relative_to(installs):
                raise ValueError(f"{tool} resolved outside mise installs: {binary}")
            subprocess.run([str(binary), "--version"], check=True, timeout=30)
            subcommand = "exec" if tool == "codex" else "auth"
            subprocess.run([str(binary), subcommand, "--help"], check=True,
                           stdout=subprocess.DEVNULL, timeout=30)
            verified[tool] = binary

        (state / "bin").mkdir(exist_ok=True)
        for tool, binary in verified.items():
            pending = state / "bin" / f".{tool}.new"
            pending.unlink(missing_ok=True)
            pending.symlink_to(binary)
            pending.replace(state / "bin" / tool)
        print("Codex and Claude verified; workstation launchers updated.", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Agent CLI update failed: {error}", file=sys.stderr)
        sys.exit(1)
