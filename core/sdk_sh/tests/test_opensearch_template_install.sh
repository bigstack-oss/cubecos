#!/bin/bash
#
# Unit test for opensearch_template_install / opensearch_shard_per_node_set in
# ../modules/sdk_opensearch.sh.
#
# On a full-cluster cold boot the master commits logstash while only its own opensearch
# node is up, so no cluster manager can be elected. Each template PUT waited ~30s in
# opensearch before a 503, 24 retries per template: the commit took 28 min on cube4510.
# Now an unchanged template (md5 stamp) costs no request, and a changed one defers
# (rc 2) without a manager instead of retrying against it.
#
# Self-contained: extracts the functions and stubs curl, sleep and Warning, with the
# stamp dir moved into a temp dir, so it needs no cluster.
#   Run: bash test_opensearch_template_install.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_opensearch.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for f in opensearch_has_manager opensearch_wait_manager opensearch_shard_per_node_set opensearch_template_install ; do
    body="$(awk -v f="$f" '$0 ~ "^"f"\\(\\)" {p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $f not extracted"; exit 1; }
    eval "$body"
done

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ---------------------------------------------------------------
# MANAGER: elected manager seen; EXISTS: template present; PUT_OK: PUT succeeds.
OPENSEARCH_URL=http://os
OPENSEARCH_STATE_DIR=$TMP
CALLS=$TMP/calls
MANAGER=1 EXISTS=1 PUT_OK=1
curl_stub()
{
    local a url="" put=0 code=0
    for a in "$@" ; do
        case "$a" in http://*) url=$a ;; PUT|-XPUT) put=1 ;; esac
    done
    case "$url" in
    *cluster_manager_node*)
        [ "$MANAGER" = 1 ] && echo '{"cluster_manager_node":"abc"}' || echo '{"cluster_name":"c"}' ;;
    *_template*)
        if [ $put = 1 ] ; then
            echo "PUT $url" >> "$CALLS"
            [ "$PUT_OK" = 1 ] || return 22
        else
            echo "GET $url" >> "$CALLS"
            [ "$EXISTS" = 1 ] && code=200 || code=404
            printf '%s' $code
        fi ;;
    *_cluster/settings*)
        echo "PUT $url" >> "$CALLS" ;;
    esac
    return 0
}
CURL=curl_stub
sleep() { : ; }
Warning() { : ; }

TPL=$TMP/logs.json
echo '{"index_patterns":["logs-*"]}' > "$TPL"
STAMP=$TMP/opensearch_template_logs
puts() { grep -c '^PUT' "$CALLS" 2>/dev/null || true ; }
run() { : > "$CALLS" ; opensearch_template_install logs "$TPL" "$@" ; echo $? ; }

# 1. first install, manager up -> PUT, stamp written
rm -f "$STAMP"
chk "1 rc" "$(run)" 0
chk "1 put" "$(puts)" 1
chk "1 stamp" "$(cat "$STAMP")" "$(md5sum < "$TPL" | cut -d' ' -f1)"
chk "1 manager_timeout" "$(grep -c 'cluster_manager_timeout=' "$CALLS")" 1

# 2. unchanged, cold boot (no manager) -> rc 0, no request at all
MANAGER=0
chk "2 rc" "$(run 60)" 0
chk "2 no calls" "$(wc -l < "$CALLS" | tr -d ' ')" 0

# 3. unchanged, manager up, template present -> no PUT
MANAGER=1
chk "3 rc" "$(run)" 0
chk "3 no put" "$(puts)" 0

# 4. unchanged but template deleted in opensearch -> re-PUT
EXISTS=0
chk "4 rc" "$(run)" 0
chk "4 put" "$(puts)" 1
EXISTS=1

# 5. template changed, no manager -> deferred (rc 2), no PUT, stamp kept
echo '{"index_patterns":["logs-*"],"order":1}' > "$TPL"
old=$(cat "$STAMP")
MANAGER=0
chk "5 rc" "$(run 60)" 2
chk "5 no put" "$(puts)" 0
chk "5 stamp kept" "$(cat "$STAMP")" "$old"

# 6. same change once the cluster is up (cluster_start) -> PUT, stamp updated
MANAGER=1
chk "6 rc" "$(run 120)" 0
chk "6 put" "$(puts)" 1
chk "6 stamp" "$(cat "$STAMP")" "$(md5sum < "$TPL" | cut -d' ' -f1)"

# 7. changed, PUT keeps failing -> rc 1 after 3 tries, stamp kept
echo '{"index_patterns":["logs-*"],"order":2}' > "$TPL"
old=$(cat "$STAMP")
PUT_OK=0
chk "7 rc" "$(run)" 1
chk "7 put tries" "$(puts)" 3
chk "7 stamp kept" "$(cat "$STAMP")" "$old"
PUT_OK=1

# 8. missing file -> rc 1
chk "8 rc" "$(opensearch_template_install logs "$TMP/nosuch" >/dev/null 2>&1 ; echo $?)" 1

# 9. shard setting: no manager -> rc 2, no PUT; manager -> PUT
MANAGER=0 ; : > "$CALLS"
opensearch_shard_per_node_set 14000 >/dev/null ; chk "9 defer rc" "$?" 2
chk "9 no put" "$(puts)" 0
MANAGER=1 ; : > "$CALLS"
opensearch_shard_per_node_set 14000 >/dev/null ; chk "9 rc" "$?" 0
chk "9 put" "$(puts)" 1

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
