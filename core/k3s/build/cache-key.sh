#!/usr/bin/env bash
#
# Print the build cache key for the k3s binary: <VERSION>-<first 12 hex of a sha256>.
#
# The key has to change whenever anything that changes the binary does, not only VERSION. Before
# this, the cache was keyed by VERSION alone, so a new Go toolchain in Dockerfile.dapper or a new
# step in the source recipe would restore the old binary from the cache and never be built.
#
# Hashed, besides VERSION:
#   - every file in this directory except this script (Dockerfile.dapper today; any patch file
#     added here later is covered without editing this list)
#   - the K3S_REPO line and the recipes that fetch dapper, clone the source and build it, as
#     written in core/k3s/Makefile. Other targets in that Makefile do not touch the binary and
#     are left out, so editing them does not force an 81-minute source build.
#
# Read by core/k3s/build/fetch-or-build.sh to find the cached binary, and by triangle's
# cube_publish_artifacts job to upload it, so both sides agree on the path.
#
#   ./cache-key.sh            -> v1.32.13+k3s1-0123456789ab
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
MK="$DIR/../Makefile"

VERSION=$(awk '/^VERSION[[:space:]]*:=/ {print $3; exit}' "$MK")
[ -n "$VERSION" ] || { echo "cache-key.sh: no VERSION in $MK" >&2; exit 1; }

# A rule block runs from its target line to the next blank line.
recipes() {
    awk '
        /^K3S_REPO[[:space:]]*:=/                          { print; next }
        /^(\.dapper|\$\(K3S_SRC_DIR\)|\$\(BIN\)-from-source):/ { inblk = 1 }
        inblk && /^[[:space:]]*$/                          { inblk = 0 }
        inblk                                              { print }
    ' "$MK"
}

inputs() {
    echo "version $VERSION"
    recipes
    (cd "$DIR" && find . -type f ! -name cache-key.sh | LC_ALL=C sort | xargs sha256sum)
}

# A renamed target would silently drop out of the hash; refuse rather than key on less.
heads=$(recipes | grep -c -E '^(K3S_REPO|\.dapper:|\$\(K3S_SRC_DIR\):|\$\(BIN\)-from-source:)' || true)
[ "$heads" -eq 4 ] || { echo "cache-key.sh: expected 4 k3s recipe anchors in $MK, found $heads" >&2; exit 1; }

echo "$VERSION-$(inputs | sha256sum | cut -c1-12)"
