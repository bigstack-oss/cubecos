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

# Regenerate prometheus's file_sd target list for the agent fleet. Control-side.
# Safe to re-run: prometheus picks up file_sd changes without a reload.
lachesis_prometheus_targets()
{
    local out=/etc/prometheus/targets/lachesis.json
    local port=9090

    mkdir -p "$(dirname $out)"

    # `cubectl node list compute` does not filter, and matching "compute" as a
    # substring would miss control-converged. Roles here mirror IsCompute() in
    # core/modules/include/role_cubesys.h.
    cubectl node list -j 2>/dev/null | jq -c --arg port "$port" '
        [ { targets: [ .[]
              | select(.role == "compute" or .role == "control-converged" or .role == "edge-core")
              | .ip.management + ":" + $port ],
            labels: {} } ]' > "$out.tmp" || { rm -f "$out.tmp" ; return 1 ; }

    mv -f "$out.tmp" "$out"
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
