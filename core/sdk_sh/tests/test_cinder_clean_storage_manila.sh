#!/bin/bash
#
# Unit test for cinder_clean_storage_manila (#2329): once an external storage
# is deleted, nothing serves <host>@<name>, so its shares stay deleting and its
# share servers cannot be deleted. The function moves only those rows to
# <host>@generic and deletes them through Manila.
#
# The suite runs the real functions and json helpers against a fake Manila in
# which a delete only completes once the row is at <host>@generic, as on a node.
# Run with SRC=<other sdk_cinder.sh> to check a tree without the function.
#
#   Run: bash test_cinder_clean_storage_manila.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC:-$DIR/../modules/sdk_cinder.sh}"

extract() {  # <file> <function>
    local body
    body="$(awk -v n="^$2\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$1")"
    [ -n "$body" ] || return 1
    eval "$body"
    [ "$(type -t "$2")" = function ]
}

for f in cinder_clean_storage_manila _cinder_storage_manila_rows _cinder_manila_set_host ; do
    extract "$SRC" "$f" || { echo "FAIL: $f not extracted"; exit 1; }
done
extract "$DIR/../modules.pre/sdk_json.sh" json_is_array || { echo "FAIL: json_is_array not extracted"; exit 1; }

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CINDER_USER_INPUT_STORAGE_CONF_DIRECTORY="$WORK/backends"
SETTINGS_TXT="$WORK/settings.txt"
HEX_TUN="$WORK/hex_tuning"
echo 'T_manila_enabled="$MANILA_ENABLED"' > "$HEX_TUN"
is_control_node() { [ "$CONTROL" = yes ]; }
_hex_function_ret() { "$@" >/dev/null 2>&1; }  # json_is_array runs jq through it

# --- fake Manila: shares.json / servers.json / types --------------------------
OPENSTACK=openstack_stub
openstack_stub() {
    echo "$*" >> "$WORK/os"
    local id="${*: -1}"
    case "$*" in
        "share list --all-projects -f json") cat "$WORK/shares.json"; return "$LIST_RC" ;;
        "share server list -f json")
            [ ! -f "$WORK/api_down" ] || return 1
            cat "$WORK/servers.json"; return "$LIST_RC" ;;
        "share delete --force --wait "*)
            [ "$SHARE_DELETE" = works ] || return 1
            # deleted when its manila-share exists: no host, or generic
            jq --arg i "$id" 'map(select(.ID != $i or (.Host != null and (.Host | contains("@generic#") | not))))' \
                "$WORK/shares.json" > "$WORK/t" && mv "$WORK/t" "$WORK/shares.json" ;;
        "share server delete --wait "*)
            [ "$SERVER_DELETE" != down ] || touch "$WORK/api_down"
            [ "$SERVER_DELETE" = works ] || return 1
            jq --arg i "$id" 'map(select(.ID != $i or (.Host | endswith("@generic") | not)))' \
                "$WORK/servers.json" > "$WORK/t" && mv "$WORK/t" "$WORK/servers.json" ;;
        "share type show "*) grep -qx "$id" "$WORK/types" ;;
        "share type delete "*) grep -vx "$id" "$WORK/types" > "$WORK/t"; mv "$WORK/t" "$WORK/types" ;;
    esac
}
MYSQL=mysql_stub
mysql_stub() {  # applies the one UPDATE the function sends to the fake rows
    local sql="${*: -1}" file="servers.json"
    echo "$sql" >> "$WORK/sql"
    [ "$MARIADB" = works ] || return 1
    [[ "$sql" == *share_instances* ]] && file="shares.json"
    [[ "$sql" =~ SET\ host=\'([^\']*)\'\ WHERE\ [a-z_]*id=\'([^\']*)\'\ AND\ host=\'([^\']*)\'\ AND\ deleted=\'False\'$ ]] || return 1
    jq --arg to "${BASH_REMATCH[1]}" --arg i "${BASH_REMATCH[2]}" --arg from "${BASH_REMATCH[3]}" \
        'map(if .ID == $i and .Host == $from then .Host = $to else . end)' \
        "$WORK/$file" > "$WORK/t" && mv "$WORK/t" "$WORK/$file"
}

S1=11111111-1111-1111-1111-111111111111 S2=22222222-2222-2222-2222-222222222222
G1=33333333-3333-3333-3333-333333333333 V1=44444444-4444-4444-4444-444444444444
V2=55555555-5555-5555-5555-555555555555 G2=66666666-6666-6666-6666-666666666666
share() { printf '{"ID":"%s","Status":"%s","Share Type Name":"%s","Host":"%s"}' "$1" "$2" "$3" "$4"; }
server() { printf '{"ID":"%s","Host":"%s","Status":"%s","Share Network ID":"%s"}' "$1" "$2" "$3" "$4"; }

reset() {  # nfs1 (deleted) left a share and a server; nfs1-x and generic are live
    rm -rf "${WORK:?}"/backends; mkdir -p "$CINDER_USER_INPUT_STORAGE_CONF_DIRECTORY"
    : > "$WORK/os"; : > "$WORK/sql"; rm -f "$WORK/api_down"
    MANILA_ENABLED="" CONTROL=yes LIST_RC=0 SERVER_DELETE=works SHARE_DELETE=works MARIADB=works
    unset T_manila_enabled
    echo "[$(share $S1 deleting nfs1 cc1@nfs1#nfs1),$(share $S2 error nfs1-x cc1@nfs1-x#nfs1-x),$(share $G1 available default_share_type cc1@generic#GENERIC)]" > "$WORK/shares.json"
    echo "[$(server $V1 cc1@nfs1 error n1),$(server $V2 cc1@nfs1-x error n2),$(server $G2 cc1@generic active n1)]" > "$WORK/servers.json"
    printf 'nfs1\nnfs1-x\n' > "$WORK/types"
}
run() { OUT="$(cinder_clean_storage_manila "$@")"; RC=$?; }
host_of() { jq -r --arg i "$2" '.[] | select(.ID == $i) | .Host' "$WORK/$1.json"; }
ids() { jq -r '[.[].ID] | join(" ")' "$WORK/$1.json"; }

# C1. the leftovers of nfs1 go; nfs1-x (a name nfs1 is a prefix of) and generic stay
reset
run nfs1
chk "C1 rc" "$RC" 0
chk "C1 shares left" "$(ids shares)" "$S2 $G1"
chk "C1 servers left" "$(ids servers)" "$V2 $G2"
chk "C1 nfs1-x share host" "$(host_of shares $S2)" "cc1@nfs1-x#nfs1-x"
chk "C1 nfs1-x server host" "$(host_of servers $V2)" "cc1@nfs1-x"
chk "C1 types" "$(xargs < "$WORK/types")" "nfs1-x"
chk "C1 SQL only for its rows" "$(grep -c -e "$S1" -e "$V1" "$WORK/sql") of $(wc -l < "$WORK/sql" | xargs)" "2 of 2"
chk "C1 share moved with its pool" "$(grep -c "SET host='cc1@generic#nfs1' WHERE share_id='$S1' AND host='cc1@nfs1#nfs1'" "$WORK/sql")" 1
chk "C1 output" "$OUT" "storage nfs1: shares deleted: $S1
storage nfs1: share servers deleted: $V1
share networks its share servers used, delete them if nothing else uses them: n1
storage nfs1: share type nfs1 deleted
storage nfs1: nothing left on Manila"

# C2. a share a previous run already moved: deleted, not moved again
reset
echo "[$(share $S1 deleting nfs1 cc1@generic#nfs1)]" > "$WORK/shares.json"
run nfs1
chk "C2 rc" "$RC" 0
chk "C2 share gone" "$(ids shares)" ""
chk "C2 no share SQL" "$(grep -c share_instances "$WORK/sql")" 0

# C3. the SQL fails: stop before any delete
reset; MARIADB=fails
run nfs1
chk "C3 rc" "$RC" 1
chk "C3 message" "$OUT" "share $S1 at cc1@nfs1#nfs1 could not be moved to generic"
chk "C3 nothing deleted" "$(grep -c delete "$WORK/os")" 0

# C3b. a share that stays: servers are not touched, the type stays
reset; SHARE_DELETE=fails
run nfs1
chk "C3b rc" "$RC" 1
chk "C3b message" "$OUT" "storage nfs1: shares not deleted: $S1"
chk "C3b server not moved" "$(host_of servers $V1)" "cc1@nfs1"
chk "C3b type kept" "$(grep -cx nfs1 "$WORK/types")" 1

# C4. a share server whose delete fails goes back to nfs1, so a rerun finds it
reset
SERVER_DELETE=fails
run nfs1
chk "C4 rc" "$RC" 1
chk "C4 message" "$(tail -2 <<< "$OUT")" "share networks its share servers used, delete them if nothing else uses them: n1
storage nfs1: share servers not deleted: $V1"
chk "C4 server back at nfs1" "$(host_of servers $V1)" "cc1@nfs1"
chk "C4 type kept" "$(grep -cx nfs1 "$WORK/types")" 1
SERVER_DELETE=works
run nfs1
chk "C4 rerun rc" "$RC" 0
chk "C4 rerun servers" "$(ids servers)" "$V2 $G2"

# C4b. a server whose delete fails while the API is down is not taken as deleted
reset
SERVER_DELETE=down
run nfs1
chk "C4b rc" "$RC" 1
chk "C4b message" "$(tail -1 <<< "$OUT")" "storage nfs1: share servers not deleted: $V1"
chk "C4b server back at nfs1" "$(host_of servers $V1)" "cc1@nfs1"

# C5. a server on another node moves to that node's generic; each share network listed once
reset
echo "[$(server $V1 cc2@nfs1 error n1),$(server $V2 cc1@nfs1 error n1),$(server $G2 cc1@nfs1 error n3)]" > "$WORK/servers.json"
run nfs1
chk "C5 rc" "$RC" 0
chk "C5 SQL" "$(grep -c "SET host='cc2@generic' WHERE id='$V1' AND host='cc2@nfs1'" "$WORK/sql")" 1
chk "C5 networks" "$(grep '^share networks' <<< "$OUT")" "share networks its share servers used, delete them if nothing else uses them: n1 n3"

# C6. a share never scheduled (no host): deleted without SQL
reset
echo "[{\"ID\":\"$S1\",\"Status\":\"error\",\"Share Type Name\":\"nfs1\",\"Host\":null}]" > "$WORK/shares.json"
run nfs1
chk "C6 rc" "$RC" 0
chk "C6 share gone" "$(ids shares)" ""
chk "C6 no share SQL" "$(grep -c share_instances "$WORK/sql")" 0

# C7. a share of the type on some other backend is refused, not force-deleted
reset
echo "[$(share $S1 available nfs1 cc1@other#other)]" > "$WORK/shares.json"
run nfs1
chk "C7 rc" "$RC" 1
chk "C7 message" "$OUT" "share $S1 is at cc1@other#other, not on storage nfs1"
chk "C7 nothing deleted" "$(grep -c delete "$WORK/os")" 0

# C8-C12. refused or nothing to do, before any change
reset; MANILA_ENABLED=false; run nfs1
chk "C8 Manila disabled" "$RC $OUT $(wc -l < "$WORK/os" | xargs)" "0 Manila is disabled 0"
reset; echo "[nfs1]" > "$CINDER_USER_INPUT_STORAGE_CONF_DIRECTORY/ext_storage_nfs1.conf"; run nfs1
chk "C9 storage still exists" "$RC $OUT" "1 storage nfs1 still exists, delete it with delete_storage"
reset; CONTROL=no; run nfs1
chk "C10 not a control" "$RC $OUT" "1 run this on a control node"
for n in "" generic CubeStorage tenant_share_type "a;b" "a b" "nfs1'" ; do
    reset; run "$n"
    chk "C11 name [$n]" "$RC $(cat "$WORK/os" "$WORK/sql" | wc -l | xargs)" "1 0"
done
reset; LIST_RC=1; run nfs1
chk "C12 list fails" "$RC $OUT $(wc -l < "$WORK/sql" | xargs)" "1 Manila shares or share servers of storage nfs1 could not be read 0"

# C13. nothing of it left, no type: nothing done
reset; echo "[]" > "$WORK/shares.json"; echo "[]" > "$WORK/servers.json"; : > "$WORK/types"; run nfs1
chk "C13 rc and output" "$RC $OUT" "0 storage nfs1: nothing left on Manila"
chk "C13 no change" "$(grep -c delete "$WORK/os") $(wc -l < "$WORK/sql" | xargs)" "0 0"

# C15. shares of the GENERIC pool are never taken for leftovers, whatever the type is named
for n in tenant_share_type nfs1 ; do
    reset
    echo "[$(share $G1 available $n cc1@generic#GENERIC)]" > "$WORK/shares.json"
    run "$n"
    chk "C15 [$n] rc" "$RC" 1
    chk "C15 [$n] share kept" "$(ids shares)" "$G1"
    chk "C15 [$n] nothing changed" "$(grep -c delete "$WORK/os") $(wc -l < "$WORK/sql" | xargs)" "0 0"
done

# C14. an ID or host that could break the SQL is refused before it reaches the database
reset; echo "[]" > "$WORK/shares.json"
echo "[$(server $V1 "c'c1@nfs1" error n1)]" > "$WORK/servers.json"
run nfs1
chk "C14 host rc" "$RC" 1
chk "C14 host message" "$OUT" "share server $V1 at c'c1@nfs1 could not be moved to generic"
chk "C14 host no SQL" "$(wc -l < "$WORK/sql" | xargs)" 0
reset
_cinder_manila_set_host server "x';drop" cc1@nfs1 cc1@generic; RC=$?
chk "C14 id" "$RC $(wc -l < "$WORK/sql" | xargs)" "1 0"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
