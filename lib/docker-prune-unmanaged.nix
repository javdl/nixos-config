# `docker system prune --all --filter until=<hours>` that spares the containers
# and images holding state this host must keep: Cua Spaces
# (label ai.cua.managed=true, modules/cua-spaces-host.nix) and Amp orbs with
# their snapshot images (label ai.amp.orb=true, modules/amp-orb-provider.nix).
# Docker ANDs repeated `label!=` filters, so one prune command cannot spare two
# labels; this script picks the candidates itself and removes them one by one.
# `--drop-orb-snapshots`, for the low-disk paths, also removes the orb snapshot
# images no container uses; a spawn then starts from the base image instead.
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
    usage="usage: docker-prune-unmanaged --until <hours>h [--drop-orb-snapshots]"
    until=""
    drop_orb_snapshots=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --until) until="$2"; shift 2 ;;
        --drop-orb-snapshots) drop_orb_snapshots=1; shift ;;
        *) echo "$usage" >&2; exit 2 ;;
      esac
    done
    [[ "$until" =~ ^([0-9]+)h$ ]] || { echo "$usage" >&2; exit 2; }
    cutoff=$(( $(date +%s) - BASH_REMATCH[1] * 3600 ))
    orb_label=ai.amp.orb=true
    keep_labels=(ai.cua.managed=true "$orb_label")

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

    # Images are removed tag by tag, and Docker only refuses the last tag of an
    # image a container uses, so images any container references are excluded
    # up front rather than left to that refusal.
    in_use() {
      docker container ls --all --quiet --no-trunc \
        | xargs --no-run-if-empty docker container inspect --format '{{.Image}}' | sort -u
    }
    removed=0
    for id in $(comm -23 <(docker image ls --all --quiet --no-trunc | sort -u) <(sort -u <(kept image) <(in_use))); do
      older_than_cutoff image "$id" || continue
      read -ra refs <<< "$(docker image inspect --format '{{join .RepoTags " "}}' "$id")"
      [ "''${#refs[@]}" -gt 0 ] || refs=("$id")
      docker image rm "''${refs[@]}" >/dev/null 2>&1 && removed=$((removed + 1))
    done
    echo "removed $removed images"

    # A pause that re-commits an orb under the same snapshot tag leaves the
    # previous snapshot untagged; those go with the rest. Tagged snapshots no
    # orb uses go only on --drop-orb-snapshots.
    orb_images=(--filter "label=$orb_label" --filter "until=$until")
    docker image prune --force "''${orb_images[@]}" >/dev/null
    if [ "$drop_orb_snapshots" = 1 ]; then
      docker image prune --all --force "''${orb_images[@]}" >/dev/null
    fi

    # Cua's per-tree networks carry ai.cua.home (not ai.cua.managed), and a
    # stopped Space cannot start again once its network is gone.
    docker network prune --force --filter "until=$until" --filter "label!=ai.cua.home" >/dev/null
    docker builder prune --all --force --filter "until=$until" >/dev/null
  '';
}
