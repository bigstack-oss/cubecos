# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

lachesis_metrics()
{
    curl -sf --max-time 5 http://localhost:9090/metrics
}

# Taps carrying the telemetry filters. The agent does not detach on shutdown, so
# this is what to check before reclaiming a node; other subsystems share clsact.
lachesis_tc_filters()
{
    local dev
    for dev in $(ip -br link | awk '/^tap/ {sub(/@.*/, "", $1); print $1}') ; do
        if tc filter show dev $dev ingress 2>/dev/null | grep -q telemetry ; then
            echo $dev
        fi
    done
}
