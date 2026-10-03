#!/bin/bash
#
# Unit test for ceph_osd_memory_targets / ceph_osd_memory_target_apply in
# ../modules/sdk_ceph.sh: each local OSD gets a fifth of host RAM split across the
# local OSDs, clamped to [2G, 4G] on rotational and 4G on flash devices, and only
# changed targets are written to the mon config db.
#
# Self-contained: extracts the two functions, fakes the OSD directories,
# /proc/meminfo, lsblk and ceph, so it needs no cluster.
#   Run: bash test_ceph_osd_memory_targets.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_ceph.sh"
for f in ceph_osd_memory_targets ceph_osd_memory_target_apply ; do
    eval "$(awk -v n="^$f\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ "$(type -t "$f")" = function ] || { echo "FAIL: $f not extracted"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CEPH_OSD_DIR=$TMP/osd
PROC_MEMINFO=$TMP/meminfo
G=1073741824

# lsblk -dno ROTA <dev>: rot* rotational, unk* unreadable, anything else flash
lsblk() {
    case "$(basename "${!#}")" in
        rot*) echo "   1" ;;
        unk*) return 1 ;;
        *) echo "   0" ;;
    esac
}

# mk_osd <id> <device name>: an OSD dir whose block points at $TMP/dev/<name>
mk_osd() {
    mkdir -p "$CEPH_OSD_DIR/ceph-$1" "$TMP/dev"
    touch "$TMP/dev/$2"
    ln -sf "$TMP/dev/$2" "$CEPH_OSD_DIR/ceph-$1/block"
}

set_mem_gib() {
    echo "MemTotal:       $(( $1 * 1048576 )) kB" > "$PROC_MEMINFO"
}

reset() {
    rm -rf "$CEPH_OSD_DIR" "$TMP/dev"
    mkdir -p "$CEPH_OSD_DIR"
}

FAILS=0
check() {
    if [ "$2" = "$3" ] ; then
        echo "ok   $1"
    else
        echo "FAIL $1"
        echo "     want: $(echo "$3" | tr '\n' '|')"
        echo "     got:  $(echo "$2" | tr '\n' '|')"
        FAILS=$((FAILS + 1))
    fi
}

# no OSD mounted: prints nothing, so nova falls back to its disk-size estimate
reset ; set_mem_gib 256
check "no osds prints nothing" "$(ceph_osd_memory_targets)" ""

# a dir without a block link (unmounted raw OSD) is not counted
reset ; set_mem_gib 64 ; mkdir -p "$CEPH_OSD_DIR/ceph-9" ; mk_osd 1 rota
check "unmounted dir skipped" "$(ceph_osd_memory_targets)" "1 hdd $((4 * G))"

# 256 GiB, 10 hdd osds: 51.2 GiB / 10 = 5.1 GiB, capped at 4 GiB
reset ; set_mem_gib 256
for i in $(seq 0 9) ; do mk_osd $i rot$i ; done
check "large node caps at 4G" "$(ceph_osd_memory_targets | awk '{print $3}' | sort -u)" "$((4 * G))"

# 128 GiB, 20 hdd osds: 25.6 GiB / 20 = 1.28 GiB, floored at 2 GiB
reset ; set_mem_gib 128
for i in $(seq 0 19) ; do mk_osd $i rot$i ; done
check "dense hdd node floors at 2G" "$(ceph_osd_memory_targets | awk '{print $3}' | sort -u)" "$((2 * G))"

# 160 GiB, 12 hdd osds: 32 GiB / 12 = 2.67 GiB, in range
reset ; set_mem_gib 160
for i in $(seq 0 11) ; do mk_osd $i rot$i ; done
check "hdd in range" "$(ceph_osd_memory_targets | awk '{print $3}' | sort -u)" "$((160 * G / 5 / 12))"

# mixed: flash osds keep 4 GiB while hdd ones share; unknown ROTA counts as hdd
reset ; set_mem_gib 64
mk_osd 0 rot0 ; mk_osd 1 nvme0 ; mk_osd 2 rot1 ; mk_osd 3 unk0
check "mixed classes" "$(ceph_osd_memory_targets | sort -n)" "0 hdd $((64 * G / 5 / 4))
1 ssd $((4 * G))
2 hdd $((64 * G / 5 / 4))
3 hdd $((64 * G / 5 / 4))"

# a dangling block link (LVM OSD not activated) is not counted
reset ; set_mem_gib 64
mk_osd 0 rot0 ; mk_osd 1 rot1 ; ln -sf "$TMP/dev/missing" "$CEPH_OSD_DIR/ceph-1/block"
check "dangling block skipped" "$(ceph_osd_memory_targets)" "0 hdd $((4 * G))"

# apply: sets only the targets that differ, skips everything without quorum
reset ; set_mem_gib 128
for i in $(seq 0 19) ; do mk_osd $i rot$i ; done
QUORUM=1
TRACE=$TMP/trace
: > "$TRACE"
ceph() {
    case "$*" in
        -s) [ $QUORUM -eq 1 ] ;;
        'config get osd.3 osd_memory_target') echo $((2 * G)) ;;
        'config get '*) echo $((4 * G)) ;;
        'config set '*) echo "$*" >> "$TRACE" ;;
    esac
}
CEPH=ceph
log_warning() { :; }
ceph_osd_memory_target_apply
check "apply sets the 19 that differ" "$(wc -l < "$TRACE")" "19"
check "apply skips the one already set" "$(grep -c 'osd\.3 ' "$TRACE")" "0"
check "apply writes the floor" "$(awk '{print $5}' "$TRACE" | sort -u)" "$((2 * G))"

QUORUM=0
: > "$TRACE"
ceph_osd_memory_target_apply
check "apply is a no-op without quorum" "$(wc -l < "$TRACE")" "0"

[ $FAILS -eq 0 ] && echo "PASS" || { echo "$FAILS failure(s)"; exit 1; }
