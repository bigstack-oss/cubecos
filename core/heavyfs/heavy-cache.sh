#!/usr/bin/env bash
#
# Reuse what heavy_base builds when its inputs have not changed. Used only when HEAVY_CACHE is
# set (core/heavyfs/Makefile); with it unset the build is exactly what it always was.
#
# Why: CPython 3.12 with PGO takes several minutes inside heavy_base on every build, while its
# inputs -- the version, the recipe, and the libraries it links against -- move only on a bump or
# an update of one of those packages. The same holds for the l1 part of heavy_base (accounts,
# repos, every dnf install and the pip installs before python 3.12): it moves when the repos
# publish an update to something it installed, or when its makefiles or scripts change.
#
#   heavy-cache.sh cpython-mark    <rootdir>
#   heavy-cache.sh cpython-restore <rootdir> <cache> <python-version> <recipe>
#   heavy-cache.sh cpython-store   <rootdir> <cache> <python-version> <recipe>
#   heavy-cache.sh l1-key          <srcdir> <make command> <dir>...
#   heavy-cache.sh l1-restore      <blddir> <cache> <key>
#   heavy-cache.sh l1-store        <blddir> <cache> <key>
#   heavy-cache.sh l1-clean        <blddir>
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

# What the l1 part leaves behind, relative to the build directory. installdnf and installpip
# download into RPMS and PIPS and keep what they find there (hex scripts/installdnf: a file
# already in RPMS is not downloaded again, and localinstall installs the whole directory), so
# the rest part needs them as l1 left them. The .before files are the l1 accounts, which
# core/main compares the final ones with.
L1_PATHS="core/heavyfs/heavy_l1 core/heavyfs/RPMS core/heavyfs/PIPS core/heavyfs/ARCS
core/main/passwd.before core/main/shadow.before core/main/group.before core/main/gshadow.before"
L1_ROOT=core/heavyfs/heavy_l1
L1_STAGE=core/heavyfs/.heavy_l1.restore
# pip installs that the constraints file leaves unpinned follow PyPI, which dnf check-update
# cannot see; an entry older than this is not used, which bounds how far they can drift
L1_MAX_DAYS=7

# Unmount whatever is mounted under <dir>, deepest first, so it can be archived or removed.
unmount_under() { # <dir>
    awk -v d="$1/" 'index($2, d) == 1 { print $2 }' /proc/mounts | sort -r |
        while read -r m; do umount -l "$m"; done
}

# The key: the commands the l1 pass runs (make -n, with ROOTDIR an empty scratch root), what
# its makefiles write into that root while they are read (the lock lists, the repo files),
# the makefiles it reads, every file under <srcdir> those commands name, and every file in
# each <dir> (the hex scripts, which source each other). Comment lines are dropped from the
# makefiles, as configure writes its date into build.mk. A path under <srcdir> that the
# commands name and that does not exist means this cannot see what the pass reads: no key.
l1_key() { # <srcdir> <make command> <dir>...
    local src=$1 cmd=$2 box f
    shift 2
    box=$(mktemp -d) || return 1
    trap 'rm -rf "${box:?}"' RETURN
    mkdir -p "$box/root/etc/yum.repos.d" "$box/list/etc/yum.repos.d"
    if ! eval "${cmd//@ROOTDIR@/$box/root} -n rootfs_install" > "$box/cmds" 2> "$box/err" ||
       ! eval "${cmd//@ROOTDIR@/$box/list} -s heavy_l1_makefiles" > "$box/makefiles" 2>> "$box/err"; then
        echo "ERROR: make -n of the l1 pass failed -- no l1 cache" >&2
        tail -5 "$box/err" >&2
        return 1
    fi
    sed "s,$box/root,@ROOTDIR@,g" "$box/cmds" > "$box/cmds.n"
    grep -o "${src//./\\.}/[^][ '\"\\;|&<>(){}=:,*?]*" "$box/cmds.n" | sed 's,/*$,,' | sort -u > "$box/named"
    {
        echo "schema $SCHEMA"
        cat "$box/cmds.n"
        (cd "$box/root" && find . -type f | sort | xargs -r sha256sum)
        for f in $(cat "$box/makefiles"); do
            echo "$(grep -v '^[[:space:]]*#' "$f" | sha256sum | cut -d' ' -f1)  $f"
        done
        while read -r f; do
            if [ -f "$f" ]; then
                sha256sum "$f"
            elif [ -d "$f" ]; then
                find "$f" -type f | sort | xargs -r sha256sum
            else
                echo "missing $f"
            fi
        done < "$box/named"
        for f in "$@"; do find "$f" -type f | sort | xargs -r sha256sum; done
    } > "$box/inputs"
    if grep -q '^missing ' "$box/inputs"; then
        echo "ERROR: the l1 pass names $(grep -m1 '^missing ' "$box/inputs" | cut -d' ' -f2-), which does not exist -- no l1 cache" >&2
        return 1
    fi
    f=$(sha256sum < "$box/inputs" | cut -c1-16)
    # kept, and saved beside the entry, so that a miss can say which input moved
    cp "$box/inputs" "${TMPDIR:-/tmp}/heavy-l1-$f.inputs"
    echo "$f"
}

# What dnf would update in <rootdir>, one "name.arch version repo" per line. A name too long
# for its column is printed on a line of its own, followed by the version and the repo.
l1_updates() { # <rootdir>
    local root=$1 out rc dns=
    out=$(mktemp) || return 1
    if [ ! -e "$root/etc/resolv.conf" ] && [ ! -L "$root/etc/resolv.conf" ]; then
        cp -f /etc/resolv.conf "$root/etc/" && dns=1
    fi
    # In a mount namespace of its own, like heavy_base (heavyfs/Makefile): this can run while
    # hex's mountrootfs runs, whose `umount proc` takes the most recently mounted proc. The
    # proc goes away with the namespace.
    unshare -m --propagation private sh -c 'mount -t proc proc "$1/proc"; chroot "$1" dnf -y check-update --refresh' sh "$root" > "$out" 2>&1
    rc=$?
    [ -z "$dns" ] || rm -f "${root:?}/etc/resolv.conf"
    if [ $rc -ne 0 ] && [ $rc -ne 100 ]; then
        echo "ERROR: dnf check-update exited $rc:" >&2
        tail -5 "$out" >&2
        rm -f "${out:?}"
        return 1
    fi
    awk 'NF == 1 && $1 ~ /\./ { name = $1; next }
         NF == 2 && name != "" { $0 = name " " $0 }
         { name = "" }
         NF == 3 && $1 ~ /\./ && $3 !~ /^@/ { print $1, $2, $3 }' "$out" | sort -u
    rm -f "${out:?}"
}

l1_clean() { # <blddir>
    local bld=${1:?} d
    for d in "$L1_ROOT" "$L1_STAGE"; do
        unmount_under "$bld/$d"
        rm -rf "${bld:?}/${d:?}"
    done
}

# The entry is used when the repos would update exactly what they would have updated when it
# was saved: dnf check-update lists the same packages at the same versions. Anything published
# since for a package the l1 part installed shows up in that list.
l1_restore() { # <blddir> <cache> <key>
    local bld=${1:?} cache=${2:?} key=${3:?} entry other p updates
    entry=$cache/l1-v$SCHEMA-$key
    updates=$bld/$L1_STAGE.updates
    if [ ! -f "$entry.tar.zst" ] || [ ! -f "$entry.updates" ]; then
        echo "    no l1 snapshot for these inputs in $cache -- building it"
        for other in "$cache"/l1-v$SCHEMA-*.inputs; do
            [ -f "$other" ] && [ -f "${TMPDIR:-/tmp}/heavy-l1-$key.inputs" ] || continue
            echo "    inputs that differ from ${other##*/}:"
            diff "$other" "${TMPDIR:-/tmp}/heavy-l1-$key.inputs" | grep '^[<>]' | head -10 | sed 's/^/      /'
        done
        return 1
    fi
    if [ -n "$(find "$entry.tar.zst" -mtime +$((L1_MAX_DAYS - 1)))" ]; then
        echo "    l1 snapshot $entry.tar.zst is over $L1_MAX_DAYS days old -- building it"
        return 1
    fi
    l1_clean "$bld"
    mkdir -p "$bld/$L1_STAGE"
    if ! zstd -dcq "$entry.tar.zst" | tar -xpf - -C "$bld/$L1_STAGE"; then
        echo "ERROR: cannot unpack $entry.tar.zst -- building l1 instead" >&2
        l1_clean "$bld"
        return 1
    fi
    if ! l1_updates "$bld/$L1_STAGE/$L1_ROOT" > "$updates"; then
        echo "ERROR: cannot check $entry.tar.zst against the repos -- building l1 instead" >&2
        rm -f "${updates:?}"
        l1_clean "$bld"
        return 1
    fi
    if ! cmp -s "$entry.updates" "$updates"; then
        echo "    the repos have moved since $entry.tar.zst ($(diff "$entry.updates" "$updates" | grep -c '^[<>]') lines of dnf check-update differ) -- building l1"
        diff "$entry.updates" "$updates" | grep '^[<>]' | head -10 | sed 's/^/      /'
        rm -f "${updates:?}"
        l1_clean "$bld"
        return 1
    fi
    rm -f "${updates:?}"
    for p in $L1_PATHS; do rm -rf "${bld:?}/${p:?}"; done
    # the stage is on the build directory's filesystem, so this links rather than copies
    if ! cp -alf "$bld/$L1_STAGE/." "$bld/"; then
        echo "ERROR: cannot move $entry.tar.zst into $bld -- building l1 instead" >&2
        for p in $L1_PATHS; do rm -rf "${bld:?}/${p:?}"; done
        l1_clean "$bld"
        return 1
    fi
    rm -rf "${bld:?}/${L1_STAGE:?}"
    echo "    restored $entry.tar.zst"
}

l1_store() { # <blddir> <cache> <key>
    local bld=${1:?} cache=${2:?} key=${3:?} entry old
    entry=$cache/l1-v$SCHEMA-$key
    mkdir -p "$cache" || return 1
    unmount_under "$bld/$L1_ROOT"
    if ! l1_updates "$bld/$L1_ROOT" > "$entry.updates.tmp"; then
        echo "ERROR: cannot list what dnf would update in $L1_ROOT -- not saving it" >&2
        rm -f "${entry:?}.updates.tmp"
        return 1
    fi
    # shellcheck disable=SC2086 # L1_PATHS is a word list
    if ! tar --numeric-owner --one-file-system -C "$bld" -cf - $L1_PATHS | zstd -q -T0 -o "$entry.tar.zst.tmp"; then
        echo "ERROR: cannot write $entry.tar.zst -- not saving l1" >&2
        rm -f "${entry:?}.tar.zst.tmp" "${entry:?}.updates.tmp"
        return 1
    fi
    cp "${TMPDIR:-/tmp}/heavy-l1-$key.inputs" "$entry.inputs.tmp" 2>/dev/null || : > "$entry.inputs.tmp"
    mv -f "$entry.tar.zst.tmp" "$entry.tar.zst" && mv -f "$entry.updates.tmp" "$entry.updates" &&
        mv -f "$entry.inputs.tmp" "$entry.inputs" || return 1
    for old in "$cache"/l1-v*; do
        case $old in "$entry".*) ;; *) rm -f "${old:?}" ;; esac
    done
    echo "    saved $entry.tar.zst ($(du -h "$entry.tar.zst" | cut -f1), $(wc -l < "$entry.updates") pending updates)"
}

cmd=${1:-}
shift || true
case $cmd in
    cpython-mark)    cpython_mark "$@" ;;
    cpython-restore) cpython_restore "$@" ;;
    cpython-store)   cpython_store "$@" ;;
    l1-key)          l1_key "$@" ;;
    l1-restore)      l1_restore "$@" ;;
    l1-store)        l1_store "$@" ;;
    l1-clean)        l1_clean "$@" ;;
    *) echo "usage: $0 cpython-mark|cpython-restore|cpython-store|l1-key|l1-restore|l1-store|l1-clean ..." >&2; exit 2 ;;
esac
