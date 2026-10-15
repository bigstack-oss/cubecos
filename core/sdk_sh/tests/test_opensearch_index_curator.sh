#!/bin/bash
#
# Unit test for opensearch_index_curator in ../modules/sdk_opensearch.sh.
#
# The daily /etc/cron.d/ec-curator job ran curator_cli's delete-indices with an age filter
# on the date in each index name. curator is gone (its last release pins urllib3 below 2),
# and the function now applies that filter itself: the first eight-digit run in the name,
# read as midnight UTC, older than now minus $1 days. Undated and invalid-date names stay.
#
# Self-contained: extracts the function and stubs curl, with index dates computed from
# today, so it needs no cluster.
#   Run: bash test_opensearch_index_curator.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_opensearch.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

body="$(awk '$0 ~ "^opensearch_index_curator\\(\\)" {p=1} p{print} p&&/^}/{exit}' "$SRC")"
[ -n "$body" ] || { echo "FAIL: opensearch_index_curator not extracted"; exit 1; }
eval "$body"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ---------------------------------------------------------------
# INDICES: what _cat/indices lists; every DELETE is logged to $CALLS.
day() { date -u -d "-$1 days" +%Y%m%d ; }
OPENSEARCH_URL=http://os
CALLS=$TMP/calls
INDICES=""
curl_stub()
{
    local a url="" del=0
    for a in "$@" ; do
        case "$a" in http://*) url=$a ;; DELETE) del=1 ;; esac
    done
    if [ $del = 1 ] ; then
        echo "DELETE ${url#$OPENSEARCH_URL/}" >> "$CALLS"
    else
        case "$url" in
        *_cat/indices*) echo "$url" > "$TMP/listurl" ; printf '%s\n' $INDICES ;;
        esac
    fi
    return 0
}
CURL=curl_stub
deleted() { sed -n 's/^DELETE //p' "$CALLS" 2>/dev/null | sort | tr '\n' ' ' ; }
run() { : > "$CALLS" ; opensearch_index_curator "$@" >/dev/null ; echo $? ; }

OLD8=$(day 8) OLD30=$(day 30) NEW6=$(day 6) TODAY=$(day 0)
INDICES="logs-$OLD8 logs-$NEW6 logs-$TODAY audit-$OLD30-x .kibana_1 .opendistro-job-scheduler-lock security-auditlog-20261399"

# 1. rp 7: only names dated more than 7 days ago go
chk "1 rc" "$(run 7)" 0
chk "1 deleted" "$(deleted)" "audit-$OLD30-x logs-$OLD8 "

# 2. closed indices are listed too
chk "2 expand_wildcards" "$(grep -c 'expand_wildcards=open,closed' "$TMP/listurl")" 1

# 3. rp 0: every dated index goes, today's too (its midnight is already past), as with curator
chk "3 rc" "$(run 0)" 0
chk "3 deleted" "$(deleted)" "audit-$OLD30-x logs-$OLD8 logs-$NEW6 logs-$TODAY "

# 4. no rp: 14 days, as before
chk "4 rc" "$(run)" 0
chk "4 deleted" "$(deleted)" "audit-$OLD30-x "

# 5. --dry-run lists what would go and deletes nothing
: > "$CALLS"
out=$(opensearch_index_curator 7 --dry-run)
chk "5 rc" "$?" 0
chk "5 no delete" "$(deleted)" ""
chk "5 listed" "$(echo "$out" | sort | tr '\n' ' ')" "DRY-RUN: would delete audit-$OLD30-x DRY-RUN: would delete logs-$OLD8 "

# 6. the first eight-digit run is the date
INDICES="metrics-$OLD30-$TODAY metrics-$TODAY-$OLD30"
chk "6 rc" "$(run 7)" 0
chk "6 deleted" "$(deleted)" "metrics-$OLD30-$TODAY "

# 7. opensearch unreachable (empty listing) -> nothing, rc 0
INDICES=""
chk "7 rc" "$(run 7)" 0
chk "7 deleted" "$(deleted)" ""

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
