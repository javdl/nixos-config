# Home Manager activation body that appends exact lines to
# ~/.ssh/authorized_keys. Append-only: hosts also hold keys that are not in
# this repo, which a home.file symlink would replace. Refuses a symlinked
# file. Adds a newline first when the file does not end in one, so a new key
# never lands on the end of the previous line.
{ lib, pkgs }:
{ keys, label }:
''
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
  for auth_key in ${lib.escapeShellArgs keys}; do
    if ! ${pkgs.gnugrep}/bin/grep -qxF "$auth_key" "$auth_file" 2>/dev/null; then
      if [ -n "$DRY_RUN_CMD" ]; then
        echo "Would append ${label} to $auth_file"
      else
        if [ -s "$auth_file" ] && [ -n "$(${pkgs.coreutils}/bin/tail -c1 "$auth_file")" ]; then
          printf '\n' >> "$auth_file"
        fi
        printf '%s\n' "$auth_key" >> "$auth_file"
      fi
    fi
  done
  $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod 0600 "$auth_file"
''
