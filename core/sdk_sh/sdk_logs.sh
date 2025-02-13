# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ]; then
    echo "Error: PROG not set" >&2
    exit 1
fi

EVENTS_DB="events"

# Usage: $PROG logs_alert_summary
logs_alert_summary()
{
    Debug "Get alert summary"

    local TODAY=$(date -d '1 day ago' '+%Y-%m-%d %H:%M:%S')
    local TLBS="system host instance"
    local SEVS="C W I"

    echo date=$(date -d '1 day ago' '+%s')
    for tbl in $TLBS
    do
        for sev in $SEVS
        do
            query="select count(message) from $tbl where severity = '$sev' and time >= '$TODAY'"
            local count=$(influx -host $(shared_id) -format csv -database "$EVENTS_DB" -execute "$query" | grep $tbl | awk -F',' '{print $3}')
            echo "${tbl}_${sev}=${count}"
        done
    done
}

# Usage: $PROG logs_system_alerts
logs_system_alerts()
{
    Debug "Get system events"

    local limit=${1:-500}

    local events=$(influx -host $(shared_id) -format json -database "$EVENTS_DB" -execute "select severity, \"key\" as eventid, message, metadata from system order by desc limit $limit" | jq -c .results[0].series[0].values)
    echo "events=$events"
}

# Usage: $PROG logs_host_alerts
logs_host_alerts()
{
    Debug "Get host alerts"

    local limit=${1:-500}

    local events=$(influx -host $(shared_id) -format json -database "$EVENTS_DB" -execute "select severity, \"key\" as eventid, message, metadata from host order by desc limit $limit" | jq -c .results[0].series[0].values)
    echo "events=$events"
}

# Usage: $PROG logs_instance_alerts
logs_instance_alerts()
{
    Debug "Get instance alerts"

    local limit=${1:-500}
    local tid=$2
    local events

    if [ -n "$tid" ]; then
        events=$(influx -host $(shared_id) -format json -database "$EVENTS_DB" -execute "select severity, \"key\" as eventid, message, metadata from instance where tenant = '$tid' order by desc limit $limit" | jq -c .results[0].series[0].values)
    else
        events=$(influx -host $(shared_id) -format json -database "$EVENTS_DB" -execute "select severity, \"key\" as eventid, message, metadata from instance order by desc limit $limit" | jq -c .results[0].series[0].values)
    fi

    echo "events=$events"
}
