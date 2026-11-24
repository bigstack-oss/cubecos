#!/bin/bash
#
# Unit test for ceph_tier_releases and ceph_mds_tier_mixed in ../modules/sdk_ceph.sh.
#
# Both read release names out of ceph version strings. Tentacle appends the build type
# to them (`tentacle (stable - RelWithDebInfo)`), so a squid -> tentacle roll reports
# both forms in one `ceph versions`. Each tier has to come out as its release names,
# and the MDS tier has to read as mixed while squid and tentacle MDS daemons coexist,
# including when the only tentacle one is this node's own, not yet registered binary.
#
# Self-contained: extracts only the functions and stubs ceph and ceph-mds, so it needs no
# cluster.  Run: bash test_ceph_tier_releases.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SDK_CEPH_SRC:-$DIR/../modules/sdk_ceph.sh}"

for f in _ceph_release_name ceph_tier_releases ceph_mds_tier_mixed ; do
    fn="$(awk -v f="$f" '$0 ~ "^"f"\\(\\)" {p=1} p{print} p&&/^}/{exit}' "$SRC")"
    eval "$fn"
done
for f in ceph_tier_releases ceph_mds_tier_mixed ; do
    type $f >/dev/null 2>&1 || { echo "FAIL: $f not extracted"; exit 1; }
done

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ----------------------------------------------------------------
# VERSIONS is what `ceph versions -f json` prints; MINE is what this node's
# `ceph-mds --version` prints.
SQ='ceph version 19.2.7 (5d4ee0fb6a4c3e28c3b0f1b2a6c6e0b9e1f2a3b4) squid (stable)'
TE='ceph version 20.2.5 (0123456789abcdef0123456789abcdef01234567) tentacle (stable - RelWithDebInfo)'
VERSIONS='{}' MINE=''
CEPH=ceph_stub
ceph_stub() { [ "$1" = versions ] && echo "$VERSIONS"; }
ceph-mds() { echo "$MINE"; }
tier() { ceph_tier_releases "$1" | tr '\n' ' ' | sed 's/ $//'; }
mixed() { ceph_mds_tier_mixed && echo mixed || echo uniform; }

# ---- 1: squid only, the 3.2.0 cluster ----------------------------------------
VERSIONS="{\"mon\":{\"$SQ\":3},\"osd\":{\"$SQ\":24},\"mds\":{\"$SQ\":3}}" MINE="$SQ"
chk "1 mon" "$(tier mon)" squid
chk "1 osd" "$(tier osd)" squid
chk "1 mds uniform" "$(mixed)" uniform

# ---- 2: tentacle only, a fresh install or a finished roll --------------------
VERSIONS="{\"mon\":{\"$TE\":3},\"osd\":{\"$TE\":24},\"mds\":{\"$TE\":3}}" MINE="$TE"
chk "2 mon" "$(tier mon)" tentacle
chk "2 osd" "$(tier osd)" tentacle
chk "2 mds uniform" "$(mixed)" uniform

# ---- 3: mid-roll, both releases in every tier --------------------------------
VERSIONS="{\"mon\":{\"$SQ\":2,\"$TE\":1},\"osd\":{\"$SQ\":16,\"$TE\":8},\"mds\":{\"$SQ\":2,\"$TE\":1}}" MINE="$TE"
chk "3 mon" "$(tier mon)" "squid tentacle"
chk "3 osd" "$(tier osd)" "squid tentacle"
chk "3 mds mixed" "$(mixed)" mixed

# ---- 4: first node into tentacle, its MDS not registered yet ----------------
VERSIONS="{\"mds\":{\"$SQ\":2}}" MINE="$TE"
chk "4 mds mixed by own binary" "$(mixed)" mixed

# ---- 5: no cluster answers ---------------------------------------------------
VERSIONS='' MINE=''
chk "5 osd empty" "$(tier osd)" ""
chk "5 mds uniform" "$(mixed)" uniform

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
