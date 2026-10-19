#!/usr/bin/env bash
#
# Print the build cache key for a k3s binary: <version>-<first 12 hex of a sha256>.
#
# The key has to change whenever anything that changes the binary does, not only the version. Before
# this, the cache was keyed by VERSION alone, so a new Go toolchain in Dockerfile.dapper or a new
# step in the source recipe would restore the old binary from the cache and never be built.
#
# Hashed, besides the version:
#   - every file in this directory except this script (Dockerfile.dapper today; any patch file
#     added here later is covered without editing this list)
#   - the K3S_REPO and K3S_GO_* lines and the recipes that fetch dapper, clone the source and
#     build it, as written in core/k3s/Makefile. Other targets in that Makefile do not touch the
#     binary and are left out, so editing them does not force an 81-minute source build.
#
# The upgrade ladder's releases (LADDER_VERSIONS) are built with that same recipe, so each one's
# key hashes the same inputs and differs only in its version: a toolchain or pin change moves
# every key at once.
#
# Read by core/k3s/build/fetch-or-build.sh to find a cached binary, and by triangle's
# cube_publish_artifacts job to upload them, so both sides agree on the path.
#
#   ./cache-key.sh                  -> v1.32.13+k3s1-0123456789ab              (VERSION)
#   ./cache-key.sh v1.27.16+k3s1    -> v1.27.16+k3s1-0123456789ab              (a ladder release)
#   ./cache-key.sh --list           -> one "<key> <path>" line per binary the build makes, the
#                                      path relative to core/k3s: "... k3s", "... ladder/<v>/k3s"
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
MK="$DIR/../Makefile"

mkvar() {
    awk -v name="$1" '$1 == name && $2 == ":=" { $1 = $2 = ""; sub(/^ +/, ""); print; exit }' "$MK"
}

VERSION=$(mkvar VERSION)
LADDER_VERSIONS=$(mkvar LADDER_VERSIONS)
LADDER_DIR=$(mkvar LADDER_DIR)
[ -n "$VERSION" ] || { echo "cache-key.sh: no VERSION in $MK" >&2; exit 1; }

# A rule block runs from its target line to the next blank line.
recipes() {
    awk '
        /^(K3S_REPO|K3S_GO_[A-Z]+)[[:space:]]*:=/          { print; next }
        /^(\.dapper|\$\(K3S_SRC_DIR\)|\$\(BIN\)-from-source):/ { inblk = 1 }
        inblk && /^[[:space:]]*$/                          { inblk = 0 }
        inblk                                              { print }
    ' "$MK"
}

inputs() {
    echo "version $1"
    recipes
    (cd "$DIR" && find . -type f ! -name cache-key.sh | LC_ALL=C sort | xargs sha256sum)
}

# A renamed target would silently drop out of the hash; refuse rather than key on less.
heads=$(recipes | grep -c -E '^(K3S_REPO|\.dapper:|\$\(K3S_SRC_DIR\):|\$\(BIN\)-from-source:)' || true)
[ "$heads" -eq 4 ] || { echo "cache-key.sh: expected 4 k3s recipe anchors in $MK, found $heads" >&2; exit 1; }

key() {
    echo "$1-$(inputs "$1" | sha256sum | cut -c1-12)"
}

case "${1:-}" in
    "")
        key "$VERSION" ;;
    --list)
        echo "$(key "$VERSION") k3s"
        for v in $LADDER_VERSIONS; do
            echo "$(key "$v") $LADDER_DIR/$v/k3s"
        done ;;
    *)
        # Only versions this Makefile builds: anything else has no recipe behind its key.
        for v in $VERSION $LADDER_VERSIONS; do
            [ "$1" = "$v" ] && { key "$v"; exit 0; }
        done
        echo "cache-key.sh: $1 is neither VERSION nor in LADDER_VERSIONS in $MK" >&2
        exit 1 ;;
esac
