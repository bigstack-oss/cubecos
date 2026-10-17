#!/bin/bash
#
# Unit test for the CLI's storage calls through cube-cos-api
# (../modules/sdk_api.sh, #2098): the API applies a storage or device tier on
# every control, and the CLI then waits on the outcome itself -- the backend up
# after a create, no control listing a deleted storage. curl, hex_sdk and the
# clock are faked; needs no cluster.
#   Run: bash test_api_storage.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_api.sh"

extract() {  # <file> <function>
    local body
    body="$(awk -v n="^$2\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$1")"
    [ -n "$body" ] || return 1
    eval "$body"
    [ "$(type -t "$2")" = function ]
}
for f in _api_request _api_msg _api_call _api_storage_err api_storage_put \
         api_storage_delete api_storage_wait_deleted api_storage_tier_create \
         api_storage_tier_delete ; do
    extract "$SRC" "$f" || { echo "FAIL: $f not extracted"; exit 1; }
done
# one-liners
eval "$(grep -E '^_api_uri\(\)' "$SRC")"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
echo 'T_cubesys_controller=dc1' > "$TMP/bin/hex_tuning"
PATH="$TMP/bin:$PATH"
HOSTNAME=cube45
mgmt_ip() { echo -n 10.0.0.5 ; }
CUBE_NODE_CONTROL_JSON='[{"hostname":"cube45","ip":{"management":"10.0.0.5"}},
                         {"hostname":"cube46","ip":{"management":"10.0.0.6"}}]'
sleep() { SECONDS=$((SECONDS + $1)) ; }

# curl: log "<method> <url> <body>", answer from $TMP/answers: one
# "<method> <url-suffix> <code> <body>" per line, first match wins and is
# consumed unless marked sticky with a leading '*'
curl() {
    local method=GET body="" url="" hdrs=""
    while [ $# -gt 0 ] ; do
        case "$1" in
            -X) method="$2" ; shift ;;
            --data-binary) body="$2" ; shift ;;
            -H) hdrs+="$2;" ; shift ;;
            -m|-w) shift ;;
            -*) ;;
            *) url="$1" ;;
        esac
        shift
    done
    echo "$method $url $body" >> "$TMP/calls"
    echo "$hdrs" >> "$TMP/headers"
    local n=0 line sticky m suffix code resp
    while IFS= read -r line ; do
        n=$((n + 1))
        sticky=0
        [ "${line:0:1}" == "*" ] && { sticky=1 ; line="${line:1}" ; }
        read -r m suffix code resp <<< "$line"
        if [ "$m" == "$method" ] && [[ "$url" == *"$suffix" ]] ; then
            [ $sticky -eq 1 ] || sed -i "${n}d" "$TMP/answers"
            [ "$code" == "000" ] && { printf '\n000' ; return 7 ; }
            printf '%s\n%s' "$resp" "$code"
            return 0
        fi
    done < "$TMP/answers"
    printf '\n000'
    return 7
}

NOT_READY=""
IN_USE=1
fake_sdk() {
    echo "sdk $*" >> "$TMP/calls"
    case "$1" in
        cinder_wait_for_backends_ready) echo -n "$NOT_READY" ; [ -z "$NOT_READY" ] ;;
        cinder_wait_for_backends_gone) echo -n "$STILL_SERVED" ; [ -z "$STILL_SERVED" ] ;;
        cinder_is_volume_type_in_use) return $IN_USE ;;
        *) return 1 ;;
    esac
}
HEX_SDK=fake_sdk

reset() { : > "$TMP/calls" ; : > "$TMP/headers" ; : > "$TMP/answers" ; NOT_READY="" ; STILL_SERVED="" ; IN_USE=1 ; SECONDS=0 ; }
answer() { echo "$*" >> "$TMP/answers" ; }

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
has() { case "$2" in *"$3"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: $1: [$2] lacks [$3]";; esac; }
calls() { cat "$TMP/calls" ; }
BASE=http://10.0.0.5:8082/api/v1/datacenters/dc1

# ==== A: api_storage_put ====

# A1: new storage -> POST to this node's API as the node, then wait for its backend
reset
answer 'POST /integrations/storages 202 {"code":202,"msg":"processing"}'
OUT="$(api_storage_put '{"name":"ext1","driver":"d"}' 2>"$TMP/err")"; RC=$?
chk "A1 rc" "$RC" 0
chk "A1 message" "$(echo "$OUT" | jq -r .message)" "storage ext1 set"
chk "A1 calls" "$(calls)" "POST $BASE/integrations/storages {\"name\":\"ext1\",\"driver\":\"d\"}
sdk cinder_wait_for_backends_ready ext1@ext1 300"
has "A1 node token" "$(head -n 1 "$TMP/headers")" "Node: cube45;Authorization: Bearer"

# A2: it exists -> 409, then PATCH it
reset
answer 'POST /integrations/storages 409 {"msg":"storage ext1 already exists"}'
answer 'PATCH /integrations/storages/ext1 202 {"msg":"processing"}'
OUT="$(api_storage_put '{"name":"ext1"}' 2>/dev/null)"; RC=$?
chk "A2 rc" "$RC" 0
chk "A2 patched" "$(calls | sed -n 2p | cut -d' ' -f1,2)" "PATCH $BASE/integrations/storages/ext1"

# A3: API refuses -> its msg, no wait
reset
answer 'POST /integrations/storages 500 {"msg":"failed to list storages"}'
api_storage_put '{"name":"ext1"}' >/dev/null 2>"$TMP/err"; RC=$?
chk "A3 rc" "$RC" 1
chk "A3 error" "$(jq -r .message "$TMP/err")" "storage ext1: failed to list storages"
chk "A3 no wait" "$(calls | grep -c sdk)" 0

# A4: applied, backend never comes up -> failure naming it
reset
answer 'POST /integrations/storages 202 {"msg":"processing"}'
NOT_READY=ext1@ext1
api_storage_put '{"name":"ext1"}' >/dev/null 2>"$TMP/err"; RC=$?
chk "A4 rc" "$RC" 1
has "A4 error" "$(jq -r .message "$TMP/err")" "backend ext1@ext1 is not up after 300s"

# A5: the name cinder knows: dots become dashes
reset
answer 'POST /integrations/storages 409 {}'
answer 'PATCH /integrations/storages/my-ext 202 {}'
api_storage_put '{"name":" my.ext "}' >/dev/null 2>&1; RC=$?
chk "A5 rc" "$RC" 0
has "A5 backend" "$(calls)" "sdk cinder_wait_for_backends_ready my-ext@my-ext 300"

# A6: API not answering
reset
api_storage_put '{"name":"ext1"}' >/dev/null 2>"$TMP/err"; RC=$?
chk "A6 rc" "$RC" 1
chk "A6 error" "$(jq -r .message "$TMP/err")" "storage ext1: cube-cos-api did not answer"

# A7: no name
reset
api_storage_put '{"driver":"d"}' >/dev/null 2>"$TMP/err"; RC=$?
chk "A7 rc" "$RC" 1
chk "A7 nothing called" "$(calls)" ""

# ==== B: api_storage_delete ====

# B1: DELETE, then every control's API stops listing it
reset
answer 'DELETE /integrations/storages/ext1 202 {"msg":"processing"}'
answer 'GET 10.0.0.6:8082/api/v1/datacenters/dc1/integrations/storages/ext1 200 {}'
answer '*GET /integrations/storages/ext1 404 {"msg":"storage ext1 not found"}'
OUT="$(api_storage_delete '{"name":"ext1"}' 2>"$TMP/err")"; RC=$?
chk "B1 rc" "$RC" 0
chk "B1 message" "$(echo "$OUT" | jq -r .message)" "storage ext1 deleted"
chk "B1 asked both controls" "$(calls | grep '^GET' | cut -d' ' -f2 | sed 's|:8082.*||' | sort -u | tr '\n' ' ')" "http://10.0.0.5 http://10.0.0.6 "
chk "B1 polled the slow one again" "$(calls | grep -c '^GET http://10.0.0.6')" 2

chk "B1 waited for cinder to drop the backend" "$(calls | grep -c '^sdk cinder_wait_for_backends_gone ext1@ext1 300')" 1

# B1b: every API stops listing it but cinder still serves the backend -> named failure
reset
STILL_SERVED="ext1@ext1"
answer 'DELETE /integrations/storages/ext1 202 {}'
answer '*GET /integrations/storages/ext1 404 {}'
api_storage_delete '{"name":"ext1"}' >/dev/null 2>"$TMP/err"; RC=$?
chk "B1b rc" "$RC" 1
chk "B1b error" "$(jq -r .message "$TMP/err")" "storage ext1 was deleted, but backend ext1@ext1 is still served after 300s"

# B2: in use -> refused before the API is called
reset
IN_USE=0
api_storage_delete '{"name":"ext1"}' >/dev/null 2>"$TMP/err"; RC=$?
chk "B2 rc" "$RC" 1
chk "B2 error" "$(jq -r .message "$TMP/err")" "volume type ext1 is still in use"
chk "B2 no API call" "$(calls | grep -vc '^sdk')" 0

# B3: one control keeps it -> bounded, and named
reset
answer 'DELETE /integrations/storages/ext1 202 {}'
answer '*GET 10.0.0.6:8082/api/v1/datacenters/dc1/integrations/storages/ext1 200 {}'
answer '*GET /integrations/storages/ext1 404 {}'
api_storage_delete '{"name":"ext1"}' >/dev/null 2>"$TMP/err"; RC=$?
chk "B3 rc" "$RC" 1
chk "B3 error" "$(jq -r .message "$TMP/err")" "storage ext1 is still configured on: 10.0.0.6"
N=$(calls | grep -c '^GET http://10.0.0.6')
chk "B3 bounded: 300s at 3s a poll" "$([ "$N" -ge 100 ] && [ "$N" -le 102 ] && echo yes)" yes

# B4: API says not found
reset
answer 'DELETE /integrations/storages/ext1 404 {"msg":"storage ext1 not found"}'
api_storage_delete '{"name":"ext1"}' >/dev/null 2>"$TMP/err"; RC=$?
chk "B4 rc" "$RC" 1
chk "B4 error" "$(jq -r .message "$TMP/err")" "storage ext1: storage ext1 not found"

# ==== C: api_storage_tier_create ====

# C1: one synchronous call, output shown, then the tier's backend
reset
answer 'POST /integrations/storages/tiers 200 {"msg":"storage tier gold created","data":{"name":"gold","output":"device tier gold created on osd.0 osd.1 (pool size 2)"}}'
OUT="$(api_storage_tier_create gold 0 osd.1 2>"$TMP/err")"; RC=$?
chk "C1 rc" "$RC" 0
chk "C1 output" "$OUT" "device tier gold created on osd.0 osd.1 (pool size 2)"
chk "C1 calls" "$(calls)" "POST $BASE/integrations/storages/tiers {\"name\":\"gold\",\"osdIds\":[\"0\",\"osd.1\"]}
sdk cinder_wait_for_backends_ready cube@gold 300"

# C2: refused -> the API's reason, no wait
reset
answer 'POST /integrations/storages/tiers 500 {"msg":"storage tier gold was created but registering it on cube46 failed: apply failed; run the create again to finish","data":null}'
api_storage_tier_create gold 0 >/dev/null 2>"$TMP/err"; RC=$?
chk "C2 rc" "$RC" 1
chk "C2 error" "$(cat "$TMP/err")" "Error: storage tier gold was created but registering it on cube46 failed: apply failed; run the create again to finish"
chk "C2 no wait" "$(calls | grep -c sdk)" 0

# C3: created, backend not up
reset
answer 'POST /integrations/storages/tiers 200 {"data":{"output":"ok"}}'
NOT_READY=cube@gold
api_storage_tier_create gold 0 >/dev/null 2>"$TMP/err"; RC=$?
chk "C3 rc" "$RC" 1
has "C3 error" "$(cat "$TMP/err")" "Cinder backend cube@gold is not up after 300s"

# ==== D: api_storage_tier_delete ====

reset
answer 'DELETE /integrations/storages/tiers/gold 200 {"data":{"output":"device tier gold deleted"}}'
OUT="$(api_storage_tier_delete gold 2>"$TMP/err")"; RC=$?
chk "D1 rc" "$RC" 0
chk "D1 output" "$OUT" "device tier gold deleted"

reset
answer 'DELETE /integrations/storages/tiers/gold 409 {"msg":"volume type gold is still in use, or the volume list could not be read; nothing was deleted"}'
api_storage_tier_delete gold >/dev/null 2>"$TMP/err"; RC=$?
chk "D2 rc" "$RC" 1
has "D2 error" "$(cat "$TMP/err")" "still in use"

echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: storage calls through cube-cos-api"; exit 0; } || exit 1
