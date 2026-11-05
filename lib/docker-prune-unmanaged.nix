# `docker system prune --all --filter until=<hours>` that spares the containers
# and images holding state this host must keep: Cua Spaces
# (label ai.cua.managed=true, modules/cua-spaces-host.nix) and Amp orbs with
# their snapshot images (label ai.amp.orb=true, modules/amp-orb-provider.nix).
# Docker ANDs repeated `label!=` filters, so one prune command cannot spare two
# labels; this script picks the candidates itself and removes them one by one.
{
  writeShellApplication,
  docker,
  coreutils,
}:

writeShellApplication {
  name = "docker-prune-unmanaged";
  runtimeInputs = [
    docker
    coreutils
  ];
  text = ''
    usage="usage: docker-prune-unmanaged --until <hours>h"
    until=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --until) until="$2"; shift 2 ;;
        *) echo "$usage" >&2; exit 2 ;;
      esac
    done
    [[ "$until" =~ ^([0-9]+)h$ ]] || { echo "$usage" >&2; exit 2; }
    cutoff=$(( $(date +%s) - BASH_REMATCH[1] * 3600 ))
    keep_labels=(ai.cua.managed=true ai.amp.orb=true)

    kept() {
      for l in "''${keep_labels[@]}"; do
        docker "$1" ls --all --quiet --no-trunc --filter "label=$l"
      done | sort -u
    }
    older_than_cutoff() {
      local created
      created=$(docker "$1" inspect --format '{{.Created}}' "$2") || return 1
      [ "$(date -d "$created" +%s)" -lt "$cutoff" ]
    }

    removed=0
    stopped=(--filter status=exited --filter status=created --filter status=dead)
    for id in $(comm -23 <(docker container ls --all --quiet --no-trunc "''${stopped[@]}" | sort -u) <(kept container)); do
      older_than_cutoff container "$id" || continue
      docker container rm "$id" >/dev/null && removed=$((removed + 1))
    done
    echo "removed $removed containers"

    removed=0
    for id in $(comm -23 <(docker image ls --quiet --no-trunc | sort -u) <(kept image)); do
      older_than_cutoff image "$id" || continue
      # Untagging the last tag deletes the image. Without --force, an image a
      # container still uses is refused and stays.
      read -ra refs <<< "$(docker image inspect --format '{{join .RepoTags " "}}' "$id")"
      [ "''${#refs[@]}" -gt 0 ] || refs=("$id")
      docker image rm "''${refs[@]}" >/dev/null 2>&1 && removed=$((removed + 1))
    done
    echo "removed $removed images"

    docker network prune --force --filter "until=$until" >/dev/null
    docker builder prune --all --force --filter "until=$until" >/dev/null
  '';
}
