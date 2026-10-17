#!/usr/bin/env bash
#
# Reuse what heavy_base builds when its inputs have not changed. Used only when HEAVY_CACHE is
# set (core/heavyfs/Makefile); with it unset the build is exactly what it always was.
#
# Why: CPython 3.12 with PGO takes several minutes inside heavy_base on every build, while its
# inputs -- the version, the recipe, and the libraries it links against -- move only on a bump or
# an update of one of those packages.
#
#   heavy-cache.sh cpython-mark    <rootdir>
#   heavy-cache.sh cpython-restore <rootdir> <cache> <python-version> <recipe>
#   heavy-cache.sh cpython-store   <rootdir> <cache> <python-version> <recipe>
#
# cpython-mark lists /usr/local before python is restored or built, so cpython-store can save
# exactly what the build added -- including anything a failed restore left behind. cpython-restore exits non-zero on any miss, which is how it tells the Makefile
# to build instead; nothing here is fatal to the build. Routine misses go to stdout, anything
# unexpected (an archive that does not unpack, a python that does not start) to stderr, so a bad
# entry does not quietly turn into a rebuild on every run.
#
# The cache is local to the build node and written by one job at a time, so entries are written
# to a temporary name and renamed, and only the newest entry is kept.
set -uo pipefail
export LC_ALL=C

SCHEMA=1
MARK=tmp/.cpython-before

# The key: everything that decides what the build produces. That is the python version and the
# recipe, the compiler and libc headers, and the package that owns each shared library the
# python links against. The sonames come from the entry itself (<entry>.sonames, read off the
# built binaries by cpython-store), so a library update misses the cache without hard-coding the
# list here.
cpython_key() { # <rootdir> <sonames-file> <python-version> <recipe>
    local root=$1 sonames=$2 out libs=() so
    out=$(mktemp) || return 1
    while read -r so; do libs+=("/usr/lib64/$so"); done < "$sonames"
    { echo "schema $SCHEMA"; echo "version $3"; echo "recipe $4"; } > "$out"
    if ! chroot "$root" rpm -q --qf '%{NEVRA}\n' gcc glibc-devel >> "$out" ||
       ! chroot "$root" rpm -qf --qf '%{NEVRA}\n' "${libs[@]}" >> "$out"; then
        rm -f "$out"
        return 1
    fi
    sha256sum < "$out" | cut -c1-16
    rm -f "$out"
}

cpython_mark() { # <rootdir>
    (cd "$1" && find usr/local | sort) > "$1/$MARK"
}

cpython_restore() { # <rootdir> <cache> <python-version> <recipe>
    local root=$1 cache=$2 ver=$3 recipe=$4 sonames key entry
    for sonames in "$cache/cpython-v$SCHEMA-"*.sonames; do
        [ -f "$sonames" ] || continue
        key=$(cpython_key "$root" "$sonames" "$ver" "$recipe") || continue
        entry=$cache/cpython-v$SCHEMA-$key
        [ "$sonames" = "$entry.sonames" ] && [ -f "$entry.tar.zst" ] || continue
        if ! zstd -dcq "$entry.tar.zst" | tar -xpf - -C "$root"; then
            echo "ERROR: cannot unpack $entry.tar.zst -- building python instead" >&2
            return 1
        fi
        if ! chroot "$root" "/usr/local/bin/python${ver%.*}" -c 'import ssl, sqlite3, ctypes'; then
            echo "ERROR: python from $entry.tar.zst does not start -- building python instead" >&2
            return 1
        fi
        rm -f "$root/$MARK"
        echo "    restored $entry.tar.zst"
        return 0
    done
    echo "    no python $ver for these inputs in $cache -- building it"
    return 1
}

cpython_store() { # <rootdir> <cache> <python-version> <recipe>
    local root=$1 cache=$2 ver=$3 recipe=$4 list sonames key entry p so old
    list=$(mktemp) && sonames=$(mktemp) || return 1
    trap 'rm -f "$list" "$sonames" "$root/$MARK"' RETURN
    [ -f "$root/$MARK" ] || { echo "ERROR: no $MARK in $root -- not saving python" >&2; return 1; }
    (cd "$root" && find usr/local | sort | comm -13 "$MARK" -) > "$list"
    # NEEDED of every ELF python installed; libraries python ships itself are not in /usr/lib64
    while read -r p; do
        [ -f "$root/$p" ] && [ ! -L "$root/$p" ] && readelf -d "$root/$p" 2>/dev/null
    done < "$list" | sed -n 's/.*(NEEDED).*\[\(.*\)\]$/\1/p' | sort -u |
        while read -r so; do [ -e "$root/usr/lib64/$so" ] && echo "$so"; done > "$sonames"
    [ -s "$sonames" ] || { echo "ERROR: python links against nothing in /usr/lib64 -- not saving it" >&2; return 1; }
    key=$(cpython_key "$root" "$sonames" "$ver" "$recipe") || { echo "ERROR: no cache key -- not saving python" >&2; return 1; }
    entry=$cache/cpython-v$SCHEMA-$key
    mkdir -p "$cache" || return 1
    if ! tar --no-recursion --numeric-owner -C "$root" -cf - -T "$list" | zstd -q -T0 -o "$entry.tar.zst.tmp"; then
        echo "ERROR: cannot write $entry.tar.zst -- not saving python" >&2
        rm -f "$entry.tar.zst.tmp"
        return 1
    fi
    cp "$sonames" "$entry.sonames.tmp" && mv -f "$entry.tar.zst.tmp" "$entry.tar.zst" &&
        mv -f "$entry.sonames.tmp" "$entry.sonames" || return 1
    for old in "$cache"/cpython-v*; do
        case $old in "$entry".*) ;; *) rm -f "$old" ;; esac
    done
    echo "    saved $entry.tar.zst ($(du -h "$entry.tar.zst" | cut -f1), $(wc -l < "$list") paths)"
}

cmd=${1:-}
shift || true
case $cmd in
    cpython-mark)    cpython_mark "$@" ;;
    cpython-restore) cpython_restore "$@" ;;
    cpython-store)   cpython_store "$@" ;;
    *) echo "usage: $0 cpython-mark|cpython-restore|cpython-store ..." >&2; exit 2 ;;
esac
