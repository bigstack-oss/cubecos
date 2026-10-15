# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

stats_safe_echo()
{
    local key=$1
    local value=$2
    local def=$3

    if [ -n "$value" -a "$value" != "null" ] ; then
        echo "$key=$value"
    else
        echo "$key=$def"
    fi
}

# Prunes per-VM series whose instance has stopped reporting. The per-VM measurements moved
# from the monasca database to telegraf.def when monasca was removed (issue #672), and
# `hex_sdk instance_metrics_collect` is what writes them now -- including
# vm.host_alive_status, which exists precisely so this function has a liveness signal to key
# on rather than having to know which of the per-VM measurements is the reliable one.
#
# `drop series where resource_id = ...` is database-wide: it spans every measurement and
# every retention policy in the database, so moving these series out of a database monasca
# had to itself and into the shared telegraf one widened what that statement can reach. It
# is still safe because nothing else in telegraf carries the tag. Measured on jim-1cc and
# accept-3cc, `SHOW SERIES` returns resource_id on exactly the seven vm.* measurements
# instance_metrics_collect writes and on nothing else -- the host and cluster series key on
# other tags entirely (node.health on `node`, vm.health on `id`, the ceph_* and the telegraf
# input measurements on `host`), so none of them is a candidate for deletion at any value of
# $rid. That is the invariant to preserve: resource_id in the telegraf database means an
# instance UUID, so a new writer must not reuse the tag name for another kind of object.
stats_inactive_vm_drop()
{
    local time=$1
    local active=$(influx -host $(shared_id) -format json -database $TELEGRAF_DB -execute "select resource_id,last(value) from \"vm.host_alive_status\" where time >= now() - $time group by resource_id" | jq -r .results[].series[].tags.resource_id 2>/dev/null | tr '\n' ',')

    readarray rid_array <<< "$(influx -host $(shared_id) -format json -database $TELEGRAF_DB -execute "select resource_id,last(value) from \"vm.host_alive_status\" group by resource_id" | jq -r .results[].series[].tags.resource_id 2>/dev/null)"
    declare -p rid_array > /dev/null
    for rid_entry in "${rid_array[@]}" ; do
        local rid=$(echo $rid_entry | tr -d '\n')
        [ ! -n "$rid" ] && continue
        if ! echo ",$active" | grep -q ",$rid," ; then
            echo "drop stats of vm resource $rid"
            influx -host $(shared_id) -format json -database $TELEGRAF_DB -execute "drop series where resource_id = '$rid'" >/dev/null
        fi
    done
}

stats_inactive_router_drop()
{
    local time=$1
    local active=$(influx -host $(shared_id) -format json -database $TELEGRAF_DB -execute "select last(sess_count) from \"vrouter.stats\" where time >= now() - $time group by router" | jq -r .results[].series[].tags.router 2>/dev/null | tr '\n' ',')

    readarray rid_array <<< "$(influx -host $(shared_id) -format json -database $TELEGRAF_DB -execute "select last(sess_count) from \"vrouter.stats\" group by router" | jq -r .results[].series[].tags.router 2>/dev/null)"
    declare -p rid_array > /dev/null
    for rid_entry in "${rid_array[@]}" ; do
        local rid=$(echo $rid_entry | tr -d '\n')
        [ ! -n "$rid" ] && continue
        if ! echo ",$active" | grep -q ",$rid," ; then
            echo "drop stats of router resource $rid"
            influx -host $(shared_id) -format json -database $TELEGRAF_DB -execute "drop series where router = '$rid'" >/dev/null
        fi
    done
}

# Usage: $PROG stats_cluster_cpu_usage
stats_cluster_cpu_usage()
{
    Debug "Get cluster cpu usage"

    # cluster cpu usage (1m)
    local total=$(influx -host $(shared_id) -format json -database "$TELEGRAF_DB" -execute "select last(mean) from (select 100 - mean(usage_idle) from cpu where time > now() - 2m group by time(60s) fill(none))" | jq .results[0].series[0].values[-1][1])
    echo "total=$total"

    # cpu usage trend
    local trend=$(influx -host $(shared_id) -format json -database "$TELEGRAF_DB" -execute "select difference(mean) from (select 100 - mean(usage_idle) from cpu where time > now() - 3m group by time(60s) fill(none))" | jq .results[0].series[0].values[-1][1])
    echo "trend=$trend"

    # cpu usage last (1hr)
    local chart=$(influx -host $(shared_id) -format json -database "$TELEGRAF_DB" -execute "select 100 - mean(usage_idle) from cpu where time > now() - 62m group by time(60s) fill(none)" | jq -c .results[0].series[0].values)
    echo "chart=$chart"
}

# Usage: $PROG stats_cluster_mem_usage
stats_cluster_mem_usage()
{
    Debug "Get cluster memory usage"

    # cluster memory usage (1m)
    local total=$(influx -host $(shared_id) -format json -database "$TELEGRAF_DB" -execute "select last(mean_mean) from (select mean(used) * 100 / mean(total) from mem where time > now() - 2m group by time(60s) fill(none))" | jq .results[0].series[0].values[-1][1])
    echo "total=$total"

    # memory usage trend
    local trend=$(influx -host $(shared_id) -format json -database "$TELEGRAF_DB" -execute "select difference(mean_mean) from (select mean(used) * 100 / mean(total) from mem where time > now() - 3m group by time(60s) fill(none))" | jq .results[0].series[0].values[-1][1])
    echo "trend=$trend"

    # memory usage last (1hr)
    local chart=$(influx -host $(shared_id) -format json -database "$TELEGRAF_DB" -execute "select mean(used) * 100 / mean(total) from mem where time > now() - 62m group by time(60s) fill(none)" | jq -c .results[0].series[0].values)
    echo "chart=$chart"
}

# Usage: $PROG stats_op_summary
stats_op_summary()
{
    Debug "Get cluster cpu memory storage summary"

    SHELL_TMPFILE=$(mktemp /tmp/shell.XXXXXX)
    openstack hypervisor stats show -f shell --prefix hypervisors_stats_ | gawk '{gsub("\"","") ; print $0}' > $SHELL_TMPFILE
    source $SHELL_TMPFILE
    rm -f $SHELL_TMPFILE
    unset SHELL_TMPFILE
    echo "vcpu_total=$hypervisors_stats_vcpus"
    echo "vcpu_used=$hypervisors_stats_vcpus_used"
    echo "memory_mb_total=$hypervisors_stats_memory_mb"
    echo "memory_mb_used=$hypervisors_stats_memory_mb_used"

    local ceph_df=$($CEPH df -f json)
    local storage_bytes_total=$(echo $ceph_df | jq -c .stats.total_bytes)
    local storage_bytes_used=$(echo $ceph_df | jq -c .stats.total_used_bytes)
    echo "storage_bytes_total=$storage_bytes_total"
    echo "storage_bytes_used=$storage_bytes_used"
}

# Usage: $PROG stats_infra_summary
stats_infra_summary()
{
    Debug "Get infrastructure summary (instance and host)"

    ORIG_IFS=$IFS
    IFS='\n'
    local compute_summary=$(openstack host list -c "Host Name" -c Service -f value | grep -v "\-ironic" | awk '{print $2}')
    local control=$(echo $compute_summary | grep scheduler | wc -l)
    local compute=$(echo $compute_summary | grep compute | wc -l)
    local storage=$(timeout 5 ceph osd status 2>&1 | grep exists | awk '{print $2}' | sort | uniq | wc -l)
    echo "role_total=$(( control + compute + storage ))"
    echo "role_control=$control"
    echo "role_compute=$compute"
    echo "role_storage=$storage"

    local vm_summary=$(openstack server list --all-projects --format value -c Status)
    echo "vm_running=$(echo $vm_summary | grep ACTIVE | wc -l)"
    echo "vm_stopped=$(echo $vm_summary | grep SHUTOFF | wc -l)"
    echo "vm_suspended=$(echo $vm_summary | grep SUSPENDED | wc -l)"
    echo "vm_paused=$(echo $vm_summary | grep PAUSED | wc -l)"
    echo "vm_error=$(echo $vm_summary | grep ERROR | wc -l)"
    echo "vm_total=$(echo $vm_summary | grep \[ACTIVE\|SHUTOFF\|SUSPENDED\|PAUSED\|ERROR\] | wc -l )"
    IFS=$ORIG_IFS
}

# Usage: $PROG stats_topten_host
stats_topten_host()
{
    local type=$1
    local query

    Debug "Get top 10 used $type hosts"

    case $type in
        cpu)
            query="SELECT host, top(used, 10) FROM (SELECT 100 - last(usage_idle) as used FROM cpu WHERE role = 'cube' AND time > now() - 2m GROUP BY host)"
            local top10cpu=$(influx -host $(shared_id) -format json -database "$TELEGRAF_DB" -execute "$query")
            local cpu_host=$(echo $top10cpu | jq .results[0].series[0].values[][1] | tr "\n" ",")
            echo "cpu_host=[${cpu_host%,}]"
            local cpu_usage=$(echo $top10cpu | jq -r .results[0].series[0].values[][2] | tr "\n" ",")
            echo "cpu_usage=[${cpu_usage%,}]"
            ;;
        mem)
            query="SELECT host, top(used, 10) FROM (SELECT last(used_percent) as used FROM mem WHERE role = 'cube' AND time > now() - 2m GROUP BY host)"
            local top10mem=$(influx -host $(shared_id) -format json -database "$TELEGRAF_DB" -execute "$query")
            local mem_host=$(echo $top10mem | jq .results[0].series[0].values[][1] | tr "\n" ",")
            echo "mem_host=[${mem_host%,}]"
            local mem_usage=$(echo $top10mem | jq -r .results[0].series[0].values[][2] | tr "\n" ",")
            echo "mem_usage=[${mem_usage%,}]"
            ;;
        disk)
            query="SELECT host, top(used, 10) FROM (SELECT last(used_percent) as used FROM disk WHERE role = 'cube' AND time > now() - 2m GROUP BY host)"
            local top10disk=$(influx -host $(shared_id) -format json -database "$TELEGRAF_DB" -execute "$query")
            local disk_host=$(echo $top10disk | jq .results[0].series[0].values[][1] | tr "\n" ",")
            echo "disk_host=[${disk_host%,}]"
            local disk_usage=$(echo $top10disk | jq -r .results[0].series[0].values[][2] | tr "\n" ",")
            echo "disk_usage=[${disk_usage%,}]"
            ;;
        netin)
            query="SELECT host, top(used, 10) FROM (SELECT (non_negative_derivative * 8) as used, host FROM (SELECT non_negative_derivative(sum(bytes_recv), 1s) FROM net WHERE interface =~ /^eth[0-9]+$/ AND role = 'cube' AND time > now() - 1m GROUP BY host, time(1m)))"
            local top10in=$(influx -host $(shared_id) -format json -database "$TELEGRAF_DB" -execute "$query")
            local in_host=$(echo $top10in | jq .results[0].series[0].values[][1] | tr "\n" ",")
            echo "in_host=[${in_host%,}]"
            local in_usage=$(echo $top10in | jq -r .results[0].series[0].values[][2] | tr "\n" ",")
            echo "in_usage=[${in_usage%,}]"
            ;;
        netout)
            query="SELECT host, top(used, 10) FROM (SELECT (non_negative_derivative * 8) as used, host FROM (SELECT non_negative_derivative(sum(bytes_sent), 1s) FROM net WHERE interface =~ /^eth[0-9]+$/ AND role = 'cube' AND time > now() - 1m GROUP BY host, time(1m)))"
            local top10out=$(influx -host $(shared_id) -format json -database "$TELEGRAF_DB" -execute "$query")
            local out_host=$(echo $top10out | jq .results[0].series[0].values[][1] | tr "\n" ",")
            echo "out_host=[${out_host%,}]"
            local out_usage=$(echo $top10out | jq -r .results[0].series[0].values[][2] | tr "\n" ",")
            echo "out_usage=[${out_usage%,}]"
            ;;
    esac
}

stats_host_chart()
{
    local host=$1
    local type=$2
    local query

    case $type in
        cpu)
            query="SELECT 100 - usage_idle as used FROM cpu WHERE host = '$host' and time > now() - 1h"
            ;;
        mem)
            query="SELECT used_percent as used FROM mem WHERE host = '$host' and time > now() - 1h"
            ;;
        disk)
            query="SELECT used_percent as used FROM disk WHERE host = '$host' and time > now() - 1h"
            ;;
        netin)
            query="SELECT non_negative_derivative(sum(bytes_recv), 1s) * 8 FROM net WHERE host ='$host' and interface =~ /^eth[0-9]+$/ and time > now() - 1h GROUP BY time(1m)"
            ;;
        netout)
            query="SELECT non_negative_derivative(sum(bytes_sent), 1s) * 8 FROM net WHERE host ='$host' and interface =~ /^eth[0-9]+$/ and time > now() - 1h GROUP BY time(1m)"
            ;;
    esac
    local chart=$(influx -host $(shared_id) -format json -database "$TELEGRAF_DB" -execute "$query" | jq -c .results[0].series[0].values)
    echo "chart=$chart"
}

# Usage: $PROG stats_topten_vm
stats_topten_vm()
{
    local type=$1
    local query

    Debug "Get top 10 used $type hosts"

    case $type in
        cpu)
            query="SELECT resource_id, vm_name, top(used, 10) FROM (SELECT last(value) as used FROM \"vm.cpu.utilization_norm_perc\" WHERE time > now() - 5m GROUP BY resource_id, vm_name)"
            ;;
        mem)
            query="SELECT resource_id, vm_name, top(used, 10) FROM (SELECT 100 - last(value) as used FROM \"vm.mem.free_perc\" WHERE time > now() - 5m GROUP BY resource_id, vm_name)"
            ;;
        diskr)
            query="SELECT resource_id, vm_name, top(used, 10), device FROM (SELECT last(value) as used FROM \"vm.io.read_bytes_sec\" WHERE time > now() - 5m GROUP BY resource_id, vm_name, device)"
            ;;
        diskw)
            query="SELECT resource_id, vm_name, top(used, 10), device FROM (SELECT last(value) as used FROM \"vm.io.write_bytes_sec\" WHERE time > now() - 5m GROUP BY resource_id, vm_name, device)"
            ;;
        netin)
            query="SELECT resource_id, vm_name, top(used, 10), device FROM (SELECT last(value) * 8 as used FROM \"vm.net.in_bytes_sec\" WHERE time > now() - 5m GROUP BY resource_id, vm_name, device)"
            ;;
        netout)
            query="SELECT resource_id, vm_name, top(used, 10), device FROM (SELECT last(value) * 8 as used FROM \"vm.net.out_bytes_sec\" WHERE time > now() - 5m GROUP BY resource_id, vm_name, device)"
            ;;
    esac

    local topten=$(influx -host $(shared_id) -format json -database "$TELEGRAF_DB" -execute "$query")
    local rcs_id=$(echo $topten | jq .results[0].series[0].values[][1] | tr "\n" ",")
    echo "rcs_id=[${rcs_id%,}]"
    local vm_name=$(echo $topten | jq .results[0].series[0].values[][2] | tr "\n" ",")
    echo "vm_name=[${vm_name%,}]"
    local usage=$(echo $topten | jq -r .results[0].series[0].values[][3] | tr "\n" ",")
    echo "usage=[${usage%,}]"

    case $type in
        diskr|diskw|netin|netout)
            local device=$(echo $topten | jq .results[0].series[0].values[][4] | tr "\n" ",")
            echo "device=[${device%,}]"
            ;;
    esac
}

stats_vm_chart()
{
    local resource_id=$1
    local type=$2
    local device=${3:-none}
    local query

    case $type in
        cpu)
            query="select value from \"vm.cpu.utilization_norm_perc\" where resource_id = '$resource_id' and time > now() - 1h"
            ;;
        mem)
            query="select 100 - value from \"vm.mem.free_perc\" where resource_id = '$resource_id' and time > now() - 1h"
            ;;
        diskr)
            query="select value from \"vm.io.read_bytes_sec\" where resource_id = '$resource_id' and device = '$device' and time > now() - 1h"
            ;;
        diskw)
            query="select value from \"vm.io.write_bytes_sec\" where resource_id = '$resource_id' and device = '$device' and time > now() - 1h"
            ;;
        netin)
            query="select value * 8 from \"vm.net.in_bytes_sec\" where resource_id = '$resource_id' and device = '$device' and time > now() - 1h"
            ;;
        netout)
            query="select value * 8 from \"vm.net.out_bytes_sec\" where resource_id = '$resource_id' and device = '$device' and time > now() - 1h"
            ;;
    esac
    local chart=$(influx -host $(shared_id) -format json -database "$TELEGRAF_DB" -execute "$query" | jq -c .results[0].series[0].values)
    echo "chart=$chart"
}

stats_ceph_osd_cmd()
{
    local stats=$($CEPH -s -f json 2>/dev/null)

    if [ -n "$stats" ] ; then
        local epoch=$(echo $stats | jq .osdmap.epoch)
        local num_osds=$(echo $stats | jq .osdmap.num_osds)
        local num_up_osds=$(echo $stats | jq .osdmap.num_up_osds)
        local num_in_osds=$(echo $stats | jq .osdmap.num_in_osds)
        local num_remapped_pgs=$(echo $stats | jq .osdmap.num_remapped_pgs)
        echo "ceph_osdmap_cmd,host=$HOSTNAME epoch=$epoch,num_osds=$num_osds,num_up_osds=$num_up_osds,num_in_osds=$num_in_osds,num_remapped_pgs=$num_remapped_pgs"
    fi
}

stats_bootstrap()
{
    local flg="-v"
    if [ "x$FORMAT" = "xjson" ] ; then
        flg+="j"
    fi

    cmd $flg "cat -v /run/cube_bootstrap.log 2>/dev/null | sed 's/ \^M//g' ; egrep -v -q -i 'fail|error' /run/cube_bootstrap.log 2>/dev/null"
}

stats_partition()
{
    local mpt=/mnt/target
    local log=$mpt/var/log/install.log
    local num_node=${#CUBE_NODE_LIST_HOSTNAMES[@]}

    cmd MountOtherPartition

    local num_success=$(cmd -v "grep '^Firmware .* has been updated with success' $log" | cut -d "|" -f2 | grep "^0$" | wc -l)
    if [ $num_success -eq $num_node ] ; then
        [ "x$VERBOSE" != "x1" ] || echo "Firmware update ${num_success}/${num_node} succeeded. Evacuate all VMs, if any, before rebooting master control."
        return 0
    elif [ $num_success -gt 0 -a $num_success -lt $num_node ] ; then
        [ "x$VERBOSE" != "x1" ] || echo "Firmware update failed with only ${num_success}/${num_node} nodes successfully partitioned. On the failed nodes, run CLI update update."
        return 1
    elif ! cmd "mountpoint -- $mpt" ; then
        [ "x$VERBOSE" != "x1" ] || echo "Firmware update failed with target partition corrupted. If some nodes succeeded, run CLI update update on failed nodes. Otherwise, confirm firmware source, verify checksum and disk health."
        return 2
    else
        [ "x$VERBOSE" != "x1" ] || echo "Firmware update failed with unknown errors that need to be investigated"
        return 3
    fi
    cmd "umount $mpt"
}

# On boot, copy the events the kapacitor relay missed while this node was down
# from the peers' InfluxDB into the local one (overwrites are idempotent).
STATS_KAPACITOR_CONF=/etc/kapacitor/kapacitor.conf
STATS_PROC_STAT=/proc/stat
STATS_EVENTS_CATCHUP_LOCK=/run/lock/stats_events_catchup.lock
# seconds per query
STATS_EVENTS_CATCHUP_SLICE=3600
# relay lag margin around the gap
STATS_EVENTS_CATCHUP_MARGIN=600
# gap end when no local point after boot: at most this long after boot
STATS_EVENTS_CATCHUP_MAX_GAP=7200
# wall-clock budget for the whole catch-up
STATS_EVENTS_CATCHUP_BUDGET=900
STATS_LOCAL_INFLUX=http://localhost:8086

# Peer InfluxDB urls from kapacitor.conf, localhost excluded
_stats_influx_peer_urls()
{
    awk '/^\[/{s=($0 ~ /^\[\[influxdb\]\]/)} s && /^[ \t]*urls[ \t]*=/' "$STATS_KAPACITOR_CONF" 2>/dev/null | \
        grep -o 'http://[^"]*' | grep -v '//localhost[:/]'
}

# Query an events db, epoch=ns JSON on stdout
_stats_influx_query()
{
    curl -sf -m 60 -G "$1/query" --data-urlencode db=events --data-urlencode epoch=ns --data-urlencode "q=$2"
}

# SHOW TAG KEYS JSON in $1, SHOW FIELD KEYS JSON in $2 (one measurement) -> column spec
# [[name, "field", [types]], ..., [name, "tag", null], ...]
_stats_influx_columns()
{
    python3 -c '
import json, sys
def vals(j):
    return [v for s in json.loads(j or "{}").get("results", [{}])[0].get("series", []) for v in s["values"]]
fields = {}
for k, t in vals(sys.argv[2]):
    fields.setdefault(k, []).append(t)
spec = [[k, "field", t] for k, t in fields.items()] + [[v[0], "tag", None] for v in vals(sys.argv[1])]
print(json.dumps(spec) if fields else "")
' "$1" "$2"
}

# Column spec in $1 -> explicit "k"::field,...,"k"::tag select list
_stats_influx_select()
{
    printf '%s' "$1" | jq -r 'map("\"" + (.[0] | gsub("\""; "\\\"")) + "\"::" + .[1]) | join(",")'
}

# Query JSON (explicit select in spec order, no GROUP BY) on stdin, column spec in $1 -> line protocol.
# Columns are classified by position, so a tag and a field sharing a name stay apart.
_stats_influx_json_to_lp()
{
    python3 -c '
import json, sys
spec = json.loads(sys.argv[1])
def esc(s, chars):
    for c in chars:
        s = s.replace(c, "\\" + c)
    return s
def ftype(v, ts):
    if len(ts) == 1:
        return ts[0]
    if isinstance(v, str):
        return "string"
    if isinstance(v, bool):
        return "boolean"
    if isinstance(v, int) and "integer" in ts:
        return "integer"
    return "float"
def fval(v, t):
    if t == "string":
        return "\"" + str(v).replace("\\", "\\\\").replace("\"", "\\\"") + "\""
    if t == "boolean":
        return "true" if v else "false"
    if t == "integer":
        return "%di" % v
    if t == "unsigned":
        return "%du" % v
    return repr(float(v))
for r in json.load(sys.stdin).get("results", []):
    for s in r.get("series", []):
        m = s["name"]
        if len(s["columns"]) != len(spec) + 1:
            sys.exit("column mismatch in " + m)
        for row in s["values"]:
            tags, fs = [], []
            for (k, kind, ts), v in zip(spec, row[1:]):
                if v is None:
                    continue
                if kind == "tag":
                    if v != "":
                        tags.append(esc(k, ", =") + "=" + esc(str(v), ", ="))
                else:
                    fs.append(esc(k, ", =") + "=" + fval(v, ftype(v, ts)))
            if fs:
                print(esc(m, ", ") + "".join("," + t for t in sorted(tags)) + " " + ",".join(fs) + " " + str(row[0]))
' "$1"
}

# Newest (DESC) or oldest local point time in s for a WHERE clause, empty if none
_stats_influx_local_edge()
{
    _stats_influx_query "$STATS_LOCAL_INFLUX" "SELECT * FROM \"def\"./.*/ WHERE $1 ${2:+ORDER BY time $2 }LIMIT 1" | \
        jq -r "[.results[0].series[]?.values[0][0]] | ${3:-max} // empty | . / 1e9 | floor" 2>/dev/null
}

stats_events_catchup()
{
    systemctl -q is-active influxdb || return 0
    local peers=$(_stats_influx_peer_urls)
    [ -n "$peers" ] || return 0
    exec 9>"$STATS_EVENTS_CATCHUP_LOCK"
    flock -n 9 || return 0

    local btime=$(awk '/^btime/{print $2}' "$STATS_PROC_STAT")
    local t0=$(date +%s)
    local deadline=$((t0 + STATS_EVENTS_CATCHUP_BUDGET))
    [ -n "$btime" ] || return 0
    # gap: last local point before this boot .. first local point after it, each with margin
    local mg=$STATS_EVENTS_CATCHUP_MARGIN start end last first
    last=$(_stats_influx_local_edge "time < ${btime}s AND time > $((btime - 7 * 86400))s" DESC max)
    first=$(_stats_influx_local_edge "time >= ${btime}s AND time < $((btime + STATS_EVENTS_CATCHUP_MAX_GAP))s" "" min)
    if [ -n "$last" ] ; then
        start=$((last - mg))
    else
        start=$((btime - 3600))
    fi
    if [ -n "$first" ] ; then
        end=$((first + mg))
    else
        end=$((btime + STATS_EVENTS_CATCHUP_MAX_GAP))
    fi
    [ $end -le $t0 ] || end=$t0
    [ $start -ge $((t0 - 7 * 86400)) ] || start=$((t0 - 7 * 86400))
    [ $start -lt $end ] || return 0
    log_info "events catch-up: copying $(date -d @$start '+%F %T') .. $(date -d @$end '+%F %T') from peers"

    local url rp m t te ms tk fk spec sel res lp n=0 skip=0 stop=""
    for url in $peers ; do
        [ -z "$stop" ] || break
        ms=$(_stats_influx_query "$url" "SHOW MEASUREMENTS" | jq -r '.results[0].series[0].values[]?[0]' 2>/dev/null)
        [ -n "$ms" ] || { log_warning "events catch-up: $url unreachable" ; continue ; }
        for m in $ms ; do
            [ -z "$stop" ] || break
            tk=$(_stats_influx_query "$url" "SHOW TAG KEYS FROM \"$m\"")
            fk=$(_stats_influx_query "$url" "SHOW FIELD KEYS FROM \"$m\"")
            spec=$(_stats_influx_columns "$tk" "$fk")
            [ -n "$spec" ] || { log_warning "events catch-up: no field keys of $m from $url, skipped" ; skip=$((skip + 1)) ; continue ; }
            sel=$(_stats_influx_select "$spec")
            for rp in def hc ; do
                for ((t = start ; t < end ; t += STATS_EVENTS_CATCHUP_SLICE)) ; do
                    if [ $(date +%s) -ge $deadline ] ; then
                        stop=" (stopped at the ${STATS_EVENTS_CATCHUP_BUDGET}s budget)"
                        break 3
                    fi
                    te=$((t + STATS_EVENTS_CATCHUP_SLICE < end ? t + STATS_EVENTS_CATCHUP_SLICE : end))
                    res=$(_stats_influx_query "$url" "SELECT $sel FROM \"$rp\".\"$m\" WHERE time >= ${t}s AND time < ${te}s")
                    if [ -z "$res" ] ; then
                        log_warning "events catch-up: $rp.$m $(date -d @$t '+%T') from $url: no answer, skipped"
                        skip=$((skip + 1))
                        continue
                    fi
                    lp=$(printf '%s' "$res" | _stats_influx_json_to_lp "$spec") || { skip=$((skip + 1)) ; continue ; }
                    [ -n "$lp" ] || continue
                    if printf '%s\n' "$lp" | curl -sf -m 120 -XPOST "$STATS_LOCAL_INFLUX/write?db=events&rp=$rp&precision=ns" --data-binary @- >/dev/null ; then
                        n=$((n + $(printf '%s\n' "$lp" | wc -l)))
                    else
                        log_warning "events catch-up: local write of $rp.$m from $url failed"
                        skip=$((skip + 1))
                    fi
                done
            done
        done
    done
    log_info "events catch-up: $n points copied, $skip slices skipped in $(( $(date +%s) - t0 ))s$stop"
}
