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

stats_inactive_vm_drop()
{
    local time=$1
    local active=$(influx -host $(shared_id) -format json -database $MONASCA_DB -execute "select resource_id,last(value) from \"vm.host_alive_status\" where time >= now() - $time group by resource_id" | jq -r .results[].series[].tags.resource_id 2>/dev/null | tr '\n' ',')

    readarray rid_array <<< "$(influx -host $(shared_id) -format json -database $MONASCA_DB -execute "select resource_id,last(value) from \"vm.host_alive_status\" group by resource_id" | jq -r .results[].series[].tags.resource_id 2>/dev/null)"
    declare -p rid_array > /dev/null
    for rid_entry in "${rid_array[@]}" ; do
        local rid=$(echo $rid_entry | tr -d '\n')
        [ ! -n "$rid" ] && continue
        if ! echo ",$active" | grep -q ",$rid," ; then
            echo "drop stats of vm resource $rid"
            influx -host $(shared_id) -format json -database $MONASCA_DB -execute "drop series where resource_id = '$rid'" >/dev/null
        fi
    done

    active=$(influx -host $(shared_id) -format json -database $TELEGRAF_DB -execute "select instance_id,last(bytes) from \"hc\".\"sflow\" where time >= now() - $time group by instance_id" | jq -r .results[].series[].tags.instance_id 2>/dev/null | tr '\n' ',')

    readarray rid_array <<< "$(influx -host $(shared_id) -format json -database $TELEGRAF_DB -execute "select instance_id,last(bytes) from \"hc\".\"sflow\" group by instance_id" | jq -r .results[].series[].tags.instance_id 2>/dev/null)"
    declare -p rid_array > /dev/null
    for rid_entry in "${rid_array[@]}" ; do
        local rid=$(echo $rid_entry | tr -d '\n')
        [ ! -n "$rid" ] && continue
        if ! echo ",$active" | grep -q ",$rid," ; then
            echo "drop sflow stats of vm resource $rid"
            influx -host $(shared_id) -format json -database $TELEGRAF_DB -execute "drop series where instance_id = '$rid'" >/dev/null
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

# Usage: $PROG stats_storage_bandwidth_usage
stats_storage_bandwidth_usage()
{
    Debug "Get storage bandwidth usage"

    local query=""
    local sub=""

    # bandwidth current usage (1m)
    query="SELECT non_negative_derivative(sum(value),1s) as rate FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_r_out_bytes' AND time > now() - 3m) GROUP BY time(60s) fill(none)"
    local read_rate=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq .results[0].series[0].values[-1][1])
    echo "read_rate=$read_rate"
    query="SELECT non_negative_derivative(sum(value),1s) as rate FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_w_in_bytes' AND time > now() - 3m) GROUP BY time(60s) fill(none)"
    local write_rate=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq .results[0].series[0].values[-1][1])
    echo "write_rate=$write_rate"

    # bandwidth trend
    sub="SELECT non_negative_derivative(sum(value),1s) as rate FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_r_out_bytes' AND time > now() - 4m) GROUP BY time(60s) fill(none)"
    query="SELECT difference(rate) FROM ($sub)"
    local read_trend=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq .results[0].series[0].values[-1][1])
    echo "read_trend=$read_trend"
    sub="SELECT non_negative_derivative(sum(value),1s) as rate FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_w_in_bytes' AND time > now() - 4m) GROUP BY time(60s) fill(none)"
    query="SELECT difference(rate) FROM ($sub)"
    local write_trend=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq .results[0].series[0].values[-1][1])
    echo "write_trend=$write_trend"

    # bandwidth chart last 1hr
    query="SELECT non_negative_derivative(sum(value),1s) as rate FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_r_out_bytes' AND time > now() - 62m) GROUP BY time(60s) fill(none)"
    local read_chart=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq -c .results[0].series[0].values)
    echo "read_chart=$read_chart"
    query="SELECT non_negative_derivative(sum(value),1s) as rate FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_w_in_bytes' AND time > now() - 62m) GROUP BY time(60s) fill(none)"
    local write_chart=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq -c .results[0].series[0].values)
    echo "write_chart=$write_chart"
}

# Usage: $PROG stats_storage_iops_usage
stats_storage_iops_usage()
{
    Debug "Get storage iops usage"

    local query=""
    local sub=""

    # iops current usage (1m)
    query="SELECT non_negative_derivative(sum(value),1s) as rate FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_r' AND time > now() - 3m) GROUP BY time(60s) fill(none)"
    local read_rate=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq .results[0].series[0].values[-1][1])
    echo "read_rate=$read_rate"
    query="SELECT non_negative_derivative(sum(value),1s) as rate FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_w' AND time > now() - 3m) GROUP BY time(60s) fill(none)"
    local write_rate=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq .results[0].series[0].values[-1][1])
    echo "write_rate=$write_rate"

    # iops trend
    sub="SELECT non_negative_derivative(sum(value),1s) as rate FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_r' AND time > now() - 4m) GROUP BY time(60s) fill(none)"
    query="SELECT difference(rate) FROM ($sub)"
    local read_trend=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq .results[0].series[0].values[-1][1])
    echo "read_trend=$read_trend"
    sub="SELECT non_negative_derivative(sum(value),1s) as rate FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_w' AND time > now() - 4m) GROUP BY time(60s) fill(none)"
    query="SELECT difference(rate) FROM ($sub)"
    local write_trend=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq .results[0].series[0].values[-1][1])
    echo "write_trend=$write_trend"

    # iops chart last 1hr
    query="SELECT non_negative_derivative(sum(value),1s) as rate FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_r' AND time > now() - 62m) GROUP BY time(60s) fill(none)"
    local read_chart=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq -c .results[0].series[0].values)
    echo "read_chart=$read_chart"
    query="SELECT non_negative_derivative(sum(value),1s) as rate FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_w' AND time > now() - 62m) GROUP BY time(60s) fill(none)"
    local write_chart=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq -c .results[0].series[0].values)
    echo "write_chart=$write_chart"
}

# Usage: $PROG stats_storage_latency_usage
stats_storage_latency_usage()
{
    Debug "Get storage latency usage"

    local query=""
    local sub=""

    # latency data (1m)
    sub="SELECT sum(value) FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_r' AND time > now() - 62m) GROUP BY time(60s) fill(none)"
    query="SELECT difference(sum) FROM ($sub)"
    local read_op=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq -c .results[0].series[0].values)
    stats_safe_echo "read_op" "$read_op" "[[0, 0],[0, 0]]"
    sub="SELECT sum(value) FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_r_latency' AND time > now() - 62m) GROUP BY time(60s) fill(none)"
    query="SELECT difference(sum) FROM ($sub)"
    local read_latency=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq -c .results[0].series[0].values)
    stats_safe_echo "read_latency" "$read_latency" "[[0, 0],[0, 0]]"

    sub="SELECT sum(value) FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_w' AND time > now() - 62m) GROUP BY time(60s) fill(none)"
    query="SELECT difference(sum) FROM ($sub)"
    local write_op=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq -c .results[0].series[0].values)
    stats_safe_echo "write_op" "$write_op" "[[0, 0],[0, 0]]"
    sub="SELECT sum(value) FROM ceph_daemon_stats WHERE (ceph_daemon =~ /^osd\.[0-9]+$/ AND type_instance = 'osd.op_w_latency' AND time > now() - 62m) GROUP BY time(60s) fill(none)"
    query="SELECT difference(sum) FROM ($sub)"
    local write_latency=$(influx -host $(shared_id) -format json -database "$CEPH_DB" -execute "$query" | jq -c .results[0].series[0].values)
    stats_safe_echo "write_latency" "$write_latency" "[[0, 0],[0, 0]]"
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

    local topten=$(influx -host $(shared_id) -format json -database "$MONASCA_DB" -execute "$query")
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
    local chart=$(influx -host $(shared_id) -format json -database "$MONASCA_DB" -execute "$query" | jq -c .results[0].series[0].values)
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
