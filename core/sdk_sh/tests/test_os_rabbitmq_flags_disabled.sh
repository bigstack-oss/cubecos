#!/bin/bash
#
# Unit test for os_rabbitmq_flags_disabled (../modules/sdk_os.sh): the feature flags the
# broker reports disabled, on one line, experimental ones left out; a broker that does not
# answer is a failure, never an empty line (#2164). The JSON is what rabbitmqctl printed on
# cube42 (3.11.28 with six left off, 3.12.14 freshly started). Self-contained, mocks
# rabbitmqctl. Run: bash test_os_rabbitmq_flags_disabled.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extract(){ awk -v f="^$2\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$1"; }
eval "$(extract "$DIR/../modules/sdk_os.sh" os_rabbitmq_flags_disabled)"
type os_rabbitmq_flags_disabled >/dev/null 2>&1 || { echo "FAIL: not extracted"; exit 1; }

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# the function runs it through env, so it has to be a program on PATH
mkdir $T/bin; export T; export OUT=$T/out RC=0
printf '#!/bin/bash\necho "$HOSTNAME $*" > $T/args; cat $OUT; exit $RC\n' > $T/bin/rabbitmqctl
chmod +x $T/bin/rabbitmqctl; PATH=$T/bin:$PATH
f(){ [ "$1" = "$2" ] && echo "$3" || echo n; }

cat > $OUT <<'EOF'
[{"name":"classic_mirrored_queue_version","state":"enabled","stability":"stable"},{"name":"classic_queue_type_delivery_support","state":"enabled","stability":"stable"},{"name":"direct_exchange_routing_v2","state":"disabled","stability":"stable"},{"name":"drop_unroutable_metric","state":"enabled","stability":"stable"},{"name":"empty_basic_get_metric","state":"enabled","stability":"stable"},{"name":"feature_flags_v2","state":"disabled","stability":"stable"},{"name":"implicit_default_bindings","state":"enabled","stability":"required"},{"name":"listener_records_in_ets","state":"disabled","stability":"stable"},{"name":"maintenance_mode_status","state":"enabled","stability":"required"},{"name":"quorum_queue","state":"enabled","stability":"required"},{"name":"stream_queue","state":"enabled","stability":"stable"},{"name":"stream_sac_coordinator_unblock_group","state":"disabled","stability":"stable"},{"name":"stream_single_active_consumer","state":"disabled","stability":"stable"},{"name":"tracking_records_in_ets","state":"disabled","stability":"stable"},{"name":"user_limits","state":"enabled","stability":"required"},{"name":"virtual_host_metadata","state":"enabled","stability":"required"}]
EOF
out=$(os_rabbitmq_flags_disabled cc2); rc=$?
chk "3.11 with six off" "$rc:$out" "0:direct_exchange_routing_v2 feature_flags_v2 listener_records_in_ets stream_sac_coordinator_unblock_group stream_single_active_consumer tracking_records_in_ets"
chk "asks the named node" "$(cut -d' ' -f1 $T/args)" "cc2"
HOSTNAME=cc9 os_rabbitmq_flags_disabled >/dev/null
chk "defaults to this host" "$(cut -d' ' -f1 $T/args)" "cc9"

cat > $OUT <<'EOF'
[{"name":"classic_mirrored_queue_version","state":"enabled","stability":"required"},{"name":"feature_flags_v2","state":"enabled","stability":"required"},{"name":"restart_streams","state":"enabled","stability":"stable"},{"name":"stream_sac_coordinator_unblock_group","state":"enabled","stability":"stable"}]
EOF
out=$(os_rabbitmq_flags_disabled cc1); rc=$?
chk "3.12 all on: empty, ok" "$rc:$out" "0:"

cat > $OUT <<'EOF'
[{"name":"khepri_db","state":"disabled","stability":"experimental"},{"name":"message_containers","state":"disabled","stability":"stable"},{"name":"quorum_queue","state":"enabled","stability":"required"}]
EOF
out=$(os_rabbitmq_flags_disabled c1); rc=$?
chk "experimental left out" "$rc:$out" "0:message_containers"

cat > $OUT <<'EOF'
[{"name":"stream_queue","state":"unavailable","stability":"stable"},{"name":"quorum_queue","state":"enabled","stability":"required"}]
EOF
out=$(os_rabbitmq_flags_disabled c1); rc=$?
chk "mid-roll unavailable is not disabled" "$rc:$out" "0:"

: > $OUT; RC=69
out=$(os_rabbitmq_flags_disabled c1); rc=$?
chk "broker down: fails" "$(f "$rc" 0 bad)" "n"
chk "broker down: prints nothing" "$out" ""

echo "Error: unable to perform an operation on node 'rabbit@c1'" > $OUT; RC=69
out=$(os_rabbitmq_flags_disabled c1 2>/dev/null); rc=$?
chk "error text: fails" "$(f "$rc" 0 bad)" "n"

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
