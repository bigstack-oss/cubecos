# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

security_tenant_flow_abnormal_detection()
{
    local t=$1
    local p=$2
    local d=$3
    local b=$4
    local u=$5
    local l=$6

    sub="SELECT sum(bytes) FROM $DB WHERE tenant_name = '$t' AND dst_ip != '' AND src_ip != '' AND direction = '$d' AND proto = '$p' AND time > now() - $b GROUP BY time($u), tenant_id fill(none)"
    query="SELECT mean(sum) FROM ($sub) GROUP BY tenant_id"
    local base=$(influx -host $(shared_id) -format json -database "telegraf" -execute "$query" | jq -c .results[0].series[0])
    sub="SELECT sum(bytes) FROM $DB WHERE tenant_name = '$t' AND dst_ip != '' AND src_ip != '' AND direction = '$d' AND proto = '$p' AND time > now() - $b GROUP BY time($u), tenant_id fill(0)"
    query="SELECT last(sum) FROM ($sub) GROUP BY tenant_id"
    local current=$(influx -host $(shared_id) -format json -database "telegraf" -execute "$query" | jq -c .results[0].series[0])

    local cu=$(echo $current | jq .values[0][1])
    local ba=$(echo $base | jq .values[0][1])

    if [ $ba = 'null' ] ; then
        return
    fi

    local ratio=$(echo "scale=2 ; $cu/$ba" | bc)

    if (( $(echo "$ratio > $l" |bc -l) )) ; then
        local tid=$(echo $current | jq -r .tags.tenant_id)
        local curr=$(echo "scale=2 ; $cu/1000000" | bc)
        local avg=$(echo "scale=2 ; $ba/1000000" | bc)
        echo "instance,category=SDN,severity=W,key=SDN10001W,tenant_id=$tid,tenant_name=$t message=\"project \\\"$t\\\" $p $d $u network usage ${curr}MB is $ratio times higher than its $b's average ${avg}MB\",metadata=\"{ \\\"category\\\": \\\"sdn\\\", \\\"tenant\\\": \\\"$tid\\\" }\""
    fi
}

security_instance_flow_abnormal_detection()
{
    local i=$1
    local p=$2
    local d=$3
    local b=$4
    local u=$5
    local l=$6

    sub="SELECT sum(bytes) FROM $DB WHERE instance_id = '$i' AND dst_ip != '' AND src_ip != '' AND direction = '$d' AND proto = '$p' AND time > now() - $b GROUP BY time($u), instance_name fill(none)"
    query="SELECT mean(sum) FROM ($sub) GROUP BY instance_name"
    local base=$(influx -host $(shared_id) -format json -database "telegraf" -execute "$query" | jq -c .results[0].series[0])
    sub="SELECT sum(bytes) FROM $DB WHERE instance_id = '$i' AND dst_ip != '' AND src_ip != '' AND direction = '$d' AND proto = '$p' AND time > now() - $b GROUP BY time($u), instance_name fill(0)"
    query="SELECT last(sum) FROM ($sub) GROUP BY instance_name"
    local current=$(influx -host $(shared_id) -format json -database "telegraf" -execute "$query" | jq -c .results[0].series[0])
    local cu=$(echo $current | jq .values[0][1])
    local ba=$(echo $base | jq .values[0][1])

    if [ $ba = 'null' ] ; then
        return
    fi

    local ratio=$(echo "scale=2 ; $cu/$ba" | bc)

    if (( $(echo "$ratio > $l" |bc -l) )) ; then
        local n=$(echo $current | jq -r .tags.instance_name)
        local curr=$(echo "scale=2 ; $cu/1000000" | bc)
        local avg=$(echo "scale=2 ; $ba/1000000" | bc)
        echo "instance,category=SDN,severity=W,key=SDN20001W,instance_id=$i,instance_name=$n message=\"instance \\\"$n\\\" $p $d $u network usage ${curr}MB is $ratio times higher than its $b's average ${avg}MB\",metadata=\"{ \\\"category\\\": \\\"sdn\\\", \\\"instance\\\": \\\"$i\\\" }\""
    fi
}

security_flow_abnormal_detection_run()
{
    local base=$1
    local unit=$2
    local threshold=$3
    local limit=${4:-40}
    local total=$(cat /proc/cpuinfo | grep processor | wc -l)
    local quota=$(echo "100 * $limit * $total" | bc)

    # limit all cores usage to default 40% if not specified
    cgcreate -g cpu:/flowdetect
    cgset -r cpu.cfs_period_us=10000 flowdetect
    cgset -r cpu.cfs_quota_us=$quota flowdetect

    declare -a proto=("tcp" "udp")
    declare -a direction=("ingress" "egress")
    for p in "${proto[@]}" ; do
        for d in "${direction[@]}" ; do
            for t in $(influx -host $(shared_id) -format json -database telegraf -execute "select tenant_name,last(bytes) from "hc"."sflow" where time >= now() - $base group by tenant_name" | jq -r .results[].series[].tags.tenant_name 2>/dev/null) ; do
                cgexec -g cpu:flowdetect hex_sdk security_tenant_flow_abnormal_detection $t $p $d $base $unit $threshold &
            done

            for i in $(influx -host $(shared_id) -format json -database telegraf -execute "select instance_id,last(bytes) from "hc"."sflow" where time >= now() - $base group by instance_id" | jq -r .results[].series[].tags.instance_id 2>/dev/null) ; do
                cgexec -g cpu:flowdetect hex_sdk security_instance_flow_abnormal_detection $i $p $d $base $unit $threshold &
            done
        done
    done

    wait
}

security_flow_abnormal_detection()
{
    if [ ! -f /etc/appliance/state/sflow_enabled ] ; then
        return 0;
    fi

    local active_host=$(/usr/sbin/hex_config status_pacemaker | awk '/IPaddr2/{print $5}')
    if [ -n "$active_host" -a "$active_host" != "$(hostname)" ] ; then
        return 0;
    fi

    for c in $(cubectl node -r control list -j | jq -r .[].hostname) ; do
        local ctrl=$(echo $c | tr -d '\n')
        if [ "$ctrl" != "$(hostname)" ] ; then
            if ping -c 1 -w 1 $ctrl >/dev/null 2>&1 ; then
                break
            fi
        fi
    done

    local base=$1
    local unit=$2
    local threshold=$3

    ssh $ctrl $HEX_SDK security_flow_abnormal_detection_run $base $unit $threshold 2>/dev/null
}
