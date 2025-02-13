# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ]; then
    echo "Error: PROG not set" >&2
    exit 1
fi

if [ -f /etc/admin-openrc.sh  ]; then
    . /etc/admin-openrc.sh
fi

# _check is invoked by lmi which lacks of persmissions of running
# ssh commands like is_remote_running, wrap with /usr/sbin/hex_config sdk_run

# share

shared_id()
{
    if [ ! -f /run/shared_id ]; then
        source hex_tuning /etc/settings.txt cubesys.control.vip
        local shared_id=$T_cubesys_control_vip
        if [ -z "$shared_id" ]; then
            shared_id=$(hostname)
        fi

        echo -n $shared_id > /run/shared_id
    fi

    cat /run/shared_id
}

is_running()
{
    systemctl show -p SubState $1 | grep -q running
}

is_remote_running()
{
    ssh root@$1 /usr/sbin/hex_sdk is_running $2 >/dev/null 2>&1
}

is_active()
{
    systemctl show -p SubState $1 | grep -q active
}

is_remote_active()
{
    ssh root@$1 /usr/sbin/hex_sdk is_active $2 >/dev/null 2>&1
}

remote_systemd_stop()
{
    local host=$1
    shift 1
    timeout $SRVTO ssh root@$host systemctl stop $@ >/dev/null 2>&1
}

remote_systemd_start()
{
    local host=$1
    shift 1
    timeout $SRVTO ssh root@$host systemctl reset-failed >/dev/null 2>&1
    timeout $SRVLTO ssh root@$host systemctl start $@ >/dev/null 2>&1
}

remote_systemd_restart()
{
    local host=$1
    shift 1
    timeout $SRVTO ssh root@$host systemctl reset-failed >/dev/null 2>&1
    timeout $SRVLTO ssh root@$host systemctl restart $@ >/dev/null 2>&1
}

remote_run()
{
    local host=$1
    shift 1
    ssh root@$host $@ 2>/dev/null
}

ntp_makestep()
{
    if systemctl restart chronyd >/dev/null 2>&1; then
        sleep 5
        /sbin/hwclock -w -u
    fi
}

rabbitmq_queue_status()
{
    local RBT_VER=$(rabbitmqctl --version)
    cp -f /var/lib/rabbitmq/.erlang.cookie /root/
    cp -f /var/lib/rabbitmq/.erlang.cookie /tmp/
    rabbitmqctl list_queues -s | awk '{ print $1 }' | xargs -L1 -P8 /usr/lib/rabbitmq/lib/rabbitmq_server-${RBT_VER}/escript/rabbitmq-queues quorum_status
}

rabbitmq_quorum_queue_set()
{
    local name=$1
    local RBT_VER=$(rabbitmqctl --version)

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        env LANG=en_US.utf8 HOSTNAME=$(hostname) /usr/lib/rabbitmq/lib/rabbitmq_server-${RBT_VER}/escript/rabbitmq-queues add_member $name rabbit@$ctrl -q
    done
}

rabbitmq_queue_repair()
{
    cp -f /var/lib/rabbitmq/.erlang.cookie /root/
    cp -f /var/lib/rabbitmq/.erlang.cookie /tmp/.erlang.cookie
    env LANG=en_US.utf8 HOSTNAME=$(hostname) /usr/sbin/rabbitmqctl list_queues -s | awk '{ print $1 }' | xargs -L1 -P8 /usr/sbin/hex_sdk rabbitmq_quorum_queue_set
}

rabbitmq_unhealthy_queue_clear()
{
    readarray queue_array <<<"$(env LANG=en_US.utf8 HOSTNAME=$(hostname) /usr/sbin/rabbitmqctl list_unresponsive_queues | sed '1,2d')"
    declare -p queue_array > /dev/null
    for queue in "${queue_array[@]}"
    do
        local q=$(echo $queue | head -c -1)
        if [ -n "$q" ]; then
            env LANG=en_US.utf8 HOSTNAME=$(hostname) /usr/sbin/rabbitmqctl eval '{ok,Q} = rabbit_amqqueue:lookup(rabbit_misc:r(<<"/">>,queue,<<"'$q'">>)),rabbit_amqqueue:delete_crashed(Q).'
        fi
    done

    readarray orphant_array <<<"$(env LANG=en_US.utf8 HOSTNAME=$(hostname) /usr/sbin/rabbitmqctl list_queues consumers name | sed '1,3d' | grep "^0" | awk '{print $2}')"
    declare -p orphant_array > /dev/null
    for orphant in "${orphant_array[@]}"
    do
        local o=$(echo $orphant | head -c -1)
        if [ -n "$o" ]; then
            env LANG=en_US.utf8 HOSTNAME=$(hostname) /usr/sbin/rabbitmqctl delete_queue $o 2>&1 >/dev/null
        fi
    done
}

mysql_stats()
{
    $MYSQL -u root -e "show global status like 'wsrep_%'"
}

mysql_clear()
{
    local JAIL_USER=$($MYSQL -sNe "select host from mysql.user where host like '%-jail'")
    if [ "x$JAIL_USER" != "x" ]; then
        $MYSQL -sNe "DROP USER 'root'@'$JAIL_USER'"
    fi
}

haproxy_stats()
{
    echo "show stat" | nc -U $1 | cut -d "," -f 1,2,37  | column -s, -t | grep -v "BACKEND\|FRONTEND"
}

opensearch_stats()
{
    $CURL http://localhost:9200/_cluster/health | jq -r .
    printf "\n"
}

opensearch_index_list()
{
    $CURL http://localhost:9200/_cat/indices?v
    printf "\n"
}

opensearch_index_curator()
{
    local rp=${1:-14}
    local dryrun=$2
    /usr/local/bin/curator_cli --host localhost --port 9200 $dryrun delete-indices --filter_list "[{\"filtertype\":\"age\",\"source\":\"name\",\"direction\":\"older\",\"unit\":\"days\",\"unit_count\":$rp,\"timestring\":\"%Y%m%d\"}]" || true
}

opensearch_shard_per_node_set()
{
    local shard=$1
    $CURL -XPUT http://localhost:9200/_cluster/settings -H 'Content-type: application/json' --data-binary $"{\"persistent\":{\"cluster.max_shards_per_node\":$shard}}"
}

opensearch_shard_delete_unassigned()
{
    $CURL -XGET http://localhost:9200/_cat/shards?h=index,shard,prirep,state,unassigned.reason| grep UNASSIGNED | cut -d' ' -f1  | xargs -i $CURL -XDELETE "http://localhost:9200/{}"
}

opensearch-dashboards_ops_reqid_search()
{
    local saved_objects="$($CURL -X GET "http://localhost:5601/opensearch-dashboards/api/saved_objects/_find?type=search")"
    echo $saved_objects | grep -q ops-reqid-search || $CURL -X POST "http://localhost:5601/opensearch-dashboards/api/saved_objects/_import?overwrite=true" -H "osd-xsrf:true" --form file=@/etc/opensearch-dashboards/export.ndjson
}

zookeeper_stats()
{
    ZK_HOST=$HOSTNAME
    ZK_PORT=2181

    echo stat | nc $ZK_HOST $ZK_PORT

    printf "\nbroker list\n"
    for i in `echo dump | nc $ZK_HOST $ZK_PORT | grep brokers`
    do
        DETAIL=`/opt/kafka/bin/zookeeper-shell.sh $ZK_HOST:$ZK_PORT <<< "get $i" 2>/dev/null | grep endpoints | jq -r .endpoints[]`
        echo "$i: $DETAIL"
    done
}

kafka_stats()
{
    /opt/kafka/bin/kafka-topics.sh --describe --bootstrap-server $HOSTNAME:9095 2>/dev/null
}

memcache_stats()
{
    echo stats | nc $(netstat -lntp | grep memcached | awk '{print $4}' | awk -F: '{print $1}') 11211
}

pacemaker_remote_add()
{
    local node=$1
    local timeout=${2:-120}

    # wait for remote pcsd started by remote node
    # check "hex_config -d" for startup order cluster -> pacemaker
    local i=0
    while [ $i -lt $timeout ]; do
        if echo "" | nc $node 2224 2>/dev/null; then
            /usr/sbin/pcs host auth $node -u hacluster -p Cube0s!
            /usr/sbin/pcs cluster node add-remote $node
            break
        else
            sleep 1
        fi
        i=$(expr $i + 1)
    done
    [ $i -lt $timeout ]
}

pacemaker_remote_remove()
{
    local node=$1
    /usr/sbin/pcs host auth $node -u hacluster -p Cube0s!
    /usr/sbin/pcs resource delete $node
    /usr/sbin/crm_node --force --remove $node
}

pacemaker_remote_cleanup()
{
    /usr/sbin/pcs resource cleanup $(hostname) 2>/dev/null
}

stale_api_clear()
{
    local service=$1
    local port=$2
    local binary_ss=${3:-$service}
    local binary_ns=${4:-$service}
    local qlen=${5:-10}
    local clear=0

    # check if receive queue full via ss
    ss -lntp | grep "LISTEN.*:$port .*$binary_ss" | while read -r recvq_ss
    do
        local q=$(echo $recvq_ss | awk '{print $2}')
        if [ -n "$q" -a $q -gt $qlen ]; then
            local pid=$(echo "$recvq_ss" | awk -F',' '{print $2}' | awk -F'=' '{print $2}')
            kill -9 $pid
            clear=1
        fi
    done

    # check if receive queue full via netstat
    netstat -lntp | grep "tcp.*:$port .*$binary_ns" | while read -r recvq_ns
    do
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

health_errcode_dump()
{
    printf "%22s %3s %s\n" "SERVICE" "ERR" "DESCRIPTION"
    for srvidx in $(echo ${!ERR_CODE[@]} | tr ' ' '\n' | sort | uniq); do
        srv=$(echo $srvidx | cut -d"," -f1)
        idx=$(echo $srvidx | cut -d"," -f2)
        printf "%22s %3s %s\n" "$srv" "$idx" "${ERR_CODE[$srvidx]}"
    done
}

health_errcode_lookup()
{
    local srv=$1
    local err=$2

    if [ $err -eq 0 ]; then
        echo -n ok
    else
        echo -n ${ERR_CODE[$srv,$err]:-$err undefined}
    fi
}

health_report()
{
    local tmp=${1%_report}
    local srv=${tmp#health_}
    local chk=${tmp}_check
    $chk
    local err=$?

    if [ $err -eq 0 ]; then
        local hth="healthy"
    else
        local hth="unhealthy"
    fi
    printf "+%12s+%12s+%24s+\n" | tr " " "-"
    printf "| %-10s | %10s | %22s |\n" "Status" "Error Code" "Error Description"
    printf "+%12s+%12s+%24s+\n" | tr " " "-"
    printf "| %-10s | %10s | %22s |\n" $hth $err "$(health_errcode_lookup $srv $err)"
    printf "+%12s+%12s+%24s+\n" | tr " " "-"
}

health_fail_log()
{
    local srv=$1
    local err=$2
    local stat=${*:3}

    [ -e $CUBE_DONE ] || return $err

    local maxerr=6
    if [ -f /etc/alert.level ]; then
        maxerr=$(cat /etc/alert.level | tr -d '\n')
    fi

    if [ -f /etc/alert.level.${srv} ]; then
        maxerr=$(cat /etc/alert.level.${srv} | tr -d '\n')
    fi

    if [ ${_OVERRIDE_MAX_ERR:-0} -gt 0 ]; then
        maxerr=$_OVERRIDE_MAX_ERR
    fi

    local count=0
    if [ -f /tmp/health_${srv}_error.count ]; then
        count=$(cat /tmp/health_${srv}_error.count | tr -d '\n')
    fi


    if ! (timeout $SRVTO cubectl node exec "[ -e /run/cube_commit_done ]" >/dev/null 2>&1); then
        return $err
    elif [ "$err" == "0" ]; then
        rm -f /tmp/health_${srv}_error.count
    else
        let "count = $count + 1"
        echo "==============================" >> /var/log/health_${srv}_error.log
        echo $(date) >> /var/log/health_${srv}_error.log
        echo "failed count: $count" >> /var/log/health_${srv}_error.log
        echo "error code: $err" >> /var/log/health_${srv}_error.log
        echo "error desc: $(health_errcode_lookup $srv $err)" >> /var/log/health_${srv}_error.log
        echo -e "$stat" $'\n' >> /var/log/health_${srv}_error.log
        echo $count > /tmp/health_${srv}_error.count
        if [ $count -ge $maxerr ]; then
            return $err
        fi
    fi

    return 0
}

# link

health_link_run()
{
    local type=$1
    local node_list=$(cubectl node list -j | jq .[].ip)
    local management=$(echo $node_list | jq -r .management)
    local provider=$(echo $node_list | jq -r .provider)
    local overlay=$(echo $node_list | jq -r .overlay)
    local storage=$(echo $node_list | jq -r .storage)
    local cluster=$(echo $node_list | jq -r '.["storage-cluster"]')
    readarray ip_array <<<"$(echo "$management $provider $overlay $storage $cluster" | tr ' ' '\n' | sort | uniq)"
    declare -p ip_array > /dev/null
    for ip_entry in "${ip_array[@]}"
    do
        local ip=$(echo $ip_entry | head -c -1)
        if [ ! -n "$ip" -o "$ip" == "null" ]; then
            continue
        fi
        case "$1" in
            report)
                echo -n "Ping $ip ... "
                ping -c 1 -w 1 $ip >/dev/null && echo "OK" || echo "FAILED"
                ;;
            check)
                ping -c 1 -w 1 $ip >/dev/null || return 1
                ;;
        esac
    done
}

health_mtu_check()
{
    local NETPTH=/sys/class/net
    local RET=0
    declare -A IFCS_MTUS

    for ifc in $(ls -1 $NETPTH | egrep -v '^veth|^tap|^lo|^eth|^bonding_masters'); do
        IFCS_MTUS[$ifc]=$(cat $NETPTH/$ifc/mtu | xargs)
    done
    for ifc in ${!IFCS_MTUS[@]}; do
        if ! cubectl node exec "if ip link show $ifc >/dev/null 2>&1; then ip link show $ifc | grep -q -i \"mtu ${IFCS_MTUS[$ifc]}\"; fi" >/dev/null 2>&1 ; then
            RET=1
            [ "$VERBOSE" != "1" ] || cubectl node exec -p "ip link show $ifc"
        fi
    done
    return $RET
}

health_link_report()
{
    health_link_run report
}

health_link_check()
{
    local err_code=0

    if ! health_link_run check >/dev/null; then
        err_code=1
    fi

    health_fail_log "link" $err_code "pings other nodes failed"
}

# dns

health_dns_report()
{
    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        local real=$(ssh root@$node time arp -a 2>&1 | grep real | awk '{print $2}')
        echo "$node DNS lookup took $real"
    done
}

health_dns_check()
{
    local err_code=0
    local err_msg=
    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if ! remote_run $node timeout 15 arp -a >/dev/null; then
            err_code=1
            err_msg="${err_msg}$node dns lookup timeout\n"
        fi
    done

    health_fail_log "dns" $err_code "$err_msg"
}

# clock

health_clock_report()
{
    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        local delta=$(clockdiff $node 2>/dev/null | awk '{print $2}')
        echo "time difference to $node is ${delta}ms"
    done
}

health_clock_check()
{
    local err_code=0
    local err_msg=

    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        local delta=$(clockdiff $node 2>/dev/null | awk '{print $2}')
        if [ -n "$delta" ]; then
            if [ ${delta#-} -gt 10000 ]; then
                err_code=1
                err_msg="${err_msg}time difference to $node is ${delta}ms\n"
            fi
        fi
    done

    health_fail_log "clock" $err_code "$err_msg"
}

health_clock_repair()
{
    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        remote_run $node /usr/sbin/hex_sdk ntp_makestep
    done
}

# node

health_node_report()
{
    printf "+%12s+%7s+%15s+%15s+\n" | tr " " "-"
    printf "| %-10s | %5s | %13s | %13s |\n" "" " CPU " "     Disk    " "    Memory   "
    printf "+%12s+%7s+%7s+%7s+%7s+%7s+\n" | tr " " "-"
    printf "| %-10s | %5s | %5s | %5s | %5s | %5s |\n" "Host" "Usage" "Usage" "Avail" "Usage" "Avail"
    printf "+%12s+%7s+%7s+%7s+%7s+%7s+\n" | tr " " "-"
    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if ping -c 1 -w 1 $node >/dev/null; then
            local cpu_usage=$(remote_run $node top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
            local disk_usage=$(remote_run $node df -h | awk '/ \/$/{print $5}')
            local disk_avail=$(remote_run $node df -h | awk '/ \/$/{print $4}')
            local mem_total_bytes=$(remote_run $node free | awk '/Mem/{print $2}')
            local mem_used_bytes=$(remote_run $node free | awk '/Mem/{print $3}')
            local mem_avail=$(remote_run $node free -h | awk '/Mem/{print $7}')
            printf "| %-10s | %5s | %5s | %5s | %5s | %5s |\n" $node "$cpu_usage" "$disk_usage" "$disk_avail" "$(( mem_used_bytes * 100 / mem_total_bytes ))%" "$mem_avail"
        fi
    done
    printf "+%12s+%7s+%7s+%7s+%7s+%7s+\n" | tr " " "-"
}

health_settings_check()
{
    local NUM_NODE=$(cubectl node list | wc -l)
    local RET=0
    for V in $(cat /etc/settings.txt | egrep -v "^#|^$" | cut -d"=" -f1 | sed 's/ $//' | tr "." "_"); do
        local CNT_UNIQ=$(timeout $SRVTO cubectl node exec -pn "source /usr/sbin/hex_tuning /etc/settings.txt ; echo \$T_${V}" | sort -u | wc -l)
        case $V in
            cubesys_role|cubesys_mgmt_cidr|cubesys_control_vip|cubesys_overlay|cubesys_provider|cubesys_storage|cubesys_management|net_if_*|ntp_server|cubesys_probeusb)
                if [ ${CNT_UNIQ:-0} -ne 1 ]; then
                    [ "$VERBOSE" != "1" ] || timeout $SRVTO cubectl node exec -r control -pn "source /usr/sbin/hex_tuning /etc/settings.txt ; echo \$HOSTNAME ${V}=\$T_${V}" | sort -u | xargs -i echo "{} (ignored)"
                    continue
                fi
                ;;
            *_alert_*)
                CNT_UNIQ=$(timeout $SRVTO cubectl node exec -r control -pn "source /usr/sbin/hex_tuning /etc/settings.txt ; echo \$T_${V}" | sort -u | wc -l)
                if [ ${CNT_UNIQ:-0} -ne 1 ]; then
                    RET=1
                    [ "$VERBOSE" != "1" ] || timeout $SRVTO cubectl node exec -r control -pn "source /usr/sbin/hex_tuning /etc/settings.txt ; echo \$HOSTNAME ${V}=\$T_${V}" | sort -u
                fi
                ;;
            net_hostname)
                if [ ${CNT_UNIQ:-0} -ne ${NUM_NODE:-3} ]; then
                    RET=1
                    [ "$VERBOSE" != "1" ] || timeout $SRVTO cubectl node exec -pn "source /usr/sbin/hex_tuning /etc/settings.txt ; echo \$HOSTNAME ${V}=\$T_${V}" | sort -u
                fi
                ;;
            *)
                if [ ${CNT_UNIQ:-0} -ne 1 ]; then
                    RET=1
                    [ "$VERBOSE" != "1" ] || timeout $SRVTO cubectl node exec -pn "source /usr/sbin/hex_tuning /etc/settings.txt ; echo \$HOSTNAME ${V}=\$T_${V}" | sort -u
                fi
                ;;
        esac
    done
    return $RET
}

# bootstrap

health_bootstrap_report()
{
    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if remote_run $node stat /run/cube_commit_done >/dev/null 2>&1; then
            echo "$node cube services... [ready]"
        else
            echo "$node cube services... [n/a]"
        fi
    done
    hex_sdk -v health_settings_check
}

health_bootstrap_check()
{
    local err_code=0
    local err_msg=

    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if ! remote_run $node stat /run/cube_commit_done >/dev/null 2>&1; then
            err_code=1
            err_msg="${err_msg}cube service of $node is not ready\n"
        fi
    done
    health_settings_check || err_code=2

    health_fail_log "bootstrap" $err_code "$err_msg"
}

# license

health_license_report()
{
    hex_cli -c license show
}

health_license_check()
{
    local err_code=0
    local err_msg=

    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        remote_run $node hex_config license_check >/dev/null 2>&1
        local r=$?
        if [ $r -ne 0 -a $r -ne 1 -a $r -ne 252 ]; then
            err_code=1
            err_msg="${err_msg}$node $(license_error_string $r)\n"
        fi
    done

    health_fail_log "license" $err_code "$err_msg"
}

# etcd

health_etcd_report()
{
    $ETCDCTL endpoint health --cluster 2>&1
}

health_etcd_check()
{
    local err_code=0
    local err_msg=

    readarray node_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if ! is_remote_running $node etcd; then
            err_code=1
            err_msg="${err_msg}etcd of $node is not running\n"
        fi
    done

    local total=$($ETCDCTL member list | wc -l)
    local online=$($ETCDCTL endpoint health --cluster 2>&1 | grep healthy | wc -l)
    if [ "$total" != "$online" ]; then
        err_code=2
        err_msg="${err_msg}$online/$total etcd are online\n"
    fi

    health_fail_log "etcd" $err_code "$err_msg"
}

health_etcd_repair()
{
    readarray node_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if ! is_remote_running $node etcd; then
            remote_systemd_restart $node etcd
        fi
    done
}

# hacluster

health_hacluster_report()
{
    pcs status
}

health_hacluster_check()
{
    local err_code=0
    local err_msg=

    readarray node_array <<<"$(/usr/sbin/cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if ! is_remote_running $node corosync; then
            err_code=1
            err_msg="${err_msg}corosync of $node is not running\n"
        elif ! is_remote_running $node pacemaker; then
            err_code=2
            err_msg="${err_msg}pacemaker of $node is not running\n"
        elif ! is_remote_running $node pcsd; then
            err_code=3
            err_msg="${err_msg}pcsd of $node is not running\n"
        fi
    done

    local status=$(/usr/sbin/hex_config status_pacemaker)

    local total=$(/usr/sbin/cubectl node list -r control -j | jq -r .[].hostname | wc -l)
    local online=$(echo "$status" | grep -i " online" | cut -d "[" -f2 | cut -d "]" -f1 | awk '{print NF}')
    if [ "$total" != "$online" ]; then
        err_code=4
        err_msg="${err_msg}$online/$total nodes are online\n"
    fi
    local offline=$(echo "$status" | grep -i " offline" | cut -d "[" -f3 | cut -d "]" -f1 | awk '{print NF}')
    if [ -n "$offline" ]; then
        err_code=5
        err_msg="${err_msg}$offline nodes are offline\n"
    fi

    local active_host=$(echo "$status" | awk '/IPaddr2/{print $5}')
    # is HA ?
    if [ -n "$active_host" ]; then
        # cinder-volume
        if ! echo "$status" | grep -q "cinder-volume.*Started"; then
            err_code=6
            err_msg="${err_msg}cinder-volume is not started\n"
        fi

        # ovndb_servers
        if echo "$status" | grep -q "ovndb_servers.*FAILED"; then
            err_code=7
            err_msg="${err_msg}ovndb_servers is not started\n"
        fi
    fi

    readarray node_array <<<"$(cubectl node list -r compute | awk -F',' '/compute/{print $1}' | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if [ -n "$node" ]; then
            if ! is_remote_running $node pcsd; then
                err_code=8
                err_msg="${err_msg}pcsd of $node is not running\n"
            elif ! is_remote_running $node pacemaker_remote; then
                err_code=9
                err_msg="${err_msg}pacemaker_remote of $node is not running\n"
            fi
        fi
    done

    local rtotal=$(cubectl node list -r compute | awk -F',' '/compute/{print $1}' | wc -l)
    local ronline=$(echo "$status" | grep -i " RemoteOnline" | cut -d "[" -f2 | cut -d "]" -f1 | awk '{print NF}')
    if [ -n "$ronline" -a "$rtotal" != "$ronline" ]; then
        err_code=10
        err_msg="${err_msg}$ronline/$rtotal remote nodes are online\n"
    fi
    local roffline=$(echo "$status" | grep -i " RemoteOFFLINE" | cut -d "[" -f3 | cut -d "]" -f1 | awk '{print NF}')
    if [ -n "$roffline" ]; then
        err_code=11
        err_msg="${err_msg}$roffline remote nodes are offline\n"
    fi

    health_fail_log "hacluster" $err_code "$err_msg"
}

health_hacluster_repair()
{
    health_hacluster_check
    if [ $? -eq 6 ]; then
        health_ceph_mds_repair
        health_cinder_repair
        pcs resource cleanup cinder-volume >/dev/null 2>&1
        pcs resource enable cinder-volume >/dev/null 2>&1
        pcs resource restart cinder-volume >/dev/null 2>&1
    fi

    pcs resource cleanup >/dev/null 2>&1

    readarray node_array <<<"$(/usr/sbin/cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        remote_run $node rm /var/lib/corosync/*
        remote_systemd_stop $node pcsd pacemaker corosync
    done
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        remote_systemd_start $node corosync pacemaker pcsd
        sleep 5
    done

    readarray node_array <<<"$(cubectl node list -r compute | awk -F',' '/compute/{print $1}' | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if [ -n "$node" ]; then
            remote_systemd_stop $node pcsd pacemaker_remote
        fi
    done
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if [ -n "$node" ]; then
            remote_systemd_start $node pacemaker_remote pcsd
            sleep 5
        fi
    done
}

# rabbitmq

health_rabbitmq_report()
{
    rabbitmqctl --formatter table cluster_status
    #printf "\n"
    #printf "Queue HA stats\n"
    #rabbitmqctl list_queues name pid synchronised_slave_pids | sed '1,2d' | awk 'FNR <= 6'

    printf "\n"
    printf "Non-empty message queues\n"
    printf "msg     sub     queue\n"
    rabbitmqctl list_queues messages consumers name | sed '1,3d' | grep -v "^0"

    printf "\n"
    printf "Zero consumer queues\n"
    printf "sub     queue\n"
    rabbitmqctl list_queues consumers name | sed '1,3d' | grep "^0"

    printf "\n"
    printf "Unresponsive queues\n"
    printf "queue\n"
    rabbitmqctl list_unresponsive_queues | sed '1,2d'
}

health_rabbitmq_check()
{
    local err_code=0
    local err_msg=

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl rabbitmq-server; then
            err_code=1
            err_msg="${err_msg}rabbitmq of $ctrl is not running\n"
        fi
    done

    local config=$(cubectl node list -r control | wc -l)
    local stats=$(/usr/sbin/hex_config status_rabbitmq)
    local online=$(echo $stats | jq -r .running_nodes[] | wc -l)
    local partition=$(echo $stats | jq -r .partitions[] | wc -l)

    if [ "$config" != "$online" ]; then
        err_code=2
        err_msg="${err_msg}$config/$online nodes are online\n"
    fi
    if [ "$partition" != "0" ]; then
        err_code=3
        err_msg="${err_msg}$partition partitions exist\n"
    fi

    rabbitmq_unhealthy_queue_clear

    health_fail_log "rabbitmq" $err_code "$err_msg"
}

health_rabbitmq_repair()
{
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        remote_systemd_stop $ctrl rabbitmq-server
        remote_run $ctrl rm -rf /var/lib/rabbitmq/mnesia/*
        remote_run $ctrl rm -f /etc/appliance/state/rabbitmq_cluster_done
    done

    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        remote_run $ctrl hex_config restart_rabbitmq
        sleep 8
    done
}

# mysql

health_mysql_report()
{
    $MYSQL -u root -e "show global status like 'wsrep_cluster_status'" | grep wsrep_cluster_status
    $MYSQL -u root -e "show global status like 'wsrep_cluster_size'" | grep wsrep_cluster_size
    $MYSQL -u root -e "show global status like 'wsrep_local_state_comment'" | grep wsrep_local_state_comment
}

health_mysql_check()
{
    local err_code=0
    local err_msg=

    local node_total=$(cubectl node list -r control | wc -l)
    local status=$($MYSQL -u root -e "show global status like 'wsrep_cluster_status'" | grep wsrep_cluster_status | awk '{print $2}')
    local online=$($MYSQL -u root -e "show global status like 'wsrep_cluster_size'" | grep wsrep_cluster_size | awk '{print $2}')
    local state=$($MYSQL -u root -e "show global status like 'wsrep_local_state_comment'" | grep wsrep_local_state_comment | awk '{print $2}')
    if [ $node_total -eq 1 ]; then
        if [ "$status" != "Disconnected" ]; then
            err_code=1
            err_msg="${err_msg}mysql is disconnected\n"
        fi
    else
        if [ "$node_total" != "$online" ]; then
            err_code=2
            err_msg="${err_msg}$online/$node_total nodes are online\n"
        elif [ "$state" != "Synced" ]; then
            err_code=3
            err_msg="${err_msg}mysql cluster doesn't sync-ed\n"
        fi
    fi

    health_fail_log "mysql" $err_code "$err_msg"
}

health_mysql_repair()
{
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        # mariadbd might hang and unable to stop in some circumstances
        local pid=$(remote_run $ctrl pidof mariadbd)
        if [ -n "$pid" ]; then
            remote_run $ctrl kill -9 $pid
        fi
        remote_systemd_stop $ctrl mariadb
    done
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        remote_run $ctrl touch /etc/appliance/state/mysql_new_cluster
        remote_run $ctrl hex_config restart_mysql
    done
}

# vip

health_vip_report()
{
    local active_host=$(/usr/sbin/hex_config status_pacemaker | awk '/IPaddr2/{print $5}')
    if [ -n "$active_host" ]; then
        local ipaddr=$(remote_run $active_host ip addr list | awk '/ secondary /{print $2}')
        echo "$ipaddr@$active_host"
    else
        echo "non-HA"
    fi
}

health_vip_check()
{
    local err_code=0
    local err_msg=

    local active_host=$(/usr/sbin/hex_config status_pacemaker | awk '/IPaddr2/{print $5}')
    if [ -n "$active_host" ]; then
        readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
        declare -p ctrl_array > /dev/null
        for ctrl_entry in "${ctrl_array[@]}"
        do
            local ctrl=$(echo $ctrl_entry | head -c -1)
            local ipaddr=$(remote_run $ctrl ip addr list | awk '/ secondary /{print $2}')
            if [ "$ctrl" == "$active_host" ]; then
                if [ -z "$ipaddr" ]; then
                    err_code=1
                    err_msg="${err_msg}$ipaddr should be active on $ctrl\n"
                fi
            else
                if [ -n "$ipaddr" ]; then
                    err_code=2
                    err_msg="${err_msg}$ipaddr shouldn't be active on $ctrl\n"
                fi
            fi
        done
    fi

    health_fail_log "vip" $err_code "$err_msg"
}

health_vip_repair()
{
    local active_host=$(/usr/sbin/hex_config status_pacemaker | awk '/IPaddr2/{print $5}')
    if [ -n "$active_host" ]; then
        readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
        declare -p ctrl_array > /dev/null
        for ctrl_entry in "${ctrl_array[@]}"
        do
            local ctrl=$(echo $ctrl_entry | head -c -1)
            local ipaddr=$(remote_run $ctrl ip addr list | awk '/ secondary /{print $2}')
            local ifname=$(remote_run $ctrl ip addr list | awk '/ secondary /{print $NF}')
            if [ "$ctrl" == "$active_host" ]; then
                if [ -z "$ipaddr" ]; then
                    pcs resource disable vip
                    pcs resource enable vip
                fi
            else
                if [ -n "$ipaddr" ]; then
                    ip addr del $ipaddr dev $ifname
                fi
            fi
        done
    fi
}

# haproxy_ha

health_haproxy_ha_report()
{
    local active_host=$(/usr/sbin/hex_config status_pacemaker | awk '/haproxy-ha/{print $5}')
    if [ -n "$active_host" ]; then
        echo "($active_host)"
        remote_run $active_host hex_sdk haproxy_stats /run/haproxy/admin.sock
    else
        echo "non-HA"
    fi
}

health_haproxy_ha_check()
{
    local err_code=0
    local err_msg=

    local active_host=$(/usr/sbin/hex_config status_pacemaker | awk '/haproxy-ha/{print $5}')
    if [ -n "$active_host" ]; then
        readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
        declare -p ctrl_array > /dev/null
        for ctrl_entry in "${ctrl_array[@]}"
        do
            local ctrl=$(echo $ctrl_entry | head -c -1)
            if [ "$ctrl" == "$active_host" ]; then
                if ! is_remote_running $ctrl haproxy-ha; then
                    err_code=1
                    err_msg="${err_msg}haproxy-ha of $ctrl is not running\n"
                fi
            fi
        done
    fi

    health_fail_log "haproxy-ha" $err_code "$err_msg"
}

health_haproxy_ha_repair()
{
    local active_host=$(/usr/sbin/hex_config status_pacemaker | awk '/haproxy-ha/{print $5}')
    if [ -n "$active_host" ]; then
        readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
        declare -p ctrl_array > /dev/null
        for ctrl_entry in "${ctrl_array[@]}"
        do
            local ctrl=$(echo $ctrl_entry | head -c -1)
            if [ "$ctrl" == "$active_host" ]; then
                if ! is_remote_running $ctrl haproxy-ha; then
                    remote_systemd_restart $ctrl haproxy-ha
                fi
            fi
        done
    fi
}

# haproxy

health_haproxy_report()
{
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        echo "($ctrl)"
        remote_run $ctrl hex_sdk haproxy_stats /run/haproxy/admin-local.sock
    done
}

health_haproxy_check()
{
    local err_code=0
    local err_msg=

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl haproxy >/dev/null 2>&1; then
            err_code=1
            err_msg="${err_msg}haproxy of $ctrl is not running\n"
        fi
    done

    health_fail_log "haproxy" $err_code "$err_msg"
}

health_haproxy_repair()
{
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl haproxy >/dev/null 2>&1; then
            remote_systemd_restart $ctrl haproxy
        fi
    done
}

# httpd

health_httpd_report()
{
    health_report ${FUNCNAME[0]}
}

health_httpd_check()
{
    local err_code=0
    local err_msg="monasca(8070) keystone(5000) placement(8778) mellon(5443) barbican(9311)\n"

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl httpd; then
            err_code=1
            err_msg="${err_msg}httpd of $ctrl is not running\n"
        fi
        local i=2
        # monasca(8070)
        # keystone(5000) placement(8778) mellon(5443)
        for port in 8070 5000 8778 5443
        do
            $CURL -sf http://$ctrl:$port >/dev/null
            # 0: ok, 22: http error (page not found)
            if [ "$?" -ne "0" -a "$?" -ne "22" ] ; then
                err_code=$i
                err_msg="${err_msg}http port $port of $ctrl doesn't respond\n"
            fi
            let "i = $i + 1"
        done

        if ! is_edge_node; then
            # barbican(9311)
            $CURL -sf http://$ctrl:9311 >/dev/null
            # 0: ok, 22: http error (page not found)
            if [ "$?" -ne "0" -a "$?" -ne "22" ] ; then
                err_code=$i
                err_msg="${err_msg}http port 9311 of $ctrl doesn't respond\n"
            fi
        fi
    done

    health_fail_log "httpd" $err_code "$err_msg"
}

health_httpd_repair()
{
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl httpd; then
            remote_systemd_restart $ctrl httpd
        fi
        for port in 9090 8070 8776 5000 8778
        do
            $CURL -sf http://$ctrl:$port >/dev/null
            # 0: ok, 22: http error (page not found)
            if [ "$?" -ne "0" -a "$?" -ne "22" ] ; then
                remote_systemd_restart $ctrl httpd
            fi
        done

        if ! is_edge_node; then
            # barbican(9311)
            $CURL -sf http://$ctrl:9311 >/dev/null
            # 0: ok, 22: http error (page not found)
            if [ "$?" -ne "0" -a "$?" -ne "22" ] ; then
                remote_systemd_restart $ctrl httpd
            fi
        fi
    done
}

# skyline

health_skyline_report()
{
    health_report ${FUNCNAME[0]}
}

health_skyline_check()
{
    local err_code=0
    local err_msg=

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl nginx >/dev/null 2>&1; then
            err_code=1
            err_msg="${err_msg}nginx of $ctrl is not running\n"
        fi
        if ! is_remote_running $ctrl skyline-apiserver >/dev/null 2>&1; then
            err_code=2
            err_msg="${err_msg}skyline-apiserver of $ctrl is not running\n"
        fi
    done

    health_fail_log "skyline" $err_code "$err_msg"
}

health_skyline_repair()
{
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl nginx >/dev/null 2>&1; then
            remote_systemd_restart $ctrl nginx
        fi
        if ! is_remote_running $ctrl skyline-apiserver >/dev/null 2>&1; then
            remote_systemd_restart $ctrl skyline-apiserver
        fi
    done
}

# lmi

health_lmi_report()
{
    health_report ${FUNCNAME[0]}
}

health_lmi_check()
{
    local err_code=0
    local err_msg=

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl lmi >/dev/null 2>&1; then
            err_code=1
            err_msg="${err_msg}lmi of $ctrl is not running\n"
        fi
        $CURL -sf http://$ctrl:8081 >/dev/null
        if [ $? -eq 7 ] ; then
            err_code=2
            err_msg="${err_msg}lmi doesn't respond\n"
        fi
    done

    health_fail_log "lmi" $err_code "$err_msg"
}

health_lmi_repair()
{
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl lmi >/dev/null 2>&1; then
            remote_systemd_restart $ctrl lmi
        fi
        $CURL -sf http://$ctrl:8081 >/dev/null
        if [ $? -eq 7 ] ; then
            remote_systemd_restart $ctrl lmi
        fi
    done
}

# memcache

health_memcache_report()
{
    health_report ${FUNCNAME[0]}
}

health_memcache_check()
{
    local err_code=0
    local err_msg=

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl memcached; then
            err_code=1
            err_msg="${err_msg}memcached of $ctrl is not running\n"
        fi
    done

    health_fail_log "memcached" $err_code "$err_msg"
}

health_memcache_repair()
{
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        remote_systemd_restart $ctrl memcached
    done
}

# keycloak

health_keycloak_report()
{
    cubectl config status keycloak
}

health_keycloak_check()
{
    local err_code=0

    if ! cubectl config check keycloak 2>/dev/null ; then
        err_code=1
    fi

    health_fail_log "keycloak" $err_code "$(health_keycloak_report)"
}

health_keycloak_repair()
{
    cubectl config repair keycloak
}

# ceph

health_ceph_report()
{
    $CEPH -s
}

health_ceph_check()
{
    local srv="ceph"
    local stats=$($CEPH status -f json)
    local service_stats=$(echo $stats | jq -r .health.status)
    local err_code=0
    if [ "$service_stats" == "HEALTH_WARN" ]; then
        err_code=1
    elif [ "$service_stats" == "HEALTH_ERR" ]; then
        err_code=2
    fi

    health_fail_log "ceph" $err_code "$($CEPH status)"
}

# ceph_mon

health_ceph_mon_report()
{
    health_report ${FUNCNAME[0]}
}

health_ceph_mon_check()
{
    local err_code=0
    local stats=$($CEPH status -f json)
    local total=$(echo $stats | jq -r .monmap.num_mons)
    local online=$(echo $stats | jq -r .quorum_names[] | wc -l)

    ! (echo $stats | jq -r .health.checks.MON_MSGR2_NOT_ENABLED.summary.message | grep -q "have not enabled msgr2") || err_code=1
    if [ "$total" != "$online" ]; then
        err_code=2
    fi
    ! (echo $stats | jq -r .health | grep -q "mon.* has slow ops") || err_code=3

    health_fail_log "ceph_mon" $err_code "$(echo $stats | jq -r .health)"
    local r=$?
    health_ceph_mon_auto_repair $err_code $r "$stats"
    return $r
}

health_ceph_mon_auto_repair()
{
    local err_code=$1
    local true_fail=$2
    local stats=${*:3}

    if [ "$err_code" == "1" -a "$true_fail" == "0" ]; then
        ceph_mon_msgr2_enable
    elif [ "$err_code" == "2" -a "$true_fail" == "0" ]; then
        for mon_entry in "${mon_array[@]}"; do
            local mon=$(echo $mon_entry | head -c -1)
            if ! echo $online | grep -q $mon; then
                remote_systemd_restart $mon ceph-mon@$mon
            fi
        done
    fi
}

health_ceph_mon_repair()
{
    local stats=$($CEPH status -f json)
    local online=$(echo $stats | jq -r .quorum_names[])

    readarray mon_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p mon_array > /dev/null
    Quiet cubectl node exec -r control "systemctl reset-failed ; systemctl restart ceph-mgr@\$HOSTNAME"
    for mon_entry in "${mon_array[@]}"; do
        local mon=$(echo $mon_entry | head -c -1)
        if ! echo $online | grep -q $mon; then
            remote_systemd_restart $mon ceph-mon@$mon
        fi
    done
}

# ceph_mgr

health_ceph_mgr_report()
{
    health_report ${FUNCNAME[0]}
}

health_ceph_mgr_check()
{
    local active=$($CEPH mgr stat -f json | jq -r .active_name)
    local cnt=0
    local err_code=0
    local stats=$($CEPH status -f json)
    local total=$(cubectl node list -r control -j | jq -r .[].hostname | wc -l)
    local standbys=$(echo $stats | jq -r .mgrmap.num_standbys)
    let "online = $standbys + 1"
    if [ "$total" != "$online" ]; then
        err_code=1
    fi

    ! (echo $stats | jq -r .health | grep -q "Failed to list/create InfluxDB database") || err_code=2
    ! (echo $stats | jq -r .health | grep -q "influx.* has failed:") || err_code=3
    ! (echo $stats | jq -r .health | grep -q "Module 'devicehealth' has failed: table Device already exists") || err_code=4
    if grep -q "ha = false" /etc/settings.txt; then
        timeout 5 curl -I -k https://${active}:7443/ceph/ 2>/dev/null | grep -q "200 OK" || err_code=5
    else
        timeout 5 curl -I -k https://${active}:7442/ceph/ 2>/dev/null | grep -q "200 OK" || err_code=5
    fi
    local MEM=$(hex_sdk remote_run $active "ps aux | tr -s ' ' | grep \"^ceph \$(pgrep ceph-mgr)\" | cut -d' ' -f4 | cut -d '.' -f1")
    [ ${MEM:-1} -lt 10 ] || err_code=6

    health_fail_log "ceph_mgr" $err_code "$(echo $stats | jq -r .mgrmap)"
    local r=$?
    health_ceph_mgr_auto_repair $err_code $r "$stats"
    return $r
}

health_ceph_mgr_auto_repair()
{
    local err_code=$1
    local true_fail=$2
    local stats=${*:3}

    if [ "$err_code" == "1" -a "$true_fail" == "0" ]; then
        Quiet cubectl node exec -r control "systemctl reset-failed ; systemctl restart ceph-mgr@\$HOSTNAME"
    elif [ "$err_code" == "2" -a "$true_fail" == "0" ]; then
        if [ "$influx_hn" = "non-HA" ]; then
            influx_hn=$(hostname)
        fi
        $CEPH config set mgr mgr/influx/hostname $influx_hn
        $CEPH config set mgr mgr/influx/interval 60
    elif [ "$err_code" == "3" -a "$true_fail" == "0" ]; then
        $CEPH mgr module disable influx
        $CEPH mgr module enable influx
    elif [ "$err_code" == "4" -a "$true_fail" == "0" ]; then
        cubectl node exec -r control -p "systemctl stop ceph-mgr@\$HOSTNAME && sleep 5"
        $CEPH osd pool rename .mgr .mgr-old
        cubectl node exec -r control -p "systemctl start ceph-mgr@\$HOSTNAME"
        $CEPH osd pool delete .mgr-old .mgr-old --yes-i-really-really-mean-it
    elif [ "$err_code" == "5" -a "$true_fail" == "0" ]; then
        $CEPH mgr module disable dashboard
        $CEPH mgr module enable dashboard
    elif [ "$err_code" == "6" -a "$true_fail" == "0" ]; then
        $CEPH mgr fail
    fi

    return 0
}

health_ceph_mgr_repair()
{
    readarray ctrl_array <<<"$(/usr/sbin/cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null

    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        remote_run $ctrl /usr/sbin/hex_config restart_ceph_mgr
    done
}

# ceph_mds

health_ceph_mds_report()
{
    health_report ${FUNCNAME[0]}
}

health_ceph_mds_check()
{
    local stats=$($CEPH status -f json | jq -r .fsmap)
    local total=$(cubectl node list -r control -j | jq -r .[].hostname | wc -l)
    local active=$(echo $stats | jq -r .up)
    local standbys=$(echo $stats | jq '.["up:standby"]')
    local hotstandbys=$(echo $stats | jq | grep 'up:standby-replay' | wc -l)
    if [ -z "$standbys" ]; then
        standbys=0
    fi

    local err_code=0
    let "online = $active + $standbys + $hotstandbys"
    if [ "$total" != "$online" ]; then
        err_code=1
    fi

    local num_ctrlnode=$(timeout $SRVSTO cubectl node exec -r control -pn hostname | wc -l)
    local num_nodes=$(timeout $SRVSTO cubectl node exec -pn hostname | wc -l)
    local cnt_mntpoint=$(cubectl node exec -pn -- "mountpoint -- $CEPHFS_STORE_DIR"  | grep "is a mountpoint" | wc -l)
    [ $cnt_mntpoint -eq $num_nodes ] || err_code=2
    [ $cnt_mntpoint -eq $num_nodes ] || Quiet cubectl node exec -p "/usr/sbin/hex_sdk ceph_mount_cephfs"

    local NFS_DIR=$(mktemp -u /tmp/nfs-XXXX)
    local VIP=$(hex_sdk health_vip_report | cut -d"/" -f1)
    [ "x$VIP" != "xnon-HA" ] || VIP=$(cubectl node list | cut -d"," -f2)
    mkdir -p $NFS_DIR
    timeout $SRVSTO mount ${VIP}:/nfs $NFS_DIR 2>/dev/null || err_code=3
    touch $NFS_DIR/.alive
    Quiet ls -lta $NFS_DIR/.alive|| err_code=4
    rm -f $NFS_DIR/.alive
    timeout $SRVSTO umount -l $NFS_DIR/ 2>/dev/null
    rmdir $NFS_DIR
    local cnt_ganesha=$(cubectl node exec -pn -- "systemctl show -p SubState nfs-ganesha" | grep running| wc -l)
    [ $cnt_ganesha -eq $num_ctrlnode ] || err_code=5

    health_fail_log "ceph_mds" $err_code "$(echo $stats)"
    local r=$?
    health_ceph_mds_auto_repair $err_code $r "$stats"
    return $r
}

health_ceph_mds_auto_repair()
{
    local err_code=$1
    local true_fail=$2
    local stats=${*:3}

    if [ "$err_code" == "1" -a "$true_fail" == "0" ]; then
        Quiet cubectl node exec -r control "systemctl reset-failed ; systemctl restart ceph-mds@\$HOSTNAME"
    elif [ "$err_code" == "2" -a "$true_fail" == "0" ]; then
        Quiet cubectl node exec -pn -- hex_sdk ceph_mount_cephfs
    elif [ "$err_code" == "3" -a "$true_fail" == "0" ]; then
        Quiet cubectl node exec -r control -p "systemctl restart nfs-ganesha"
    elif [ "$err_code" == "4" -a "$true_fail" == "0" ]; then
        Quiet cubectl node exec -r control -p "systemctl restart nfs-ganesha"
    elif [ "$err_code" == "5" -a "$true_fail" == "0" ]; then
        Quiet cubectl node exec -r control -p "systemctl restart nfs-ganesha"
    fi

    return 0
}

health_ceph_mds_repair()
{
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        remote_run $ctrl "systemctl reset-failed"
        remote_run $ctrl /usr/sbin/hex_config restart_ceph_mds
    done

    for i in {1..10}; do
        sleep 1
        $CEPH fs status | grep -q active && break
    done

    Quiet cubectl node exec -p "/usr/sbin/hex_sdk ceph_mount_cephfs"
    Quiet cubectl node exec -r control -p "systemctl restart nfs-ganesha"
}

# ceph_disk

health_ceph_disk_check()
{
    local MKF=/etc/appliance/state/${FUNCNAME[0]%_check}_enabled
    if [ -e $MKF  ]; then
        if cubectl node exec -pn "hex_sdk ceph_osd_query_health" | sort -t. -n -k2 | egrep -q "warning|fail" ; then
            return 1
        fi
    fi
}

# ceph_osd

health_ceph_osd_report()
{
    health_report ${FUNCNAME[0]}
    cubectl node exec -pn "hex_sdk ceph_osd_query_health" | sort -t. -n -k2 | egrep "warning|fail"
}

health_ceph_osd_check()
{
    local err_code=0
    local stats=$($CEPH status -f json)
    local total=$(echo $stats | jq -r .osdmap.num_osds)
    local uposd=$(echo $stats | jq -r .osdmap.num_up_osds)
    local inosd=$(echo $stats | jq -r .osdmap.num_in_osds)
    if [ "$total" != "$uposd" ]; then
        err_code=1
    elif [ "$total" != "$inosd" ]; then
        err_code=2
    fi
    health_ceph_disk_check || err_code=3

    health_fail_log "ceph_osd" $err_code "$(echo $stats | jq -r .osdmap)"
}

health_ceph_osd_repair()
{
    if [ $($CEPH osd tree down | grep host | awk '{print $4}' | sort -u | wc -l) -gt 0 ]; then
        readarray osd_array <<<"$($CEPH osd tree | awk '/ down /{print $1}' | sort)"
        declare -p osd_array > /dev/null
        for osd_entry in "${osd_array[@]}" ; do
            local osd=$(echo $osd_entry | head -c -1)
            local host=$(ceph_get_host_by_id $osd)
            remote_run $host "timeout $SRVLTO hex_sdk ceph_osd_restart $osd"
        done
    fi
}

# ceph_rgw

health_ceph_rgw_report()
{
    health_report ${FUNCNAME[0]}
}

health_ceph_rgw_check()
{
    local err_code=0
    local total=$(cubectl node list -r control -j | jq -r .[].hostname | wc -l)
    local online=$($CEPH -s | awk '/rgw:/{print $2}')
    if [ "$total" != "$online" ]; then
        err_code=1
    fi

    health_fail_log "ceph_rgw" $err_code "$online/$total rgw are online"
}

health_ceph_rgw_repair()
{
    local online=$($CEPH -s -f json | jq -r .servicemap.services.rgw.daemons[] | jq -r .metadata.hostname)
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! echo "$online" | grep -q $ctrl ; then
            remote_run $ctrl /usr/sbin/hex_config restart_ceph_rgw
        fi
    done
}

# rbd_target

health_rbd_target_report()
{
    health_report ${FUNCNAME[0]}
}

health_rbd_target_check()
{
    # FIXME: ceph-iscsi for el9/python3.9 is not yet available (Latest is ceph-iscsi 3.6-2 el8 which depends on python3.6)
    if [[ $(python3 --version) =~ 3.9 ]]; then return 0 ; fi

    local err_code=0
    local err_msg=

    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        local osd_count=$($CEPH osd status 2>/dev/nul | grep " $node " | wc -l)
        if [ "$osd_count" != "0" ]; then
            if ! is_remote_running $node rbd-target-api; then
                err_code=1
                err_msg="${err_msg}rbd-target-api of $node is not running.\n"
            elif ! is_remote_running $node rbd-target-gw; then
                err_code=2
                err_msg="${err_msg}rbd-target-gw of $node is not running.\n"
            fi
        fi
    done

    health_fail_log "rbd_target" $err_code "$err_msg"
}

health_rbd_target_repair()
{
    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        local osd_count=$($CEPH osd status 2>/dev/nul | grep " $node " | wc -l)
        if [ "$osd_count" != "0" ]; then
            if ! is_remote_running $node rbd-target-api; then
                remote_systemd_restart $node rbd-target-api
            elif ! is_remote_running $node rbd-target-gw; then
                remote_systemd_restart $node rbd-target-gw
            fi
        fi
    done
}

# nova

health_nova_report()
{
    timeout $SRVTO openstack compute service list
}

health_nova_check()
{
    stale_api_check_repair openstack-nova-api 8774 nova-api python3

    local http_stats=$(influx -host $(shared_id) -database monasca -format json -execute "select last(value) from http_status where service = 'compute'" | jq .results[0].series[0].values[0][1])
    if [ "$http_stats" != "0" ]; then
        health_fail_log "nova" 1 "endpoint unreachable"
        return $?
    fi

    local service_stats=$(timeout $SRVTO openstack compute service list -f value -c Binary -c Host -c Status -c State 2>/dev/null)
    if [ -z "$service_stats" ]; then
        health_fail_log "nova" 2 "service api timeout"
        return $?
    fi

    local err_code=0
    local scheduler_up=$(echo "$service_stats" | grep scheduler | grep -i enabled | grep -i up | wc -l )
    local scheduler_down=$(echo "$service_stats" | grep scheduler | grep -i enabled | grep -i down | wc -l )
    local conductor_up=$(echo "$service_stats" | grep conductor | grep -i enabled | grep -i up | wc -l )
    local conductor_down=$(echo "$service_stats" | grep conductor | grep -i enabled | grep -i down | wc -l )
    local compute_up=$(echo "$service_stats" | grep compute | grep -v ironic | grep -i enabled | grep -i up | wc -l )
    local compute_down=$(echo "$service_stats" | grep compute | grep -v ironic | grep -i enabled | grep -i down | wc -l )
    if [ "$scheduler_up" == "0" -o "$scheduler_down" != "0" ]; then
        err_code=3
    elif [ "$conductor_up" == "0" -o "$conductor_down" != "0" ]; then
        err_code=4
    elif [ "$compute_up" == "0" -o "$compute_down" != "0" ]; then
        err_code=5
    fi

    health_fail_log "nova" $err_code "$service_stats"
    local r=$?
    health_nova_auto_repair $err_code $r "$service_stats"
    return $r
}

health_nova_auto_repair()
{
    local err_code=$1
    local true_fail=$2
    local stats=${*:3}

    if [ "$err_code" != "0" -a "$true_fail" == "0" ]; then
        readarray entry_array <<<"$(echo "$stats" | awk '/enabled.*down/{print $1" "$2}' | sort)"
        declare -p entry_array > /dev/null
        for entry in "${entry_array[@]}"
        do
            local srv=$(echo $entry | awk '{print $1}')
            local host=$(echo $entry | awk '{print $2}')
            if [ -n "$host" ]; then
                remote_systemd_restart $host openstack-$srv
            fi
        done
    fi

    return 0
}

health_nova_repair()
{
    cubectl node exec -p /usr/sbin/hex_config restart_nova >/dev/null 2>&1
    return 0
}

# ironic

health_ironic_report()
{
    health_report ${FUNCNAME[0]}

    source hex_tuning /etc/settings.txt ironic.enabled
    if [ "$T_ironic_enabled" == "true" ]; then
        timeout $SRVTO openstack baremetal driver list
    fi
}

health_ironic_check()
{
    source hex_tuning /etc/settings.txt ironic.enabled
    if [ "$T_ironic_enabled" != "true" ]; then
        return 0
    fi

    stale_api_check_repair openstack-ironic-api 6385 ironic-api python3
    stale_api_check_repair openstack-ironic-inspector 5050 ironic-inspecto python3

    local service_stats=$(timeout $SRVTO openstack compute service list -f value -c Binary -c Host -c Status -c State 2>/dev/null)
    if [ -z "$service_stats" ]; then
        health_fail_log "ironic" 2 "service api timeout"
        return $?
    fi

    local err_code=0

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl openstack-ironic-api; then
            err_code=3
        elif ! is_remote_running $ctrl openstack-ironic-conductor; then
            err_code=4
        elif ! is_remote_running $ctrl openstack-ironic-inspector; then
            err_code=5
        fi
    done

    local ironic_up=$(echo "$service_stats" | grep compute | grep ironic | grep -i enabled | grep -i up | wc -l )
    local ironic_down=$(echo "$service_stats" | grep compute | grep ironic | grep -i enabled | grep -i down | wc -l )
    if [ "$ironic_up" == "0" -o "$ironic_down" != "0" ]; then
        err_code=6
    fi

    health_fail_log "ironic" $err_code "$service_stats"
    local r=$?
    health_ironic_auto_repair $err_code $r "$service_stats"
    return $r
}

health_ironic_auto_repair()
{
    local err_code=$1
    local true_fail=$2
    local stats=${*:3}

    if [ "$err_code" != "0" -a "$true_fail" == "0" ]; then
        readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
        declare -p ctrl_array > /dev/null
        for ctrl_entry in "${ctrl_array[@]}"
        do
            local ctrl=$(echo $ctrl_entry | head -c -1)
            if ! is_remote_running $ctrl openstack-ironic-api; then
                remote_systemd_restart $ctrl openstack-ironic-api
            elif ! is_remote_running $ctrl openstack-ironic-conductor; then
                remote_systemd_restart $ctrl openstack-ironic-conductor
            elif ! is_remote_running $ctrl openstack-ironic-inspector; then
                remote_systemd_restart $ctrl openstack-ironic-inspector
            fi
        done

        readarray entry_array <<<"$(echo "$stats" | awk '/ironic.*enabled.*down/{print $1" "$2}' | sort)"
        declare -p entry_array > /dev/null
        for entry in "${entry_array[@]}"
        do
            local srv=$(echo $entry | awk '{print $1}')
            local host=$(echo $entry | awk '{print $2}' | awk -F'-' '{print $1}' | tr -d '\n')
            if [ -n "$host" ]; then
                remote_systemd_restart $host openstack-$srv
            fi
        done
    fi

    return 0
}

health_ironic_repair()
{
    cubectl node exec -p /usr/sbin/hex_config restart_ironic >/dev/null 2>&1
    return 0
}

# cyborg

health_cyborg_report()
{
    echo "Accelerator:"
    timeout $SRVTO openstack accelerator device list 2>/dev/null

    echo "GPU Resource Provider:"
    timeout $SRVTO openstack resource provider list -c uuid -c name --resource PGPU=1 2>/dev/null

    echo "Accelerator Request:"
    timeout $SRVTO openstack accelerator arq list 2>/dev/null

    echo "Accelerator Device Profile:"
    timeout $SRVTO openstack accelerator device profile list 2>/dev/null
}

health_cyborg_check()
{
    local err_code=0
    local err_msg=
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl cyborg-api; then
            err_msg="${err_msg}cyborg-api of $ctrl is not running\n"
            err_code=3
        elif ! is_remote_running $ctrl cyborg-conductor; then
            err_msg="${err_msg}cyborg-conductor of $ctrl is not running\n"
            err_code=4
        fi
    done

    readarray cmp_array <<<"$(cubectl node list -r compute -j | jq -r .[].hostname | sort)"
    declare -p cmp_array > /dev/null
    for cmp_entry in "${cmp_array[@]}"
    do
        local cmp=$(echo $cmp_entry | head -c -1)
        if ! is_remote_running $cmp cyborg-agent; then
            err_msg="${err_msg}cyborg-agent of $cmp is not running\n"
            err_code=5
        fi
    done

    health_fail_log "cyborg" $err_code "$err_msg"
    local r=$?
    health_cyborg_auto_repair $err_code $r
    return $r
}

health_cyborg_auto_repair()
{
    local err_code=$1
    local true_fail=$2

    if [ "$err_code" != "0" -a "$true_fail" == "0" ]; then
        readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
        declare -p ctrl_array > /dev/null
        for ctrl_entry in "${ctrl_array[@]}"
        do
            local ctrl=$(echo $ctrl_entry | head -c -1)
            if ! is_remote_running $ctrl cyborg-api; then
                remote_systemd_restart $ctrl cyborg-api
            elif ! is_remote_running $ctrl cyborg-conductor; then
                remote_systemd_restart $ctrl cyborg-conductor
            fi
        done

        readarray cmp_array <<<"$(cubectl node list -r compute -j | jq -r .[].hostname | sort)"
        declare -p cmp_array > /dev/null
        for cmp_entry in "${cmp_array[@]}"
        do
            local cmp=$(echo $cmp_entry | head -c -1)
            if ! is_remote_running $cmp cyborg-agent; then
                remote_systemd_restart $cmp cyborg-agent
            fi
        done
    fi

    return 0
}

health_cyborg_repair()
{
    cubectl node exec -p /usr/sbin/hex_config restart_cyborg >/dev/null 2>&1
    return 0
}

# neutron

health_neutron_report()
{
    timeout $SRVTO openstack network agent list
}

health_neutron_check()
{
    stale_api_check_repair neutron-server 9696 neutron-server server

    local service_stats=$(timeout $SRVTO openstack network agent list -f value -c Binary -c Alive -c Host 2>/dev/null)
    if [ -z "$service_stats" ]; then
        health_fail_log "neutron" 2 "service api timeout"
        return $?
    fi

    local err_code=0
    local metadata_up=$(echo "$service_stats" | grep neutron-ovn-metadata-agent | grep -i True | wc -l )
    local metadata_down=$(echo "$service_stats" | grep neutron-ovn-metadata-agent | grep -i False | wc -l )
    local vpn_up=$(echo "$service_stats" | grep neutron-ovn-vpn-agent | grep -i True | wc -l )
    local vpn_down=$(echo "$service_stats" | grep neutron-ovn-vpn-agent | grep -i False | wc -l )
    local control_up=$(echo "$service_stats" | grep ovn-controller | grep -i True | wc -l )
    local control_down=$(echo "$service_stats" | grep ovn-controller | grep -i False | wc -l )
    if [ "$metadata_up" == "0" -o "$metadata_down" != "0" ]; then
        err_code=3
    elif [ "$vpn_up" == "0" -o "$vpn_down" != "0" ]; then
        err_code=4
    elif [ "$control_up" == "0" -o "$control_down" != "0" ]; then
        err_code=5
    fi

    if [ $err_code -eq 0 ]; then
        # create a dummy port for e2e test
        net_id=$(timeout $SRVTO openstack subnet list | awk '/ lb-mgmt-subnet / {print $6}')
        if [ -n "$net_id" ]; then
            suffix=$(echo $RANDOM | md5sum | head -c 4)
            port_id=$(timeout $SRVTO openstack port create --project admin --device-owner cube:diag --host=$HOSTNAME -c id -f value --network $net_id diag-$HOSTNAME-$suffix 2>/dev/null)
            if [ -n "$port_id" ]; then
                timeout $SRVTO openstack port delete $port_id
            else
                err_code=6
            fi
        fi
    fi

    health_fail_log "neutron" $err_code "$service_stats"
    local r=$?
    health_neutron_auto_repair $err_code $r "$service_stats"
    return $r
}

health_neutron_auto_repair()
{
    local err_code=$1
    local true_fail=$2
    local stats=${*:3}

    if [ "$err_code" != "0" -a "$true_fail" == "0" ]; then
        openstack port list -f value -c ID -c Name | grep "diag[-]" | cut -d " " -f1 | xargs -i openstack port delete {}
        if [ $err_code -eq 6 ]; then
            cubectl node exec -r control -pn -- hex_sdk os_neutron_worker_scale
        else
            ovn_neutron_db_sync

            readarray entry_array <<<"$(echo "$stats" | awk '/False/{print $1" "$3}' | sort)"
            declare -p entry_array > /dev/null
            for entry in "${entry_array[@]}"
            do
                local srv=$(echo $entry | awk '{print $2}')
                local host=$(echo $entry | awk '{print $1}')
                if [ -n "$host" ]; then
                    remote_systemd_restart $host $srv
                fi
            done
        fi
    fi
    return 0
}

health_neutron_repair()
{
    cubectl node exec -p /usr/sbin/hex_config bootstrap neutron >/dev/null 2>&1

    ovn_neutron_db_sync

    local net_id=$(timeout $SRVTO openstack subnet list | awk '/ lb-mgmt-subnet / {print $6}')
    if [ -n "$net_id" ]; then
        timeout 900 openstack port delete $(timeout $SRVTO openstack port list --network $net_id -f value -c ID -c Name 2>/dev/null | grep diag | awk '{print $1}') >/dev/null 2>&1
    fi

    local agent_list=$(timeout $SRVTO openstack network agent list -f json -c ID -c Alive)
    for i in $(echo $agent_list | jq -r ".[].ID"); do
        alive=$(echo $agent_list | jq -r ".[] | select(.ID == \"$i\").Alive")
        if [ "x$alive" = "xfalse" ]; then
            openstack network agent delete $i
        fi
    done
}

# glance

health_glance_report()
{
    if health_glance_check; then
        h="healthy"
        e="available"
        c=$(openstack image list -f value -c ID | wc -l )
    else
        h="unhealthy"
        e="unavailable"
        c="N/A"
    fi
    printf "+%12s+%14s+%12s+\n" | tr " " "-"
    printf "| %-10s | %-12s | %-10s |\n" "Status" "API Endpoint" "Images"
    printf "+%12s+%14s+%12s+\n" | tr " " "-"
    printf "| %-10s | %-12s | %-10s |\n" $h $e $c
    printf "+%12s+%14s+%12s+\n" | tr " " "-"
}

health_glance_check()
{
    stale_api_check_repair openstack-glance-api 9292 glance-api python3

    local http_stats=$(influx -host $(shared_id) -database monasca -format json -execute "select last(value) from http_status where service = 'image-service'" | jq .results[0].series[0].values[0][1])
    if [ "$http_stats" != "0" ]; then
        health_fail_log "glance" 1 "endpoint unreachable"
        return $?
    fi

    local err_code=0
    local err_msg=
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl openstack-glance-api; then
            err_code=3
            err_msg="${err_msg}glance-api of $ctrl is down\n"
        fi
    done

    health_fail_log "glance" $err_code "$err_msg"
    local r=$?
    health_glance_auto_repair $err_code $r
    return $r
}

health_glance_auto_repair()
{
    local err_code=$1
    local true_fail=$2

    if [ "$err_code" != "0" -a "$true_fail" == "0" ]; then
        readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
        declare -p ctrl_array > /dev/null
        for ctrl_entry in "${ctrl_array[@]}"
        do
            local ctrl=$(echo $ctrl_entry | head -c -1)
            if ! is_remote_running $ctrl openstack-glance-api; then
                remote_systemd_restart $ctrl openstack-glance-api
            fi
        done
    fi

    return 0
}

health_glance_repair()
{
    cubectl node exec -p /usr/sbin/hex_config restart_glance >/dev/null 2>&1
    return 0
}

# cinder

health_cinder_report()
{
    timeout $SRVTO openstack volume service list
}

health_cinder_check()
{
    stale_api_check_repair openstack-cinder-api 8776 cinder-api python3

    local http_stats=$(influx -host $(shared_id) -database monasca -format json -execute "select last(value) from http_status where service = 'block-storage'" | jq .results[0].series[0].values[0][1])
    if [ "$http_stats" != "0" ]; then
        health_fail_log "cinder" 1 "endpoint unreachable"
        return $?
    fi

    local service_stats=$(timeout $SRVTO openstack volume service list -f value -c Binary -c Status -c State 2>/dev/null)
    if [ -z "$service_stats" ]; then
        health_fail_log "cinder" 2 "service api timeout"
        return $?
    fi

    local err_code=0
    local scheduler_up=$(echo "$service_stats" | grep scheduler | grep -i enabled | grep -i up | wc -l )
    local scheduler_down=$(echo "$service_stats" | grep scheduler | grep -i enabled | grep -i down | wc -l )
    local volume_up=$(echo "$service_stats" | grep volume | grep -i enabled | grep -i up | wc -l )
    local volume_down=$(echo "$service_stats" | grep volume | grep -i enabled | grep -i down | wc -l )
    local backup_up=$(echo "$service_stats" | grep backup | grep -i enabled | grep -i up | wc -l )
    local backup_down=$(echo "$service_stats" | grep backup | grep -i enabled | grep -i down | wc -l )
    if [ "$scheduler_up" == "0" -o "$scheduler_down" != "0" ]; then
        err_code=3
    elif [ "$volume_up" == "0" -o "$volume_down" != "0" ]; then
        err_code=4
    elif [ "$backup_up" == "0" -o "$backup_down" != "0" ]; then
        err_code=5
    fi

    health_fail_log "cinder" $err_code "$service_stats"
    local r=$?
    health_cinder_auto_repair $err_code $r "$service_stats"
    return $r
}

health_cinder_auto_repair()
{
    local err_code=$1
    local true_fail=$2
    local stats=${*:3}

    if [ "$err_code" != "0" -a "$true_fail" == "0" ]; then
        readarray entry_array <<<"$(echo "$stats" | awk '/enabled.*down/{print $1" "$2}' | sort)"
        declare -p entry_array > /dev/null
        for entry in "${entry_array[@]}"
        do
            local srv=$(echo $entry | awk '{print $1}')
            local host=$(echo $entry | awk '{print $2}' | tr -d '\n')
            if [ "$srv" == "cinder-volume" ]; then
                if [ $(cubectl node list -r control | wc -l) -eq 1 ]; then
                    systemctl restart openstack-$srv
                else
                    pcs resource cleanup cinder-volume >/dev/null 2>&1
                    pcs resource enable cinder-volume >/dev/null 2>&1
                    pcs resource restart cinder-volume >/dev/null 2>&1
                fi
            else
                if [ -n "$host" -a -n "$srv" ]; then
                    remote_systemd_restart $host openstack-$srv
                fi
            fi
        done
    fi

    return 0
}

health_cinder_repair()
{
    cubectl node exec -p /usr/sbin/hex_config restart_cinder >/dev/null 2>&1
    return 0
}

# manila

health_manila_report()
{
    manila service-list
}

health_manila_check()
{
    stale_api_check_repair openstack-manila-api 8786 manila-api python3

    local service_stats=$(timeout $SRVTO manila service-list 2>/dev/null)
    if [ -z "$service_stats" ]; then
        health_fail_log "manila" 2 "service api timeout"
        return $?
    fi

    local err_code=0
    local scheduler_up=$(echo "$service_stats" | grep manila-scheduler | grep -i enabled | grep -i up | wc -l )
    local scheduler_down=$(echo "$service_stats" | grep manila-scheduler | grep -i enabled | grep -i down | wc -l )
    local share_up=$(echo "$service_stats" | grep manila-share | grep -i enabled | grep -i up | wc -l )
    local share_down=$(echo "$service_stats" | grep manila-share | grep -i enabled | grep -i down | wc -l )
    local share_total=$(cubectl node list -r compute -j | jq -r .[].hostname | head -3 | wc -l)
    if [ "$scheduler_up" == "0" -o "$scheduler_down" != "0" ]; then
        err_code=3
    elif [ "$share_up" != "$share_total" -o "$share_down" != "0" ]; then
        err_code=4
    fi

    health_fail_log "manila" $err_code "$service_stats"
    local r=$?
    health_manila_auto_repair $err_code $r "$service_stats"
    return $r
}

health_manila_auto_repair()
{
    local err_code=$1
    local true_fail=$2
    local stats=${*:3}

    if [ "$err_code" != "0" -a "$true_fail" == "0" ]; then
        if [ $(openstack network list | grep manila_service_network | wc -l) -gt 1 ]; then
            for NID in $(openstack network list -f value -c ID -c Name | grep manila_service_network | cut -d' ' -f1); do
                openstack port list --network $NID -f value -c ID | xargs -i openstack port delete {}
                openstack network delete $NID
            done
        fi
        readarray entry_array <<<"$(echo "$stats" | awk '/enabled.*down/{print $4" "$6}' | sort)"
        declare -p entry_array > /dev/null
        for entry in "${entry_array[@]}"
        do
            local srv=$(echo $entry | awk '{print $1}')
            local host=$(echo $entry | awk '{print $2}' | awk -F'@' '{print $1}' | tr -d '\n')
            if [ -n "$host" ]; then
                if [ -n "$srv" -a "$srv" == "manila-share" ]; then
                    os_manila_service_remove $host $srv
                fi
                remote_systemd_restart $host openstack-$srv
            fi
        done
        for cmp in $(cubectl node list -r compute -j | jq -r .[].hostname | head -3)
        do
            local host=$(echo $cmp | tr -d '\n')
            if [ -n "$host" ]; then
                remote_systemd_restart $host openstack-manila-share
            fi
        done
    fi

    return 0
}

health_manila_repair()
{
    cubectl node exec -p /usr/sbin/hex_config restart_manila >/dev/null 2>&1
    return 0
}

# swift

health_swift_report()
{
    if health_swift_check; then
        local service_stats=$(openstack object store account show -f json)
        h="healthy"
        e="available"
        c=$(echo $service_stats | jq -r .Objects)
        o=$(echo $service_stats | jq -r .Objects)
    else
        h="unhealthy"
        e="unavailable"
        c="N/A"
        o="N/A"
    fi
    printf "+%12s+%14s+%8s+%12s+%12s+\n" | tr " " "-"
    printf "| %-10s | %-12s | %-6s | %-10s | %-10s |\n" "Status" "API Endpoint" "Tenant" "Containers" "Objects"
    printf "+%12s+%14s+%8s+%12s+%12s+\n" | tr " " "-"
    printf "| %-10s | %-12s | %-6s | %-10s | %-10s |\n" $h $e "admin" $c $o
    printf "+%12s+%14s+%8s+%12s+%12s+\n" | tr " " "-"
}

health_swift_check()
{
    $CURL -sf http://$HOSTNAME:8888 >/dev/null
    if [ $? -ne 0 ] ; then
        health_fail_log "swift" 1 "endpoint unreachable"
        return $?
    fi

    local service_stats=$(timeout $SRVTO openstack object store account show -f json 2>/dev/null)
    if [ -z "$service_stats" ]; then
        health_fail_log "swift" 2 "service api timeout"
        return $?
    fi

    local err_code=0
    local object_count=$(echo $service_stats | jq -r .Objects)
    if [ ! $object_count -ge 0 ]; then
        health_fail_log "swift" 3 "$service_stats"
        return $?
    fi
}

# heat

health_heat_report()
{
    health_heat_check
    local r=$?
    if [ $r -eq 0 -o $r -eq 1 ]; then
        local service_stats=$(timeout $SRVLTO openstack orchestration service list -f value -c Status 2>/dev/null)
        e="available"
        u=$(echo "$service_stats" | grep -i up | wc -l)
        d=$(echo "$service_stats" | grep -i down | wc -l)
        if [ $r -eq 0 ]; then
            h="healthy"
        else
            h="unhealthy"
        fi
    else
        h="unhealthy"
        e="unavailable"
        u="0"
        d="0"
    fi
    printf "+%12s+%14s+%18s+\n" | tr " " "-"
    printf "| %-10s | %-12s | %16s |\n" "Status" "API Endpoint" "Engine (Up/Down)"
    printf "+%12s+%14s+%18s+\n" | tr " " "-"
    printf "| %-10s | %-12s | %16s |\n" $h $e "$u/$d"
    printf "+%12s+%14s+%18s+\n" | tr " " "-"
}

health_heat_check()
{
    stale_api_check_repair openstack-heat-api 8004 heat-api python3
    stale_api_check_repair openstack-heat-api-cfn 8000 heat-api-cfn python3

    local http_stats=$(influx -host $(shared_id) -database monasca -format json -execute "select last(value) from http_status where service = 'orchestration'" | jq .results[0].series[0].values[0][1])
    if [ "$http_stats" != "0" ]; then
        health_fail_log "heat" 1 "endpoint unreachable"
        return $?
    fi

    local service_stats=$(timeout $SRVLTO openstack orchestration service list -f value -c Hostname -c Binary -c Status | sort | uniq 2>/dev/null)
    if [ -z "$service_stats" ]; then
        health_fail_log "heat" 2 "service api timeout"
        return $?
    fi

    local err_code=0
    local engine_up=$(echo "$service_stats" | grep -i up | wc -l )
    if [ "$engine_up" == "0" ]; then
        err_code=3
    fi

    health_fail_log "heat" $err_code "$service_stats"
    local r=$?
    health_heat_auto_repair $err_code $r "$service_stats"
    return $r
}

health_heat_auto_repair()
{
    local err_code=$1
    local true_fail=$2
    local stats=${*:3}

    if [ "$err_code" != "0" -a "$true_fail" == "0" ]; then
        readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
        declare -p ctrl_array > /dev/null
        for ctrl_entry in "${ctrl_array[@]}"
        do
            local ctrl=$(echo $ctrl_entry | head -c -1)
            if ! is_remote_running $ctrl openstack-heat-api; then
                remote_systemd_restart $ctrl openstack-heat-api
            elif ! is_remote_running $ctrl openstack-heat-api-cfn; then
                remote_systemd_restart $ctrl openstack-heat-api-cfn
            fi
        done

        readarray entry_array <<<"$(echo "$stats" | awk '/down/{print $1" "$2}' | sort)"
        declare -p entry_array > /dev/null
        for entry in "${entry_array[@]}"
        do
            local srv=$(echo $entry | awk '{print $2}')
            local host=$(echo $entry | awk '{print $1}')
            if [ -n "$host" ]; then
                remote_systemd_restart $host openstack-$srv
            fi
        done
    fi

    return 0
}

health_heat_repair()
{
    cubectl node exec -r control -p /usr/sbin/hex_config restart_heat >/dev/null 2>&1
    return 0
}

# octavia

health_octavia_report()
{
    health_report ${FUNCNAME[0]}
}

health_octavia_check()
{
    stale_api_check_repair octavia-api 9876 octavia-api python3

    local http_stats=$(influx -host $(shared_id) -database monasca -format json -execute "select last(value) from http_status where service = 'octavia'" | jq .results[0].series[0].values[0][1])
    if [ "$http_stats" != "0" ]; then
        health_fail_log "octavia" 1 "endpoint unreachable"
        return $?
    fi

    local err_code=0
    local err_msg=
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl octavia-api; then
            err_msg="${err_msg}octavia-api of $ctrl is not running\n"
            err_code=3
        elif ! is_remote_running $ctrl octavia-housekeeping; then
            err_msg="${err_msg}octavia-housekeeping of $ctrl is not running\n"
            err_code=4
        fi
    done
    readarray comp_array <<<"$(cubectl node list -r compute -j | jq -r .[].hostname | head -3)"
    declare -p comp_array > /dev/null
    for comp_entry in "${comp_array[@]}"
    do
        local comp=$(echo $comp_entry | head -c -1)
        if ! remote_run $comp ovs-vsctl port-to-br octavia-hm0 >/dev/null 2>&1; then
            err_msg="${err_msg}no octavia-hm0 ovn port found in $comp\n"
            err_code=5
        elif remote_run $comp ip link show octavia-hm0 | grep -q DOWN; then
            err_msg="${err_msg}no link octavia-hm0 found in $comp\n"
            err_code=6
        elif ! remote_run $comp route -n | grep -q octavia-hm0; then
            err_msg="${err_msg}no route from octavia-hm0 found in $comp\n"
            err_code=7
        elif ! is_remote_running $comp octavia-worker; then
            err_msg="${err_msg}octavia-worker of $comp is not running\n"
            err_code=8
        elif ! is_remote_running $comp octavia-health-manager; then
            err_msg="${err_msg}octavia-health-manager of $comp is not running\n"
            err_code=9
        fi
    done

    health_fail_log "octavia" $err_code "$err_msg"
    local r=$?
    health_octavia_auto_repair $err_code $r
    return $r
}

health_octavia_auto_repair()
{
    local err_code=$1
    local true_fail=$2

    if [ "$err_code" != "0" -a "$true_fail" == "0" ]; then
        readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
        declare -p ctrl_array > /dev/null
        for ctrl_entry in "${ctrl_array[@]}"
        do
            local ctrl=$(echo $ctrl_entry | head -c -1)
            if ! is_remote_running $ctrl octavia-api; then
                remote_systemd_restart $ctrl octavia-api
            elif ! is_remote_running $ctrl octavia-housekeeping; then
                remote_systemd_restart $ctrl octavia-housekeeping
            fi
        done

        readarray comp_array <<<"$(cubectl node list -r compute -j | jq -r .[].hostname | head -3)"
        declare -p comp_array > /dev/null
        for comp_entry in "${comp_array[@]}"
        do
            local comp=$(echo $comp_entry | head -c -1)
            if ! is_remote_running $comp octavia-worker; then
                remote_systemd_restart $comp octavia-worker
            elif ! is_remote_running $comp octavia-health-manager; then
                remote_systemd_restart $comp octavia-health-manager
            fi
        done
    fi

    return 0
}

health_octavia_repair()
{
    # master node should run first before other nodes
    local master=$(cubectl node list -r control -j | jq -r .[].hostname | head -n 1)
    remote_run $master /usr/sbin/hex_config reinit_octavia >/dev/null 2>&1

    cubectl node exec -p /usr/sbin/hex_config reinit_octavia >/dev/null 2>&1
    return 0
}

# designate

health_designate_report()
{
    health_report ${FUNCNAME[0]}
    timeout $SRVTO openstack dns service list
}

health_designate_check()
{
    stale_api_check_repair designate-api 9001 designate-api python3

    local http_stats=$(influx -host $(shared_id) -database monasca -format json -execute "select last(value) from http_status where service = 'dns'" | jq .results[0].series[0].values[0][1])
    if [ "$http_stats" != "0" ]; then
        health_fail_log "designate" 1 "endpoint unreachable"
        return $?
    fi

    local service_stats=$(timeout $SRVTO openstack dns service list -f value -c hostname -c service_name -c status 2>/dev/null)
    if [ -z "$service_stats" ]; then
        health_fail_log "designate" 2 "service api timeout"
        return $?
    fi

    local err_code=0
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl designate-api; then
            err_code=3
        elif ! is_remote_running $ctrl designate-central; then
            err_code=4
        elif ! is_remote_running $ctrl designate-worker; then
            err_code=5
        elif ! is_remote_running $ctrl designate-producer; then
            err_code=6
        elif ! is_remote_running $ctrl designate-mdns; then
            err_code=7
        elif ! is_remote_running $ctrl named; then
            err_code=8
        fi
    done

    local api_up=$(echo "$service_stats" | grep api | grep -i up | wc -l )
    local api_down=$(echo "$service_stats" | grep api | grep -i down | wc -l )
    local central_up=$(echo "$service_stats" | grep central | grep -i up | wc -l )
    local central_down=$(echo "$service_stats" | grep central | grep -i down | wc -l )
    local worker_up=$(echo "$service_stats" | grep worker | grep -i up | wc -l )
    local worker_down=$(echo "$service_stats" | grep worker | grep -i down | wc -l )
    local producer_up=$(echo "$service_stats" | grep producer | grep -i up | wc -l )
    local producer_down=$(echo "$service_stats" | grep producer | grep -i down | wc -l )
    local mdns_up=$(echo "$service_stats" | grep mdns | grep -i up | wc -l )
    local mdns_down=$(echo "$service_stats" | grep mdns | grep -i down | wc -l )
    if [ "$api_up" == "0" -o "$api_down" != "0" ]; then
        err_code=9
    elif [ "$central_up" == "0" -o "$central_down" != "0" ]; then
        err_code=10
    elif [ "$worker_up" == "0" -o "$worker_down" != "0" ]; then
        err_code=11
    elif [ "$producer_up" == "0" -o "$producer_down" != "0" ]; then
        err_code=12
    elif [ "$mdns_up" == "0" -o "$mdns_down" != "0" ]; then
        err_code=13
    fi

    health_fail_log "designate" $err_code "$service_stats"
    local r=$?
    health_designate_auto_repair $err_code $r "$service_stats"
    return $r
}

health_designate_auto_repair()
{
    local err_code=$1
    local true_fail=$2
    local stats=${*:3}

    if [ "$err_code" != "0" -a "$true_fail" == "0" ]; then
        readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
        declare -p ctrl_array > /dev/null
        for ctrl_entry in "${ctrl_array[@]}"
        do
            local ctrl=$(echo $ctrl_entry | head -c -1)
            if ! is_remote_running $ctrl designate-api; then
                remote_systemd_restart $ctrl designate-api
            elif ! is_remote_running $ctrl designate-central; then
                remote_systemd_restart $ctrl designate-central
            elif ! is_remote_running $ctrl designate-worker; then
                remote_systemd_restart $ctrl designate-worker
            elif ! is_remote_running $ctrl designate-producer; then
                remote_systemd_restart $ctrl designate-producer
            elif ! is_remote_running $ctrl designate-mdns; then
                remote_systemd_restart $ctrl designate-mdns
            elif ! is_remote_running $ctrl named; then
                local master=$(cubectl node list -r control -j | jq -r .[].hostname | head -n 1)
                remote_run $master /usr/local/bin/cubectl node rsync -r control /etc/designate/rndc.key
                remote_systemd_restart $ctrl named
            fi
        done

        readarray entry_array <<<"$(echo "$stats" | awk '/DOWN/{print $1" "$2}' | sort)"
        declare -p entry_array > /dev/null
        for entry in "${entry_array[@]}"
        do
            local srv=$(echo $entry | awk '{print $2}')
            local host=$(echo $entry | awk '{print $1}')
            if [ -n "$host" ]; then
                remote_systemd_restart $host designate-$srv
            fi
        done
    fi

    return 0
}

health_designate_repair()
{
    local master=$(cubectl node list -r control -j | jq -r .[].hostname | head -n 1)
    remote_run $master /usr/local/bin/cubectl node rsync -r control /etc/designate/rndc.key

    cubectl node exec -r control -p /usr/sbin/hex_config restart_designate >/dev/null 2>&1
    return 0
}

# masakari

health_masakari_report()
{
    health_report ${FUNCNAME[0]}
}

health_masakari_check()
{
    stale_api_check_repair masakari-api 15868 masakari-api python3

    $CURL -sf http://$HOSTNAME:15868 >/dev/null
    if [ $? -ne 0 ] ; then
        health_fail_log "masakari" 1 "endpoint unreachable"
        return $?
    fi

    local err_code=0
    local err_msg=
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl masakari-api; then
            err_msg="${err_msg}masakari-api of $ctrl is not running\n"
            err_code=3
        elif ! is_remote_running $ctrl masakari-engine; then
            err_msg="${err_msg}masakari-engine of $ctrl is not running\n"
            err_code=4
        fi
    done
    readarray cmp_array <<<"$(cubectl node list -r compute -j | jq -r .[].hostname | sort)"
    declare -p cmp_array > /dev/null
    for cmp_entry in "${cmp_array[@]}"
    do
        local cmp=$(echo $cmp_entry | head -c -1)
        if ! is_remote_running $cmp masakari-processmonitor; then
            err_msg="${err_msg}masakari-processmonitor of $cmp is not running\n"
            err_code=5
        elif ! is_remote_running $cmp masakari-hostmonitor; then
            err_msg="${err_msg}masakari-hostmonitor of $cmp is not running\n"
            err_code=6
        elif ! is_remote_running $cmp masakari-instancemonitor; then
            err_msg="${err_msg}masakari-instancemonitor of $cmp is not running\n"
            err_code=7
        fi
    done

    health_fail_log "masakari" $err_code "$err_msg"
    local r=$?
    health_masakari_auto_repair $err_code $r
    return $r
}

health_masakari_auto_repair()
{
    local err_code=$1
    local true_fail=$2

    if [ "$err_code" != "0" -a "$true_fail" == "0" ]; then
        readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
        declare -p ctrl_array > /dev/null
        for ctrl_entry in "${ctrl_array[@]}"
        do
            local ctrl=$(echo $ctrl_entry | head -c -1)
            if ! is_remote_running $ctrl masakari-api; then
                remote_systemd_restart $ctrl masakari-api
            elif ! is_remote_running $ctrl masakari-engine; then
                remote_systemd_restart $ctrl masakari-engine
            fi
        done
        readarray cmp_array <<<"$(cubectl node list -r compute -j | jq -r .[].hostname | sort)"
        declare -p cmp_array > /dev/null
        for cmp_entry in "${cmp_array[@]}"
        do
            local cmp=$(echo $cmp_entry | head -c -1)
            if ! is_remote_running $cmp masakari-processmonitor; then
                remote_systemd_restart $cmp masakari-processmonitor
            elif ! is_remote_running $cmp masakari-hostmonitor; then
                remote_systemd_restart $cmp masakari-hostmonitor
            elif ! is_remote_running $cmp masakari-instancemonitor; then
                remote_systemd_restart $cmp masakari-instancemonitor
            fi
        done
    fi

    return 0
}

health_masakari_repair()
{
    cubectl node exec -p /usr/sbin/hex_config restart_masakari >/dev/null 2>&1
    return 0
}

# monasca

health_monasca_report()
{
    health_report ${FUNCNAME[0]}
}

health_monasca_check()
{
    local err_code=0
    local err_msg=
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl monasca-persister; then
            err_msg="${err_msg}monasca-persister of $ctrl is not running\n"
            err_code=3
        fi
    done
    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if ! is_remote_running $node monasca-collector; then
            err_msg="${err_msg}monasca-collector of $node is not running\n"
            err_code=4
        elif ! is_remote_running $node monasca-forwarder; then
            err_msg="${err_msg}monasca-forwarder of $node is not running\n"
            err_code=5
        elif ! is_remote_running $node monasca-statsd; then
            err_msg="${err_msg}monasca-statsd of $node is not running\n"
            err_code=6
        fi
    done

    health_fail_log "monasca" $err_code "$err_msg"
    local r=$?
    health_monasca_auto_repair $err_code $r
    return $r
}

health_monasca_auto_repair()
{
    local err_code=$1
    local true_fail=$2

    if [ "$err_code" != "0" -a "$true_fail" == "0" ]; then
        readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
        declare -p ctrl_array > /dev/null
        for ctrl_entry in "${ctrl_array[@]}"
        do
            local ctrl=$(echo $ctrl_entry | head -c -1)
            if ! is_remote_running $ctrl monasca-persister; then
                remote_systemd_restart $ctrl monasca-persister
            fi
        done
        readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
        declare -p node_array > /dev/null
        for node_entry in "${node_array[@]}"
        do
            local node=$(echo $node_entry | head -c -1)
            if ! is_remote_running $node monasca-collector; then
                remote_systemd_restart $node monasca-collector
            elif ! is_remote_running $node monasca-forwarder; then
                remote_systemd_restart $node monasca-forwarder
            elif ! is_remote_running $node monasca-statsd; then
                remote_systemd_restart $node monasca-statsd
            fi
        done
    fi

    return 0
}

health_monasca_repair()
{
    cubectl node exec -p /usr/sbin/hex_config restart_monasca >/dev/null 2>&1
    return 0
}

# senlin

health_senlin_report()
{
    timeout $SRVTO openstack cluster service list
}

health_senlin_check()
{
    stale_api_check_repair openstack-senlin-api 8777 senlin-api python3

    local service_stats=$(timeout $SRVTO openstack cluster service list -f value -c host -c binary -c status -c state 2>/dev/null)
    if [ -z "$service_stats" ]; then
        health_fail_log "senlin" 2 "service api timeout"
        return $?
    fi

    local err_code=0
    local engine_up=$(echo "$service_stats" | grep senlin-engine | grep -i enabled | grep -i up | wc -l )
    local engine_down=$(echo "$service_stats" | grep senlin-engine | grep -i enabled | grep -i down | wc -l )
    local conductor_up=$(echo "$service_stats" | grep senlin-conductor | grep -i enabled | grep -i up | wc -l )
    local conductor_down=$(echo "$service_stats" | grep senlin-conductor | grep -i enabled | grep -i down | wc -l )
    local hmgr_up=$(echo "$service_stats" | grep senlin-health-manager | grep -i enabled | grep -i up | wc -l )
    local hmgr_down=$(echo "$service_stats" | grep senlin-health-manager | grep -i enabled | grep -i down | wc -l )
    if [ "$engine_up" == "0" -o "$engine_down" != "0" ]; then
        err_code=3
    elif [ "$conductor_up" == "0" -o "$conductor_down" != "0" ]; then
        err_code=4
    elif [ "$hmgr_up" == "0" -o "$hmgr_down" != "0" ]; then
        err_code=5
    fi

    health_fail_log "senlin" $err_code "$service_stats"
    local r=$?
    health_senlin_auto_repair $err_code $r "$service_stats"
    return $r
}

health_senlin_auto_repair()
{
    local err_code=$1
    local true_fail=$2
    local stats=${*:3}

    if [ "$err_code" != "0" -a "$true_fail" == "0" ]; then
        readarray entry_array <<<"$(echo "$stats" | awk '/enabled.*down/{print $1" "$2}' | sort)"
        declare -p entry_array > /dev/null
        for entry in "${entry_array[@]}"
        do
            local srv=$(echo $entry | awk '{print $1}')
            local host=$(echo $entry | awk '{print $2}')
            if [ -n "$host" ]; then
                remote_systemd_restart $host openstack-$srv
            fi
        done
    fi

    return 0
}

health_senlin_repair()
{
    cubectl node exec -r control -p /usr/sbin/hex_config restart_senlin >/dev/null 2>&1
    return 0
}

# watcher

health_watcher_report()
{
    timeout $SRVTO openstack optimize service list
}

health_watcher_check()
{
    stale_api_check_repair openstack-watcher-api 9322 watcher-api python3

    local service_stats=$(timeout $SRVTO openstack optimize service list -f value -c Name -c Host -c Status 2>/dev/null)
    if [ -z "$service_stats" ]; then
        health_fail_log "watcher" 2 "service api timeout"
        return $?
    fi

    local err_code=0
    local applier_up=$(echo "$service_stats" | grep watcher-applier | grep -i ACTIVE | wc -l )
    local applier_down=$(echo "$service_stats" | grep watcher-applier | grep -i FAILED | wc -l )
    local engine_up=$(echo "$service_stats" | grep watcher-decision-engine | grep -i ACTIVE | wc -l )
    local engine_down=$(echo "$service_stats" | grep watcher-decision-engine | grep -i FAILED | wc -l )
    if [ "$applier_up" == "0" -o "$applier_down" != "0" ]; then
        err_code=3
    elif [ "$engine_up" == "0" -o "$engine_down" != "0" ]; then
        err_code=4
    fi

    health_fail_log "watcher" $err_code "$service_stats"
    local r=$?
    health_watcher_auto_repair $err_code $r "$service_stats"
    return $r
}

health_watcher_auto_repair()
{
    local err_code=$1
    local true_fail=$2
    local stats=${*:3}

    if [ "$err_code" != "0" -a "$true_fail" == "0" ]; then
        readarray entry_array <<<"$(echo "$stats" | awk '/FAILED/{print $1" "$2}' | sort)"
        declare -p entry_array > /dev/null
        for entry in "${entry_array[@]}"
        do
            local srv=$(echo $entry | awk '{print $1}')
            local host=$(echo $entry | awk '{print $2}')
            if [ -n "$host" ]; then
                remote_systemd_restart $host openstack-$srv
            fi
        done
    fi

    return 0
}

health_watcher_repair()
{
    cubectl node exec -r control -p /usr/sbin/hex_config restart_watcher >/dev/null 2>&1
    return 0
}

# k3s

health_k3s_report()
{
    cubectl config status k3s
}

health_k3s_check()
{
    local err_code=0

    if ! cubectl config check k3s 2>/dev/null ; then
        err_code=1
    fi

    health_fail_log "k3s" $err_code "$(health_k3s_report)"
}

health_k3s_repair()
{
    cubectl config repair k3s
}

# rancher

health_rancher_report()
{
    cubectl config status rancher
}

health_rancher_check()
{
    T_rancher_enabled=$(grep rancher.enabled /etc/settings.txt | tail -1 | awk -F'= ' '{print $2}' | tr -d '\n')
    if [ "$T_rancher_enabled" == "false" ]; then
        return 0
    fi

    local err_code=0

    if ! cubectl config check rancher 2>/dev/null ; then
        err_code=1
    fi

    health_fail_log "rancher" $err_code "$(health_rancher_report)"
}

health_rancher_repair()
{
    cubectl config repair rancher
}

# this is going to purge existing rancher data, using it with cautions
health_rancher_rebuild()
{
    cubectl node exec cubectl config reset --hard rancher k3s
    cubectl node exec cubectl config commit k3s rancher
}

# opensearch

health_opensearch_report()
{
    health_report ${FUNCNAME[0]}
}

health_opensearch_check()
{
    local err_code=0
    local err_msg=0

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl opensearch; then
            err_code=1
            err_msg="${err_msg}opensearch of $ctrl is not running\n"
        fi
    done
    local node_total=$(cubectl node list -r control | wc -l)
    local stats=$($CURL -q http://localhost:9200/_cluster/health 2>/dev/null)
    local status=$(echo $stats | jq -r .status)
    local online=$(echo $stats | jq -r .number_of_nodes)
    err_msg="${err_msg}$stats\n"
    if [ "$node_total" != "$online" ]; then
        err_code=2
    elif [ "$status" != "green" ]; then
        err_code=3
    fi

    health_fail_log "opensearch" $err_code "$err_msg"
}

health_opensearch_repair()
{
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        remote_systemd_restart $ctrl opensearch
    done
}

# zookeeper

health_zookeeper_report()
{
    health_report ${FUNCNAME[0]}
}

health_zookeeper_check()
{
    local node_total=$(cubectl node list -r control | wc -l)
    if [ "$node_total" == "2" ]; then
        readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort | head -1)"
    else
        readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    fi

    local err_code=0
    local err_msg=0

    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl zookeeper; then
            err_code=1
            err_msg="${err_msg}zookeeper of $ctrl is not running\n"
        fi
        local online=$(echo dump | nc $ctrl 2181 | grep brokers | wc -l)
        if [ "$node_total" != "$online" ]; then
            err_code=2
            err_msg="${err_msg}$online/$node_total brokers are online\n"
        fi
    done

    health_fail_log "zookeeper" $err_code "$err_msg"
}

health_zookeeper_repair()
{
    health_datapipe_deep_repair >/dev/null 2>&1
}

# kafka

health_kafka_report()
{
    health_report ${FUNCNAME[0]}
}

health_kafka_check()
{
    local err_code=0
    local err_msg=

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl kafka; then
            err_code=1
            err_msg="${err_msg}kafka of $ctrl is not running\n"
        fi
    done

    # check the last line of telegraf log
    if journalctl -u telegraf -n 1 | grep -q "E\!.*Failed.*telegraf.*metrics"; then
        err_code=2
        err_msg="${err_msg}kafka fails to get sys/host metrics\n"
    fi

    # check the last 5 minutes from monasca persister log
    if ! awk -v dt="$(date '+%Y-%m-%d %T' -d '-5 minutes')" -F, '$1 > dt' /var/log/monasca/persister.log | grep -q "Processed .* messages from topic 'metrics'"; then
        err_code=3
        err_msg="${err_msg}kafka fails to get instance metrics\n"
    fi

    # check the last 3 seconds from logstash log
    if awk -v dt="$(date '+%Y-%m-%dT%H:%M:%S' -d '3 second ago')" -F'[[,]' '$2 > dt' /var/log/logstash/logstash.log | grep -q "NOT_LEADER_OR_FOLLOWER"; then
        err_code=4
        err_msg="${err_msg}kafka queues has no leader\n"
    fi

    if awk -v dt="$(date '+%Y-%m-%dT%H:%M:%S' -d '3 second ago')" -F'[[,]' '$2 > dt' /var/log/logstash/logstash.log | grep -q "NOT_COORDINATOR"; then
        err_code=5
        err_msg="${err_msg}kafka queues has no coordinator\n"
    fi

    local queue_num=$(kafka_stats | grep "PartitionCount: 6" | wc -l)
    # the six most important queues: telegraf-metrics, telegraf-hc-metrics, metrics, logs, transformed-logs, alarms
    if [ $queue_num -lt 6 ]; then
        err_code=6
        err_msg="${err_msg}kafka has no built-in queues\n"
    fi

    _OVERRIDE_MAX_ERR=18 health_fail_log "kafka" $err_code "$err_msg"
    local r=$?
    health_kafka_auto_repair $err_code $r
    return $r
}

health_kafka_auto_repair()
{
    local err_code=$1
    local true_fail=$2

    if [ "$true_fail" != "0" ]; then
        return 0
    fi

    if [ "$err_code" == "2" ]; then
        if journalctl -u telegraf -n 1 | grep -q "E\!.*Failed.*telegraf-metrics"; then
            hex_config recreate_kafka_topic "telegraf-metrics"
        fi
        if journalctl -u telegraf -n 1 | grep -q "E\!.*Failed.*telegraf-hc-metrics"; then
            hex_config recreate_kafka_topic "telegraf-hc-metrics"
        fi
        if journalctl -u telegraf -n 1 | grep -q "E\!.*Failed.*telegraf-events-metrics"; then
            hex_config recreate_kafka_topic "telegraf-events-metrics"
        fi
    fi

    if [ "$err_code" == "3" ]; then
        hex_config recreate_kafka_topic "metrics"
        cubectl node -r control exec -p systemctl restart monasca-persister >/dev/null
    fi

    if [ "$err_code" == "4" ]; then
        hex_config recreate_kafka_topic "transformed-logs"
    fi

    if [ "$err_code" == "5" ]; then
        hex_config recreate_kafka_topic "__consumer_offsets"
    fi

    if [ "$err_code" == "6" ]; then
        hex_config update_kafka_topics
    fi

    return 0
}

health_kafka_repair()
{
    health_datapipe_deep_repair >/dev/null 2>&1
    # reset error count to bring back auto_repair()
    rm -f /tmp/health_kafka_error.count
}

# telegraf

health_telegraf_report()
{
    health_report ${FUNCNAME[0]}
}

health_telegraf_check()
{
    local err_code=0
    local err_msg=

    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if ! ssh root@$node ps ax 2>/dev/null | grep -v grep | grep -q /usr/bin/telegraf ; then
            err_code=1
            err_msg="${err_msg}telegraf of $node is not running\n"
        fi
    done

    health_fail_log "telegraf" $err_code "$err_msg"
}

health_telegraf_repair()
{
    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if ! ssh root@$node ps ax 2>/dev/null | grep -v grep | grep -q /usr/bin/telegraf ; then
            remote_systemd_restart $node telegraf
        fi
    done
}

# influxdb

health_influxdb_report()
{
    health_report ${FUNCNAME[0]}
}

health_influxdb_check()
{
    local err_code=0
    local err_msg=

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if remote_run $ctrl /usr/sbin/hex_sdk is_moderator_node >/dev/null 2>&1 ; then
            continue
        fi
        if ! is_remote_running $ctrl influxdb; then
            err_code=1
            err_msg="${err_msg}influxdb of $ctrl is not running\n"
        fi
        $CURL -sf http://$ctrl:8086 >/dev/null
        if [ $? -eq 7 ] ; then
            err_code=2
            err_msg="${err_msg}influxdb of $ctrl doesn't respond\n"
        fi
    done

    health_fail_log "influxdb" $err_code "$err_msg"
}

health_influxdb_repair()
{
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if remote_run $ctrl /usr/sbin/hex_sdk is_moderator_node >/dev/null 2>&1 ; then
            continue
        fi
        if ! is_remote_running $ctrl influxdb; then
            remote_systemd_restart $ctrl influxdb
        fi
        $CURL -sf http://$ctrl:8086 >/dev/null
        if [ $? -eq 7 ] ; then
            remote_systemd_restart $ctrl influxdb
        fi
    done
}

# kapacitor

health_kapacitor_report()
{
    health_report ${FUNCNAME[0]}
}

health_kapacitor_check()
{
    local err_code=0
    local err_msg=

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! ssh root@$ctrl ps ax 2>/dev/null | grep -v grep | grep -q /usr/bin/kapacitord ; then
            err_code=1
            err_msg="${err_msg}kapacitor of $ctrl is not running\n"
        fi
        $CURL -sf http://$ctrl:9092 >/dev/null
        if [ $? -eq 7 ] ; then
            err_code=2
            err_msg="${err_msg}kapacitor of $ctrl doesn't respond\n"
        fi
    done

    health_fail_log "kapacitor" $err_code "$err_msg"
}

health_kapacitor_repair()
{
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! ssh root@$ctrl ps ax 2>/dev/null | grep -v grep | grep -q /usr/bin/kapacitord ; then
            remote_systemd_restart $ctrl kapacitor
        fi
        $CURL -sf http://$ctrl:9092 >/dev/null
        if [ $? -eq 7 ] ; then
            remote_systemd_restart $ctrl kapacitor
        fi
    done
}

# grafana

health_grafana_report()
{
    health_report ${FUNCNAME[0]}
}

health_grafana_check()
{
    local err_code=0
    local err_msg=

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl grafana-server; then
            err_code=1
            err_msg="${err_msg}grafana of $ctrl is not running\n"
        fi
        $CURL -sf http://$ctrl:3000 >/dev/null
        if [ $? -eq 7 ] ; then
            err_code=2
            err_msg="${err_msg}grafana of $ctrl doesn't respond\n"
        fi
    done

    health_fail_log "grafana" $err_code "$err_msg"
}

health_grafana_repair()
{
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl grafana-server; then
            remote_systemd_restart $ctrl grafana-server
        fi
        $CURL -sf http://$ctrl:3000 >/dev/null
        if [ $? -eq 7 ] ; then
            remote_systemd_restart $ctrl grafana-server
        fi
    done
}

# filebeat

health_filebeat_report()
{
    health_report ${FUNCNAME[0]}
}

health_filebeat_check()
{
    local err_code=0
    local err_msg=

    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if ! is_remote_running $node filebeat; then
            err_code=1
            err_msg="${err_msg}filebeat of $node is not running\n"
        fi
    done

    health_fail_log "filebeat" $err_code "$err_msg"
}

health_filebeat_repair()
{
    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if ! is_remote_running $node filebeat; then
            remote_systemd_restart $node filebeat
        fi
    done
}

# auditbeat

health_auditbeat_report()
{
    health_report ${FUNCNAME[0]}
}

health_auditbeat_check()
{
    local err_code=0
    local err_msg=

    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if ! is_remote_running $node auditbeat; then
            err_code=1
            err_msg="${err_msg}auditbeat of $node is not running\n"
        fi
    done

    health_fail_log "auditbeat" $err_code "$err_msg"
}

health_auditbeat_repair()
{
    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        if ! is_remote_running $node auditbeat; then
            remote_systemd_restart $node auditbeat
        fi
    done
}

# logstash

health_logstash_report()
{
    health_report ${FUNCNAME[0]}
}

health_logstash_check()
{
    local err_code=0
    local err_msg=

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if cubectl node list -r control | grep "^${ctrl}," | grep -q moderator; then
            continue
        fi
        if ! is_remote_running $ctrl logstash; then
            err_code=1
            err_msg="${err_msg}logstash of $ctrl is not running\n"
        fi
    done

    health_fail_log "logstash" $err_code "$err_msg"
}

health_logstash_repair()
{
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if cubectl node list -r control | grep "^${ctrl}," | grep -q moderator; then
            continue
        fi
        if ! is_remote_running $ctrl logstash; then
            remote_systemd_restart $ctrl logstash
        fi
    done
}

# opensearch-dashboards

health_opensearch-dashboards_report()
{
    health_report ${FUNCNAME[0]}
}

health_opensearch-dashboards_check()
{
    local err_code=0
    local err_msg=

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl opensearch-dashboards; then
            err_code=1
            err_msg="${err_msg}opensearch-dashboards of $ctrl is not running\n"
        fi
        $CURL -sf http://$ctrl:5601 >/dev/null
        if [ $? -eq 7 ] ; then
            err_code=2
            err_msg="${err_msg}opensearch-dashboards of $ctrl doesn't respond\n"
        fi
    done

    health_fail_log "opensearch_dashboards" $err_code "$err_msg"
}

health_opensearch-dashboards_repair()
{
    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}"
    do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        if ! is_remote_running $ctrl opensearch-dashboards; then
            remote_systemd_restart $ctrl opensearch-dashboards
        fi
        $CURL -sf http://$ctrl:5601 >/dev/null
        if [ $? -eq 7 ] ; then
            remote_systemd_restart $ctrl opensearch-dashboards
        fi
    done
}

# deep repair

health_neutron_deep_repair()
{
    # OVN DBs location: non-HA -> /var/lib/ovn/, HA -> /etc/ovn/
    cubectl node -r control exec -p -- rm -f /etc/ovn/ovnnb_db.db /etc/ovn/ovnsb_db.db /var/lib/ovn/ovnnb_db.db /var/lib/ovn/ovnsb_db.db
    cubectl node exec -p -- rm -f /etc/openvswitch/conf.db
    health_neutron_repair
}

health_datapipe_deep_repair()
{
    cubectl node -r control exec -p systemctl stop zookeeper kafka logstash kapacitor influxdb monasca-forwarder monasca-persister telegraf >/dev/null
    sleep 10
    cubectl node -r control exec -p rm -rf /tmp/zookeeper/* /var/lib/kafka/* /var/lib/logstash/* >/dev/null

    cubectl node -r control exec -p systemctl stop zookeeper kafka logstash kapacitor influxdb monasca-forwarder monasca-persister telegraf >/dev/null
    sleep 10
    cubectl node -r control exec -p rm -rf /tmp/zookeeper/* /var/lib/kafka/* /var/lib/logstash/* >/dev/null

    cubectl node -r control exec -p hex_config bootstrap kafka >/dev/null
    cubectl node -r control exec -p hex_config bootstrap logstash >/dev/null
    hex_config update_kafka_topics
    cubectl node -r control exec -p systemctl reset-failed
    cubectl node -r control exec -p systemctl start kapacitor influxdb monasca-forwarder monasca-persister telegraf >/dev/null
    cubectl node -r control exec -p systemctl restart httpd >/dev/null
}

health_hypervisor_check()
{
    if ! (timeout $SRVTO cubectl node exec "[ -e /run/cube_commit_done ]" >/dev/null 2>&1); then
        echo "Pre-condition not met: not all nodes are bootstrapped!"
        return 1
    fi

    local max=10
    readarray cmpt_array <<<"$(cubectl node list -r compute -j | jq -r .[].hostname | sort)"
    declare -p cmpt_array > /dev/null
    for cmpt_entry in "${cmpt_array[@]}"
    do
        local srv=
        local cmpt=$(echo $cmpt_entry | head -c -1)
        if ! is_remote_running $cmpt libvirtd; then
            srv=libvirtd
        elif ! is_remote_running $cmpt openstack-nova-compute; then
            srv=openstack-nova-compute
        fi
        [ -n "$srv" ] || continue

        # Only control node with VIP takes actions
        if [ $(/usr/sbin/hex_config status_pacemaker | awk '/IPaddr2/{print $5}') = $(hostname) ]; then
            for cnt in $(seq $max); do
                echo "Failed to run $srv on node: $cmpt ($cnt)"
                if remote_systemd_restart $cmpt $srv; then
                    sleep 5
                fi
                if is_remote_running $cmpt $srv ; then
                    echo "On $cmpt $srv is successfully restarted"
                    break
                fi
            done
            if [ $cnt -ge $max ]; then
                echo "Ceph entering maintenance mode to avoid data reblancing"
                ceph_enter_maintenance
                echo "Stopping server instances on node: $cmpt"
                remote_run $cmpt reboot || true

                while ping -c 1 $cmpt >/dev/null
                do
                    echo "Waiting for cluster to detect problematic node: $cmpt"
                    sleep 10
                done

                sleep 30 && openstack server list --long || true

                if os_post_failure_host_evacuation $cmpt | grep "still in use"; then
                    sleep 60
                    os_post_failure_host_evacuation $cmpt
                fi
                echo "Evacuating server instances from $cmpt"
                break
            fi
        fi
    done
}

health_nodelist_check()
{
    local thisnode=$(cubectl node list -j)
    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"
    do
        local node=$(echo $node_entry | head -c -1)
        local nextnode=$(remote_run $node "cubectl node list -j")
        if [ "x$thisnode" != "x$nextnode" ]; then
            return 1
        fi
    done
}

health_nodelist_report()
{
    cubectl node list
}

health_check_toggle()
{
    local SRV=${1:-NOSUCHSERVICE}
    [ "x$SRV" != "xNOSUCHSERVICE" ] || Error "$SRV"
    hex_sdk | grep -q "^health_${SRV}_check$" || Error "no health_${SRV}_check"
    local MKF=/etc/appliance/state/health_${SRV}_enabled
    if [ -e $MKF ]; then
        cubectl node exec -pn rm -f $MKF
    else
        cubectl node exec -pn touch $MKF
    fi
    [ "$VERBOSE" != "1" ] || health_check_toggle_status $SRV
}

health_check_toggle_status()
{
    local SRV=${1:-NOSUCHSERVICE}
    [ "x$SRV" != "xNOSUCHSERVICE" ] || Error "$SRV"
    hex_sdk | grep -q "^health_${SRV}_check$" || Error "no health_${SRV}_check"
    local MKF=/etc/appliance/state/health_${SRV}_enabled

    if [ -e $MKF ]; then
        echo -n "enabled"
    else
        echo -n "disabled"
    fi
}
