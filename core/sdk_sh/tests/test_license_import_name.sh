#!/bin/bash
#
# Unit test for license name handling in ../modules.pre/sdk_license.sh:
#   license_import_list  -- enumerates *.license and derives each name
#   license_import_stage -- extracts an archive to the fixed $LICENSE_STAGE stem
#
# A license name is free text from the portal ("NYCU ADFP3.0"), and it reaches
# the SDK as a filename.  These assertions pin the two ways that used to break:
# a space (word splitting) and a dot (truncation at the first '.').
#
# Self-contained: extracts just those functions, builds real zips, so it needs
# no cluster.  Run: bash test_license_import_name.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules.pre/sdk_license.sh"
eval "$(awk '/^license_import_list\(\)/{f=1} f{print} f&&/^}/{exit}' "$SRC")"
eval "$(awk '/^license_import_stage\(\)/{f=1} f{print} f&&/^}/{exit}' "$SRC")"
eval "$(awk '/^license_import_unstage\(\)/{f=1} f{print} f&&/^}/{exit}' "$SRC")"

grep -q '^license_staged_check()' "$SRC" || { echo "FAIL: license_staged_check missing"; exit 1; }
for f in license_import_list license_import_stage license_import_unstage ; do
    [ "$(type -t $f)" = function ] || { echo "FAIL: $f not extracted"; exit 1; }
done
command -v zip >/dev/null || { echo "SKIP: zip not installed"; exit 0; }

LICENSE_BADSOURCE=2
WORK=$(mktemp -d)
LICENSE_STAGE=$WORK/stage/license_import
mkdir -p "$WORK/stage" "$WORK/store"
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0
ck(){ [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

# build a .license whose members are named after $1, as the portal generates them
mklic(){
    local name=$1 hw=${2:-J2RSMK2}
    local d=$WORK/build; rm -rf "$d"; mkdir -p "$d"
    printf 'license.name=%s\nlicense.type=enterprise\nissue.hardware=%s\nproduct=CubeCOS\n' "$name" "$hw" > "$d/$name.dat"
    head -c 1024 /dev/zero | tr '\0' 'x' > "$d/$name.sig"
    ( cd "$d" && zip -q "$WORK/store/$name.license" "$name.dat" "$name.sig" )
    rm -rf "$d"
}

# ---- license_import_list: every name survives enumeration verbatim ----
mklic 'cube42-lab'
mklic 'NYCU ADFP3.0'
mklic 'NYCU_ADFP3.0'
got=$(license_import_list "$WORK/store" | LC_ALL=C sort | tr '\n' '|')
ck "$got" 'NYCU ADFP3.0|NYCU_ADFP3.0|cube42-lab|' "list keeps spaces and dots"

# ---- license_import_stage: the archive is found and normalized ----
for name in 'cube42-lab' 'NYCU ADFP3.0' 'NYCU_ADFP3.0' 'a b.c d.0' ; do
    [ -f "$WORK/store/$name.license" ] || mklic "$name"
    license_import_unstage
    license_import_stage "$WORK/store" "$name"
    ck "$?" 0 "stage [$name]"
    ck "$([ -f "$LICENSE_STAGE.dat" ] && echo y)" y "staged .dat for [$name]"
    ck "$([ -f "$LICENSE_STAGE.sig" ] && echo y)" y "staged .sig for [$name]"
    ck "$(grep -c "^license.name=$name$" "$LICENSE_STAGE.dat" 2>/dev/null)" 1 "staged .dat is the right license for [$name]"
done

# the stem the peers and hex_config see never carries the name
ck "$(basename "$LICENSE_STAGE")" license_import "staged stem is name-independent"
case "$LICENSE_STAGE" in *[[:space:]]*) ck space nospace "staged stem has no whitespace";; *) pass=$((pass+1));; esac

# ---- members need not match the archive name (a renamed download) ----
mklic 'orig-name'
mv "$WORK/store/orig-name.license" "$WORK/store/renamed by user.license"
license_import_unstage
license_import_stage "$WORK/store" 'renamed by user'
ck "$?" 0 "stage a renamed archive"
ck "$(grep -c '^license.name=orig-name$' "$LICENSE_STAGE.dat" 2>/dev/null)" 1 "members located by extension, not by name"

# ---- refusals ----
license_import_unstage
license_import_stage "$WORK/store" 'no such license'
ck "$?" "$LICENSE_BADSOURCE" "absent archive -> LICENSE_BADSOURCE"

: > "$WORK/store/empty.license"
license_import_stage "$WORK/store" 'empty' 2>/dev/null
ck "$?" "$LICENSE_BADSOURCE" "unreadable archive -> LICENSE_BADSOURCE"

d=$WORK/build; mkdir -p "$d"; echo x > "$d/only.dat"
( cd "$d" && zip -q "$WORK/store/sigless.license" only.dat ); rm -rf "$d"
license_import_stage "$WORK/store" 'sigless'
ck "$?" "$LICENSE_BADSOURCE" "archive without .sig -> LICENSE_BADSOURCE"

# ---- unstage leaves nothing behind ----
license_import_stage "$WORK/store" 'cube42-lab' >/dev/null
license_import_unstage
ck "$(ls "$WORK/stage" | wc -l)" 0 "unstage removes the staged pair"

# the cluster paths must not interpolate $name into a remote path
for fn in license_cluster_import_check license_cluster_import ; do
    body=$(awk -v f="^$fn[(][)]$" '$0 ~ f{s=1} s{print} s&&/^}/{exit}' "$SRC")
    ck "$(printf '%s' "$body" | grep -c 'root@\$node:.*\$name')" 0 "$fn: no \$name in a remote path"
    ck "$(printf '%s' "$body" | grep -c 'printf .%q')" 0 "$fn: no shell-escaped remote path (scp is sftp-backed)"
done
ck "$(grep -c 'root@\$node:\$LICENSE_STAGE' "$SRC")" 4 "peers only ever receive the fixed stem"

# whatever is copied to a peer must be removed from it again
for fn in license_cluster_import_check license_cluster_import ; do
    body=$(awk -v f="^$fn[(][)]$" '$0 ~ f{s=1} s{print} s&&/^}/{exit}' "$SRC")
    ck "$(printf '%s' "$body" | grep -c 'host_remote_run $node $HEX_SDK license_import_unstage')" 1 "$fn: unstages peers"
done

echo "passed=$pass failed=$fail"
[ $fail -eq 0 ]
