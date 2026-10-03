#!/usr/bin/env bash
# Build the Cua Bots Mac app with the host-placement patch, so a bot's
# computer can run on one of your machines that provides Spaces (bali,
# github-runner-03/04/05, fu137; see docs/cua-bots-fleet.md), not only on
# this Mac or in Cua Cloud.
#
# macOS only (SwiftUI). Needs Xcode or the Command Line Tools and rustup
# (installed by users/joost/home-manager.nix). Re-running updates in place.
#
#   scripts/build-cua-bots.sh            # build
#   scripts/build-cua-bots.sh --run      # build, then start the app
set -euo pipefail

# The upstream commit patches/cua-bots-host-placement.patch was made against.
# Bump both together: upstream ships several releases a day.
CUA_REV="66e0b6652fc4a89318e84955e71760646fc52350"
SRC="${CUA_BOTS_SRC:-$HOME/src/cua}"
PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/patches/cua-bots-host-placement.patch"

[ "$(uname -s)" = Darwin ] || { echo "Cua Bots is a macOS app; run this on the Mac" >&2; exit 1; }

if [ ! -d "$SRC/.git" ]; then
  git clone --filter=blob:none https://github.com/trycua/cua "$SRC"
fi
git -C "$SRC" fetch --quiet origin "$CUA_REV"
# A dedicated build clone: --force drops the previous run's patch (and any
# other local edit) so the patch always applies to a clean tree.
git -C "$SRC" checkout --quiet --force --detach "$CUA_REV"
git -C "$SRC" apply "$PATCH"

command -v cargo >/dev/null || rustup default stable
(cd "$SRC/libs/cua" && cargo build --locked --release -p cua-spaces-ffi)
"$SRC/libs/spaces-app-swift/scripts/stage-library.sh"
(cd "$SRC/samples/cua-bots-macos" && swift build -c release)

app="$SRC/samples/cua-bots-macos/.build/release/CuaBots"
echo "built $app"
if [ "${1:-}" = "--run" ]; then
  exec "$app"
fi
