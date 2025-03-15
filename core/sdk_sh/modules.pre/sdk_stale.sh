# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

stale_api_clear()
{
    local service=$1
    local port=$2
    local binary_ss=${3:-$service}
    local binary_ns=${4:-$service}
    local qlen=${5:-10}
    local clear=0

    # check if receive queue full via ss
    ss -lntp | grep "LISTEN.*:$port .*$binary_ss" | while read -r recvq_ss ; do
        local q=$(echo $recvq_ss | awk '{print $2}')
        if [ -n "$q" -a $q -gt $qlen ]; then
            local pid=$(echo "$recvq_ss" | awk -F',' '{print $2}' | awk -F'=' '{print $2}')
            kill -9 $pid
            clear=1
        fi
    done

    # check if receive queue full via netstat
    netstat -lntp | grep "tcp.*:$port .*$binary_ns" | while read -r recvq_ns ; do
        local q=$(echo $recvq_ns | awk '{print $2}')
        if [ -n "$q" -a $q -gt $qlen ]; then
            local pid=$(echo "$recvq_ns" | awk '{print $7}' | awk -F'/' '{print $1}')
            kill -9 $pid
            clear=1
        fi
    done

    return $clear
}

stale_api_check_repair()
{
    local service=$1
    local port=$2
    local binary_ss=${3:-$service}
    local binary_ns=${4:-$service}
    local qlen=${5:-3}
    local clear=0

    while : ; do
        stale_api_clear $service $port $binary_ss $binary_ns $qlen
        local r=$?
        if [ $r -eq 0 ]; then
            break
        else
            clear=1
        fi
    done

    if [ $clear -eq 1 ]; then
        systemctl restart $service
        hex_log_event -e SRV01002I hostname=$(hostname),service=$service,port=$port
    fi
}

stale_repair_clear()
{
    local pid=$(cat $CLUSTER_REPAIRING 2>/dev/null)
    if [ "x$pid" = "x" ]; then
        rm -f $CLUSTER_REPAIRING
    else
        if Quiet ps -p $pid 2>/dev/null ; then
            if [ "x$(find $CLUSTER_REPAIRING -cmin +30)" = "x$CLUSTER_REPAIRING" ]; then
                Quiet -n pkill -9 -P $pid
                rm -f $(readlink $CLUSTER_REPAIRING) $CLUSTER_REPAIRING
            fi
        else
            ps awwx | grep "${HEX_SDK}.*health_link_repair"
            for pid in $(ps awwx | grep "${HEX_SDK}.*health_link_repair" 2>/dev/null | awk '{print $1}'); do
                ! Quiet ps -p $pid 2>/dev/null || Quiet -n pkill -9 -P $pid
            done
            rm -f $(readlink $CLUSTER_REPAIRING) $CLUSTER_REPAIRING
        fi
    fi
}
