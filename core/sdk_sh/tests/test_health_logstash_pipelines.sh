#!/bin/bash
#
# Unit test for health_logstash_check and its per-node probe health_logstash_pipelines in
# ../modules/sdk_health.sh.
#
# On a 384-core control node logstash died on OutOfMemoryError while it created its
# pipelines, and systemd restarted it into the same death 1509 times over three days. The
# check only asked whether the unit was running, which it is for all but RestartSec of every
# cycle, so it stayed green and nothing reached InfluxDB. It now also asks logstash which of
# the pipelines in pipelines.yml it runs, and gives a start that has not crashed a grace
# period to bring them up.
#
# Self-contained: extracts only the functions under test and stubs curl, systemctl, ps,
# remote_run and is_remote_running, so it needs no cluster.
#   Run: bash test_health_logstash_pipelines.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_health.sh"

for fn in health_logstash_pipelines health_logstash_check ; do
    body="$(awk -v fn="$fn" '$0 ~ "^"fn"\\(\\)" {p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done
grace="$(awk -F= '/^LOGSTASH_START_GRACE=/{print $2}' "$SRC")"
[ -n "$grace" ] || { echo "FAIL: LOGSTASH_START_GRACE not found"; exit 1; }
LOGSTASH_START_GRACE=$grace

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ---------------------------------------------------------------
# Per node: ACTIVE is the unit state, UP the pipelines logstash reports RUNNING ("-" = the
# API does not answer), RESTARTS systemd's NRestarts and AGE the main process's age in s.
declare -A ACTIVE UP RESTARTS AGE
CUBE_NODE_CONTROL_HOSTNAMES=(c1 c2 c3)
LOGSTASH_PIPELINES_YML=$(mktemp)
cat > "$LOGSTASH_PIPELINES_YML" <<'EOF'
- pipeline.id: log-transformer
  path.config: "/etc/logstash/conf.d/log-transformer.conf"
- pipeline.id: telegraf-persister
  path.config: "/etc/logstash/conf.d/telegraf-persister.conf"
- pipeline.id: kernel-event-mapper
  path.config: "/etc/logstash/conf.d/kernel-event-mapper.conf"
EOF
ALL="log-transformer telegraf-persister kernel-event-mapper"

curl_stub() {
    [ "${UP[$NODE]}" = "-" ] && return 7
    local id sep= out='{"status":"green","indicators":{"pipelines":{"indicators":{'
    for id in ${UP[$NODE]} ; do
        out+="$sep\"$id\":{\"status\":\"green\",\"details\":{\"status\":{\"state\":\"RUNNING\"}}}" ; sep=,
    done
    # a pipeline logstash knows of but has not started is listed too, just not RUNNING
    out+="$sep\"auditlog-transformer\":{\"status\":\"yellow\",\"details\":{\"status\":{\"state\":\"LOADING\"}}}"
    echo "$out}}}}"
}
systemctl() {   # systemctl show logstash -p <prop> --value
    case $4 in NRestarts) echo "${RESTARTS[$NODE]}" ;; MainPID) echo 4242 ;; esac
}
ps() { printf '%7s\n' "${AGE[$NODE]}" ; }
is_moderator_node() { return 1 ; }
remote_run() { local NODE=$1 ; shift ; eval "$*" ; }
is_remote_running() { [ "${ACTIVE[$1]}" = 1 ] ; }
_health_fail_log() { return $ERR_CODE ; }
CURL=curl_stub HEX_SDK= ERR_LOGSIZE=100

healthy() { local n ; for n in c1 c2 c3 ; do ACTIVE[$n]=1 UP[$n]=$ALL RESTARTS[$n]=0 AGE[$n]=86400 ; done ; }
run() { ERR_CODE=0 ERR_MSG= ERR_LOG= ; health_logstash_check ; }

# 1. every pipeline running on every node
healthy ; run
chk "1 healthy" "$ERR_CODE" 0

# 2. the unit is down on c2
healthy ; ACTIVE[c2]=0 ; run
chk "2 down code" "$ERR_CODE" 1
chk "2 down msg" "$(echo -e "$ERR_MSG")" "logstash on c2 is not running"

# 3. the #1259 crash loop: c2 is running again, 40 s into another attempt, API silent
healthy ; UP[c2]=- RESTARTS[c2]=1509 AGE[c2]=40 ; run
chk "3 loop code" "$ERR_CODE" 2
chk "3 loop msg" "$(echo -e "$ERR_MSG")" "logstash on c2 is not running pipelines: $ALL (NRestarts=1509)"
chk "3 loop log" "$ERR_LOG" /var/log/logstash/logstash.log

# 4. a plain (re)start, still inside the grace period -> not an error yet
healthy ; UP[c2]=- RESTARTS[c2]=0 AGE[c2]=40 ; run
chk "4 starting" "$ERR_CODE" 0

# 5. the same start, past the grace period and still not running its pipelines
healthy ; UP[c2]=- RESTARTS[c2]=0 AGE[c2]=$LOGSTASH_START_GRACE ; run
chk "5 stuck" "$ERR_CODE" 2

# 6. up for a day, one pipeline gone: only that one is named
healthy ; UP[c3]="log-transformer kernel-event-mapper" ; run
chk "6 one code" "$ERR_CODE" 2
chk "6 one msg" "$(echo -e "$ERR_MSG")" "logstash on c3 is not running pipelines: telegraf-persister (NRestarts=0)"

rm -f "$LOGSTASH_PIPELINES_YML"
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: logstash pipelines health check" ; exit 0 ; } || exit 1
