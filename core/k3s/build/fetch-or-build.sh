#!/usr/bin/env bash
#
# Restore the prebuilt k3s binary from a cache, if one is configured and holds this version.
#
# Exits non-zero on any miss, which is how it tells the Makefile to fall back to building from
# source -- see the `|| $(MAKE) k3s-from-source` in core/k3s/Makefile. Nothing here is fatal: an
# unset, unreachable or incomplete cache just means the build does what it always did.
#
# Why bother: the dapper build ("BUILD k3s") took 4876 s -- 81 min -- in cubecos prod #750, the
# single most expensive step in the build, and it reruns every time because the jail container is
# recreated per build. The version only moves on a deliberate bump. It is also the most fragile
# step: prod #146 failed inside it on an Alpine apk fetch (`gcc-14.2.0-r4: IO ERROR`), so not
# running it at all is worth more than the 81 minutes. See cubecos#1350.
#
#   K3S_CACHE=<base-url> VERSION=v1.26.6+k3s1 OUT=/path/to/k3s ./fetch-or-build.sh
#
# Populate it with the cube_publish_artifacts job in triangle.
set -uo pipefail

VERSION=${VERSION:?VERSION is required}
OUT=${OUT:?OUT is required}
CACHE=${K3S_CACHE:-}

if [ -z "$CACHE" ]; then
    echo "K3S_CACHE not set -- building k3s from source"
    exit 1
fi

BASE="$CACHE/k3s/$VERSION"
echo "==> checking cache for k3s $VERSION"

# The checksum first and separately: we built this binary ourselves, so there is no upstream
# digest to fall back on. Without it a truncated download would be installed as a working k3s and
# only surface as a broken cluster much later.
if ! curl -fsSL --retry 3 --max-time 300 "$BASE/k3s.sha256" -o "$OUT.sha256" ; then
    echo "    cache miss (no checksum) -- building from source"
    rm -f "$OUT.sha256"
    exit 1
fi

if ! curl -fsSL --retry 3 --max-time 1800 "$BASE/k3s" -o "$OUT.part" ; then
    echo "    cache miss (no binary) -- building from source"
    rm -f "$OUT.part" "$OUT.sha256"
    exit 1
fi

if ! printf '%s  %s\n' "$(cut -d' ' -f1 < "$OUT.sha256")" "$OUT.part" | sha256sum -c - >/dev/null 2>&1 ; then
    echo "ERROR: cached k3s failed its checksum -- refusing it and building from source" >&2
    sha256sum "$OUT.part" >&2 || true
    echo "expected: $(cut -d' ' -f1 < "$OUT.sha256")" >&2
    rm -f "$OUT.part" "$OUT.sha256"
    exit 1
fi

chmod +x "$OUT.part"

# Cheap sanity check that this is the k3s we asked for, not some other build that happened to be
# uploaded under this path. `k3s --version` prints e.g. "k3s version v1.26.6+k3s1 (...)".
if ! "$OUT.part" --version 2>/dev/null | grep -qF "$VERSION" ; then
    echo "ERROR: cached binary does not report version $VERSION -- building from source" >&2
    "$OUT.part" --version 2>&1 | head -2 >&2 || true
    rm -f "$OUT.part" "$OUT.sha256"
    exit 1
fi

mv "$OUT.part" "$OUT"
rm -f "$OUT.sha256"
echo "==> cache hit: k3s $VERSION restored without a source build"
"$OUT" --version 2>/dev/null | head -1
