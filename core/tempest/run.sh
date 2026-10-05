#!/bin/bash
# Container entrypoint: render tempest.conf, run the selected suite, write results, tear down this run.
set -uo pipefail
SUITE=${SUITE:-smoke}; CONCURRENCY=${CONCURRENCY:-2}
export OUT=${OUT:-/work/out} WORKSPACE=/work/ws
PLUGINS="neutron cinder octavia designate heat manila barbican watcher cyborg ironic"
plugin_re() { case $1 in manila) echo '^manila_tempest_tests\.' ;; *) echo "^$1_tempest_plugin\\." ;; esac; }

if [ -n "${REGEX:-}" ]; then SEL=("--regex $REGEX")
else
    case " smoke api scenario full $PLUGINS " in
        *" $SUITE "*) ;;
        *) echo "unknown SUITE=$SUITE ($(echo smoke api scenario full $PLUGINS))"; exit 2 ;;
    esac
    case $SUITE in
        smoke)    SEL=("--smoke") ;;
        api)      SEL=("--regex ^tempest\.api\.") ;;
        scenario) SEL=("--regex ^tempest\.(serial_tests\.)?scenario\.") ;;
        full)     SEL=("--regex ^tempest\."); for p in $PLUGINS; do SEL+=("--regex $(plugin_re $p)"); done ;;
        *)        SEL=("--regex $(plugin_re $SUITE)") ;;
    esac
fi
for v in VIP ADMIN_USER ADMIN_PASSWORD ADMIN_PROJECT; do [ -n "${!v:-}" ] || { echo "$v is required"; exit 2; }; done
export OS_AUTH_URL=http://$VIP:5000/v3 OS_USERNAME=$ADMIN_USER OS_PASSWORD=$ADMIN_PASSWORD \
       OS_PROJECT_NAME=$ADMIN_PROJECT OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default \
       OS_IDENTITY_API_VERSION=3 OS_AUTH_TYPE=password OS_INTERFACE=public

mkdir -p "$OUT"
if [ "${PREFLIGHT:-1}" = 1 ]; then
    python3 /opt/tempest/preflight.py 2>&1 | tee "$OUT/preflight.log"
    [ "${PIPESTATUS[0]}" = 0 ] || exit 3
fi
[ "${PREFLIGHT_ONLY:-}" = 1 ] && exit 0
: > "$OUT/created.txt"
tempest init "$WORKSPACE" >/dev/null && cp /opt/tempest/exclude-cos.txt "$WORKSPACE/etc/"
openstack project list -f value -c ID -c Name > "$OUT/projects.tmp" || { echo "cannot reach keystone at $VIP"; exit 2; }
awk '$2 ~ /^tempest-/ {print $1}' "$OUT/projects.tmp" > "$OUT/projects-before.txt"; rm -f "$OUT/projects.tmp"
openstack flavor list --all -f value -c ID -c Name | awk '$2 ~ /^tempest-/ {print $1}' > "$OUT/flavors-before.txt"
trap '/opt/tempest/teardown.sh' EXIT
/opt/tempest/render-conf.sh || exit 2
cd "$WORKSPACE" || exit 2

# PID 1 ignores untrapped signals: stop tempest on INT/TERM, then the EXIT trap tears down
stop=0
# (background jobs start with SIGINT ignored, so TERM everything but this shell)
trap 'stop=1; kill -TERM -1 2>/dev/null' INT TERM
unset_os=$(compgen -v | grep '^OS_' | sed 's/^/-u /')
rc=0; : > "$OUT/results.subunit"
for g in "${SEL[@]}"; do
    # no OS_* in the run: CLI-based plugin tests would inherit the admin credentials
    # shellcheck disable=SC2086  # $g is "--regex <re>" or "--smoke"
    # watcher client_functional tests share unscoped listings; they race above concurrency 1
    conc=$CONCURRENCY; case $g in *watcher*) conc=1 ;; esac
    env $unset_os tempest run $g --exclude-list etc/exclude-cos.txt --concurrency "$conc" \
        > >(tee -a "$OUT/console.log") 2>&1 &
    tpid=$!
    wait $tpid; r=$?
    while kill -0 $tpid 2>/dev/null; do wait $tpid; r=$?; done
    [ "$r" -ne 0 ] && rc=$r
    stestr last --subunit >> "$OUT/results.subunit" 2>/dev/null
    [ $stop = 1 ] && { rc=130; break; }
done
subunit2junitxml < "$OUT/results.subunit" > "$OUT/results.xml" 2>/dev/null
subunit2html "$OUT/results.subunit" "$OUT/results.html" >/dev/null 2>&1
grep -E '^ - (Passed|Skipped|Failed)' "$OUT/console.log"
exit $rc
