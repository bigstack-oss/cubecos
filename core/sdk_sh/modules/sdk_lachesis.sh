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

# Regenerate prometheus's file_sd target list for the agent fleet. Control-side,
# invoked at prometheus commit and from the every-minute cron: file_sd solves
# reload, but nothing re-commits this module when compute membership changes.
lachesis_prometheus_targets()
{
    local out=/etc/prometheus/targets/lachesis.json
    local port=9090
    local nodes

    # -r compute is a role-bitmask match (compute, control-converged, edge-core)
    # -- exactly IsCompute() in core/modules/include/role_cubesys.h. Empty
    # output means cubectl/etcd gave no answer (e.g. bootstrap commits before
    # the node registers itself), never a zero-node cluster: fail instead of
    # truncating the list. Bounded so a wedged etcd cannot stall the cron.
    nodes=$(timeout 20 cubectl node list -j -r compute 2>/dev/null)
    [ -n "$nodes" ] || return 1

    mkdir -p "$(dirname $out)"

    # One group per node so instance carries the hostname rather than ip:port;
    # the dashboards populate their node picker from label_values(up, instance).
    echo "$nodes" | jq -c --arg port "$port" '
        [ .[] | { targets: [ .ip.management + ":" + $port ],
                  labels: { instance: .hostname } } ]' > "$out.tmp" || { rm -f "$out.tmp" ; return 1 ; }

    # a removed node's target is dropped, not retained-as-down: removal is
    # deliberate, and a permanent up==0 alert for it would only be noise
    if cmp -s "$out.tmp" "$out" 2>/dev/null ; then
        rm -f "$out.tmp"
    else
        mv -f "$out.tmp" "$out"
    fi
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
