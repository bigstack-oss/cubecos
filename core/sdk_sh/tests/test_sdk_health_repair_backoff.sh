#!/bin/bash
#
# Unit test for _health_repair_due() in ../modules/sdk_health.sh -- the maxerr
# backoff gate: auto_repair runs every round below maxerr, then backs off to
# every Nth round instead of giving up forever (so a service whose dependency
# later recovers still gets fixed).
#
# Self-contained: extracts ONLY the predicate, so it needs none of
# sdk_health.sh's runtime prerequisites (PROG / SDK_DIR / errcodes).
# Run:  bash test_sdk_health_repair_backoff.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_health.sh"

fn="$(awk '/^_health_repair_due\(\)/{f=1} f{print} f&&/^}/{exit}' "$SRC")"
[ -n "$fn" ] || { echo "FAIL: _health_repair_due not found in $SRC"; exit 1; }
eval "$fn"

pass=0 fail=0
# assert <want: due|no> <count> <maxerr> <backoff>
assert() {
    local want=$1 count=$2 maxerr=$3 backoff=$4 got
    if _health_repair_due "$count" "$maxerr" "$backoff"; then got=due; else got=no; fi
    if [ "$got" = "$want" ]; then pass=$((pass+1))
    else fail=$((fail+1)); echo "FAIL: count=$count maxerr=$maxerr backoff=$backoff -> $got (want $want)"; fi
}

# maxerr=6 backoff=10: repair every round below 6, then only rounds 6,16,26,...
for c in 0 1 2 3 4 5; do assert due "$c" 6 10; done          # below maxerr: always repair
assert due 6 6 10                                            # at maxerr: retry (not give up)
for c in 7 8 9 10 11 12 13 14 15; do assert no "$c" 6 10; done  # cooldown: skip
assert due 16 6 10                                          # +backoff: retry
for c in 17 18 25; do assert no "$c" 6 10; done
assert due 26 6 10                                         # +2*backoff: retry

# tunable knobs: maxerr=6 backoff=3 -> retry at 6,9,12; skip 7,8,10,11
assert due 6 6 3; assert no 7 6 3; assert no 8 6 3; assert due 9 6 3; assert no 10 6 3; assert due 12 6 3

# key property: never a permanent give-up -- some round in any window is due
found=no
for c in $(seq 100 109); do _health_repair_due "$c" 6 10 && { found=yes; break; }; done
if [ "$found" = yes ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: permanent give-up (no retry in 10 rounds past maxerr)"; fi

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: _health_repair_due"; exit 0; } || exit 1
