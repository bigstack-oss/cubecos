# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

source ${SDK_DIR}/modules/errcodes
# _check is invoked by lmi which lacks persmissions to run
# ssh commands like is_remote_running. Wrap it with /usr/sbin/hex_config sdk_run
ERR_CODE=0                      # health_check error code
ERR_MSG=                        # health_check error message
ERR_LOG=                        # health_check log file
ERR_LOGSIZE=100                 # health_check log size (number of lines)
DESCRIPTION=                    # health_check result description

health_errcode_dump()
{
    printf "%22s %3s %s\n" "component" "err" "description"
    for srvidx in $(echo ${!ERR_CODE[@]} | tr ' ' '\n' | sort | uniq) ; do
        srv=$(echo $srvidx | cut -d"," -f1)
        idx=$(echo $srvidx | cut -d"," -f2)
        printf "%22s %3s %s\n" "$srv" "$idx" "${ERR_CODE[$srvidx]}"
    done
}

health_errcode_lookup()
{
    local srv=${1:-NOSUCHSRV}
    local err=${2:-0}

    if [ $err -eq 0 ] ; then
        echo -n ok
    else
        echo -n ${ERR_CODE[$srv,$err]:-$err undefined}
    fi
}

_health_report()
{
    local tmp=${1%_report}
    local srv=${tmp#health_}
    local chk=${tmp}_check
    $chk 2>/dev/null
    local err=$?

    if [ $err -eq 0 ] ; then
        local hth="healthy"
    else
        local hth="unhealthy"
    fi
    local des=${DESCRIPTION:-$(health_errcode_lookup $srv $err)}

    if [ "$FORMAT" = "none" ] ; then
        :
    elif [ "$FORMAT" = "json" ] ; then
        cat <<EOF
{"status" : "$hth","error_code" : "$err","description" : "$des"}
EOF
    elif [ "$FORMAT" = "shell" ] ; then
        cat <<EOF
status=$hth
error_code=$err
description="$des"
EOF
    elif [ "$FORMAT" = "line" ] ; then
        printf "status=$hth,error_code=$err,description=$des\n"
    else
        printf "+%12s+%12s+%44s+\n" | tr " " "-"
        printf "| %-10s | %10s | %42s |\n" "status" "error_code" "description"
        printf "+%12s+%12s+%44s+\n" | tr " " "-"
        printf "| %-10s | %10s | %42s |\n" $hth $err "$des"
        printf "+%12s+%12s+%44s+\n" | tr " " "-"
    fi
}

_health_fail_log()
{
    local srv=$(caller 0 | cut -d" " -f2 | sed -e "s/^health_//" -e "s/_check$//")

    [ "$VERBOSE" != "1" ] || echo -e "$ERR_MSG"
    [ `cubectl node exec -pn "[ -e $CUBE_DONE ] && echo 0" | wc -l` -eq ${#CUBE_NODE_LIST_HOSTNAMES[@]} ] || return $ERR_CODE

    local maxerr=6
    if [ -f /etc/alert.level ] ; then
        maxerr=$(cat /etc/alert.level | tr -d '\n')
    fi

    if [ -f /etc/alert.level.${srv} ] ; then
        maxerr=$(cat /etc/alert.level.${srv} | tr -d '\n')
    fi

    if [ ${_OVERRIDE_MAX_ERR:-0} -gt 0 ] ; then
        maxerr=$_OVERRIDE_MAX_ERR
    fi

    local count=0
    if [ -f /tmp/health_${srv}_error.count ] ; then
        count=$(cat /tmp/health_${srv}_error.count | tr -d '\n')
    fi

    local query=
    local description="$(health_errcode_lookup $srv $ERR_CODE)"
    if [ -e $HEX_STATE_DIR/health_${srv}_check_disabled ] ; then
        description="disabled"
        ERR_CODE=0
    fi
    if [ "$ERR_CODE" == "0" ] ; then
        rm -f /tmp/health_${srv}_error.count
    else
        let "count = $count + 1"
        echo "==============================" >> /var/log/health_${srv}_error.log
        echo $(date) >> /var/log/health_${srv}_error.log
        echo "failed count: $count" >> /var/log/health_${srv}_error.log
        echo "error code: $ERR_CODE" >> /var/log/health_${srv}_error.log
        echo "error desc: $description" >> /var/log/health_${srv}_error.log
        echo -e "$ERR_MSG" $'\n' >> /var/log/health_${srv}_error.log
        echo $count > /tmp/health_${srv}_error.count
        if [ $count -lt $maxerr ] ; then
            local auto_repair_func="_health_${srv}_auto_repair"
            if Quiet type $auto_repair_func 2>/dev/null ; then
                query="insert health,component=$srv,node=$HOSTNAME,code=$ERR_CODE description=\"fixing\""
                if ! $INFLUX -database events -execute "${query},detail=\"auto repair ($count/$maxerr)\"" ; then
                    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
                        timeout $SRVSTO /usr/bin/influx -host $node -database events -execute "${query},detail=\"auto repair ($count/$maxerr)\""
                    done
                fi
                $auto_repair_func
            fi
        fi
    fi

    cat <<EOF >/run/health_${srv}_check
{"SERVICE" : "$srv","ERROR_CODE" : "$ERR_CODE","DESCRIPTION" : "$description"}
EOF

    local err_msg_oneline=`echo -e "$ERR_MSG" | paste -s -d';' /dev/stdin`
    local log="${srv}-${node}-$(date +%s)-$(mktemp -u XXXX)"
    local log_pth="log/$log"
    local log_url=
    rm -f /tmp/$log
    query="insert health,component=$srv,node=$HOSTNAME,code=$ERR_CODE description=\"$description\""
    if [ "x$ERR_LOG" != "x" -a $ERR_CODE -ne 0 ] ; then
        local keys="$($OPENSTACK ec2 credentials list --user admin -c Access -c Secret -f value | head -n 1)"
        if [ "x$keys" = "x" ] ; then
            Quiet -n $OPENSTACK ec2 credentials create --user admin --project admin
            keys="$($OPENSTACK ec2 credentials list --user admin -c Access -c Secret -f value | head -n 1)"
            keys=$keys $HEX_SDK os_s3_bucket_create admin log >/dev/null 2>&1
        fi
        # Only when there're valid keys would we be able to save logs
        if [ "x$keys" != "x" ] ; then
            timeout $SRVSTO cubectl node exec -p "if [ -f \"$ERR_LOG\" ] ; then tail -n $ERR_LOGSIZE $ERR_LOG ; else $ERR_LOG ; fi" > /tmp/$log
            if [ -e /tmp/${log:-NOSUCHLOG} ] ; then
                keys=$keys $HEX_SDK os_s3_object_put admin /tmp/$log $log_pth >/dev/null 2>&1 || keys=$keys $HEX_SDK os_s3_bucket_create admin log
                log_url="s3://$log_pth"
                rm -f /tmp/$log
            else
                # In case collecting logs from remote fails, look for local log
                if [ -e $ERR_LOG ] ; then
                    tail -n $ERR_LOGSIZE $ERR_LOG > /tmp/$log
                    keys=$keys $HEX_SDK os_s3_object_put admin $ERR_LOG $log_pth >/dev/null 2>&1 || keys=$keys $HEX_SDK os_s3_bucket_create admin log
                    log_url="s3://$log_pth"
                fi
            fi
        fi
    fi
    $INFLUX -database events -execute "${query},log=\"${log_url}\",detail=\"${err_msg_oneline}\""

    return $ERR_CODE
}

health_link_report()
{
    _health_report ${FUNCNAME[0]}
}

health_link_check()
{
    for ip in "${CUBE_NODE_LIST_IPS[@]}" ; do
        ERR_MSG+="Ping $ip ... "
        ping -c 1 -w 1 $ip >/dev/null || ERR_CODE=1
        if [ "x$ERR_CODE" = "x0" ] ; then
            ERR_MSG+="OK\n"
        else
            ERR_MSG+="FAILED\n"
            ERR_LOG=/var/log/messages
        fi
    done

    _health_fail_log
}

health_mtu_report()
{
    _health_report ${FUNCNAME[0]}
}

health_mtu_check()
{
    local netpth=/sys/class/net
    declare -A ifcs_mtus

    for ifc in $(ls -1 $netpth | egrep -v '^veth|^tap|^lo|^eth|^bonding_masters') ; do
        ifcs_mtus[$ifc]=$(cat $netpth/$ifc/mtu | xargs)
    done
    for ifc in ${!ifcs_mtus[@]}; do
        if ! cubectl node exec "if ip link show $ifc >/dev/null 2>&1 ; then ip link show $ifc | grep -q -i \"mtu ${ifcs_mtus[$ifc]}\" ; fi" >/dev/null 2>&1 ; then
            ERR_CODE=1
            ERR_MSG+="$(cubectl node exec -p ip link show $ifc)\n"          
        fi
    done

    _health_fail_log
}

health_dns_report()
{
    _health_report ${FUNCNAME[0]}
}

health_dns_check()
{
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        local real=$(timeout $SRVSTO ssh root@$node time arp -a 2>&1 | grep real | awk '{print $2}') || ERR_CODE=1
        if [ "x$ERR_CODE" = "x0" ] ; then
            ERR_MSG+="$node DNS lookup took $real\n"
        else
            ERR_MSG+="$node dns lookup timed out\n"
        fi
    done

    _health_fail_log
}

health_clock_report()
{
    _health_report ${FUNCNAME[0]}
}

health_clock_check()
{
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        local delta=$(clockdiff $node 2>/dev/null | awk '{print $2}')
        if [ -n "$delta" ] ; then
            if [ ${delta#-} -gt 10000 ] ; then
                ERR_CODE=1
                ERR_MSG+="time difference to $node is ${delta}ms\n"
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u chronyd"
            fi
        fi
    done

    _health_fail_log
}

health_clock_repair()
{
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        remote_run $node $HEX_SDK ntp_makestep
    done
}

health_settings_report()
{
    _health_report ${FUNCNAME[0]}
}

health_settings_check()
{
    local num_node=${#CUBE_NODE_LIST_HOSTNAMES[@]}

    for V in $(cat $SETTINGS_TXT | egrep -v "^#|^$" | cut -d"=" -f1 | sed 's/ $//' | tr "." "_") ; do
        local CNT_UNIQ=$(timeout $SRVTO cubectl node exec -pn "source $HEX_TUN $SETTINGS_TXT ; echo \$T_${V}" | sort -u | wc -l)
        ERR_MSG+="`timeout $SRVTO cubectl node exec -r control -pn \"source $HEX_TUN $SETTINGS_TXT ; echo \\$HOSTNAME ${V}=\\$T_${V}\" | sort -u`\n"
        case $V in
            cubesys_role|cubesys_mgmt_cidr|cubesys_control_vip|cubesys_overlay|cubesys_provider|cubesys_storage|cubesys_management|net_if_*|ntp_server|cubesys_probeusb)
                if [ ${CNT_UNIQ:-0} -ne 1 ] ; then
                    ERR_MSG+="ignored\n"
                    continue
                fi
                ;;
            *_alert_*)
                CNT_UNIQ=$(timeout $SRVTO cubectl node exec -r control -pn "source $HEX_TUN $SETTINGS_TXT ; echo \$T_${V}" | sort -u | wc -l)
                if [ ${CNT_UNIQ:-0} -ne 1 ] ; then
                    ERR_CODE=1
                fi
                ;;
            net_hostname)
                if [ ${CNT_UNIQ:-0} -ne ${num_node:-3} ] ; then
                    ERR_CODE=1
                fi
                ;;
            *)
                if [ ${CNT_UNIQ:-0} -ne 1 ] ; then
                    ERR_CODE=1
                fi
                ;;
        esac
    done

    _health_fail_log
}

health_bootstrap_report()
{
    _health_report ${FUNCNAME[0]}
}

health_bootstrap_check()
{
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        if ! remote_run $node stat $CUBE_DONE >/dev/null 2>&1 ; then
            ERR_CODE=1
            ERR_MSG+="$node services ... [n/a]\n"
        else
            ERR_MSG+="$node services ... [ready]\n"
        fi
    done

    _health_fail_log
}

health_license_report()
{
    ERR_MSG+="$(hex_cli -c license show)\n"
    _health_report ${FUNCNAME[0]}
}

health_license_check()
{
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        remote_run $node $HEX_CFG license_check >/dev/null 2>&1
        local r=$?
        if [ $r -ne 0 -a $r -ne 1 -a $r -ne 252 ] ; then
            ERR_CODE=1
            ERR_MSG+="$node $(license_error_string $r)\n"
            ERR_LOG="hex_cli -c license show"
            break
        fi
    done

    _health_fail_log
}

health_etcd_report()
{
    ERR_MSG+="$($ETCDCTL endpoint health --cluster 2>&1)\n"
    _health_report ${FUNCNAME[0]}
}

health_etcd_check()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node etcd ; then
            ERR_CODE=1
            ERR_MSG+="$node etcd is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u etcd"
        fi
    done

    local total=$($ETCDCTL member list 2>/dev/null | wc -l)
    local online=$($ETCDCTL endpoint health --cluster 2>/dev/null | grep healthy | wc -l)
    if [ "$total" != "$online" -o $online -eq 0 ] ; then
        ERR_CODE=2
        ERR_MSG+="$online/$total etcd are online\n"
        ERR_LOG="$$HEX_SDK cmd ETCDCTL endpoint health --cluster"
    fi

    _health_fail_log
}

health_etcd_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node etcd ; then
            remote_systemd_restart $node etcd
        fi
    done
}

health_hacluster_report()
{
    ERR_MSG+="$(pcs status)\n"
    _health_report ${FUNCNAME[0]}
}

health_hacluster_check()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node corosync ; then
            ERR_CODE=1
            ERR_MSG+="corosync on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u corosync"
        elif ! is_remote_running $node pacemaker ; then
            ERR_CODE=2
            ERR_MSG+="pacemaker on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u pacemaker"
        elif ! is_remote_running $node pcsd ; then
            ERR_CODE=3
            ERR_MSG+="pcsd on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u pcsd"
        fi
    done

    local status=$($HEX_CFG status_pacemaker)
    local total=${#CUBE_NODE_CONTROL_HOSTNAMES[@]}
    local online=$(echo "$status" | grep -i " online" | cut -d "[" -f2 | cut -d "]" -f1 | awk '{print NF}')
    if [ "$total" != "$online" ] ; then
        ERR_CODE=4
        ERR_MSG+="$online/$total nodes are online\n"
        ERR_LOG="pcs status"
    fi
    local offline=$(echo "$status" | grep -i " offline" | cut -d "[" -f3 | cut -d "]" -f1 | awk '{print NF}')
    if [ -n "$offline" ] ; then
        ERR_CODE=5
        ERR_MSG+="$offline nodes are offline\n"
        ERR_LOG="pcs status"
    fi

    local active_host=$(echo "$status" | awk '/IPaddr2/{print $5}')
    # is HA ?
    if [ -n "$active_host" ] ; then
        # cinder-volume
        if ! echo "$status" | grep -q "cinder-volume.*Started" ; then
            ERR_CODE=6
            ERR_MSG+="cinder-volume is not started\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-cinder-volume"
        fi

        # ovndb_servers
        if echo "$status" | grep -q "ovndb_servers.*FAILED" ; then
            ERR_CODE=7
            ERR_MSG+="ovndb_servers is not started\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u ovsdb-server"
        fi
    fi

    readarray node_array <<<"$(cubectl node list -r compute | awk -F',' '/compute/{print $1}' | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"; do
        local node=$(echo $node_entry | head -c -1)
        if [ -n "$node" ] ; then
            if ! is_remote_running $node pcsd ; then
                ERR_CODE=8
                ERR_MSG+="pcsd on $node is not running\n"
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u pcsd"
            elif ! is_remote_running $node pacemaker_remote ; then
                ERR_CODE=9
                ERR_MSG+="pacemaker_remote on $node is not running\n"
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u pacemaker_remote"
            fi
        fi
    done

    local rtotal=$(cubectl node list -r compute | awk -F',' '/compute/{print $1}' | wc -l)
    local ronline=$(echo "$status" | grep -i " RemoteOnline" | cut -d "[" -f2 | cut -d "]" -f1 | awk '{print NF}')
    if [ -n "$ronline" -a "$rtotal" != "$ronline" ] ; then
        ERR_CODE=10
        ERR_MSG+="$ronline/$rtotal remote nodes are online\n"
    fi
    local roffline=$(echo "$status" | grep -i " RemoteOFFLINE" | cut -d "[" -f3 | cut -d "]" -f1 | awk '{print NF}')
    if [ -n "$roffline" ] ; then
        ERR_CODE=11
        ERR_MSG+="$roffline remote nodes are offline\n"
    fi

    _health_fail_log
}

health_hacluster_repair()
{
    health_hacluster_check
    if [ $? -eq 6 ] ; then
        health_ceph_mds_repair
        health_cinder_repair
        pcs resource cleanup cinder-volume >/dev/null 2>&1
        pcs resource enable cinder-volume >/dev/null 2>&1
        pcs resource restart cinder-volume >/dev/null 2>&1
    fi

    pcs resource cleanup >/dev/null 2>&1

    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        remote_run $node rm /var/lib/corosync/*
        remote_systemd_stop $node pcsd pacemaker corosync
    done
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        remote_systemd_start $node corosync pacemaker pcsd
        sleep 5
    done

    for node in "${CUBE_NODE_COMPUTE_HOSTNAMES[@]}" ; do
        remote_systemd_stop $node pcsd pacemaker_remote
    done
    for node in "${CUBE_NODE_COMPUTE_HOSTNAMES[@]}" ; do
        remote_systemd_start $node pacemaker_remote pcsd
        sleep 5
    done
}

health_rabbitmq_report()
{
    if [ "$VERBOSE" = "1" ] ; then
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
    fi
    _health_report ${FUNCNAME[0]}
}

health_rabbitmq_check()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node rabbitmq-server ; then
            ERR_CODE=1
            ERR_MSG+="rabbitmq on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u rabbitmq-server"
        fi
    done

    local config=${#CUBE_NODE_CONTROL_HOSTNAMES[@]}
    local stats=$($HEX_CFG status_rabbitmq)
    local online=$(echo $stats | jq -r .running_nodes[] | wc -l)
    local partition=$(echo $stats | jq -r .partitions[] | wc -l)

    if [ "$config" != "$online" ] ; then
        ERR_CODE=2
        ERR_MSG+="$online/$config nodes are online\n"
        ERR_LOG="$HEX_CFG status_rabbitmq"
    fi
    if [ "$partition" != "0" ] ; then
        ERR_CODE=3
        ERR_MSG+="$partition partitions exist\n"
        ERR_LOG="$HEX_CFG status_rabbitmq"
    fi

    Quiet -n $HEX_SDK rabbitmq_unhealthy_queue_clear

    _health_fail_log
}

health_rabbitmq_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        remote_systemd_stop $node rabbitmq-server
        remote_run $node rm -rf /var/lib/rabbitmq/mnesia/*
        remote_run $node rm -f $HEX_STATE_DIR/rabbitmq_cluster_done
    done

    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        remote_run $node $HEX_CFG restart_rabbitmq
        sleep 8
    done
}

health_mysql_report()
{
    if [ "$VERBOSE" = "1" ] ; then
        $MYSQL -u root -e "show global status like 'wsrep_cluster_status'" | grep wsrep_cluster_status
        $MYSQL -u root -e "show global status like 'wsrep_cluster_size'" | grep wsrep_cluster_size
        $MYSQL -u root -e "show global status like 'wsrep_local_state_comment'" | grep wsrep_local_state_comment
    fi
    _health_report ${FUNCNAME[0]}
}

health_mysql_check()
{
    local node_total=${#CUBE_NODE_CONTROL_HOSTNAMES[@]}
    local status=$($MYSQL -u root -e "show global status like 'wsrep_cluster_status'" | grep wsrep_cluster_status | awk '{print $2}')
    local online=$($MYSQL -u root -e "show global status like 'wsrep_cluster_size'" | grep wsrep_cluster_size | awk '{print $2}')
    local state=$($MYSQL -u root -e "show global status like 'wsrep_local_state_comment'" | grep wsrep_local_state_comment | awk '{print $2}')
    if [ $node_total -eq 1 ] ; then
        if [ "$status" != "Disconnected" ] ; then
            ERR_CODE=1
            ERR_MSG+="mysql is disconnected\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u mariadb"
        fi
    else
        if [ "$node_total" != "$online" ] ; then
            ERR_CODE=2
            ERR_MSG+="$online/$node_total nodes are online\n"
            ERR_LOG="$MYSQL -u root -e \"show global status like 'wsrep_cluster_status'\""
        elif [ "$state" != "Synced" ] ; then
            ERR_CODE=3
            ERR_MSG+="mysql cluster doesn't sync-ed\n"
            ERR_LOG="$MYSQL -u root -e \"show global status like 'wsrep_local_state_comment'\""
        fi
    fi

    _health_fail_log
}

health_mysql_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        # mariadbd might hang and unable to stop in some circumstances
        local pid=$(remote_run $node pidof mariadbd)
        if [ -n "$pid" ] ; then
            remote_run $node kill -9 $pid
        fi
        remote_systemd_stop $node mariadb
    done
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        remote_run $node touch $HEX_STATE_DIR/mysql_new_cluster
        remote_run $node $HEX_CFG restart_mysql
    done
}

health_vip_report()
{
    _health_report ${FUNCNAME[0]}
}

health_vip_check()
{
    local active_host=$($HEX_CFG status_pacemaker | awk '/IPaddr2/{print $5}')
    DESCRIPTION="non-HA"

    if [ -n "$active_host" ] ; then
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            local ipcidr=$(remote_run $node ip addr list | awk '/ secondary /{print $2}')
            local ipaddr=$(echo $ipcidr | cut -d"/" -f1)
            if [ "$node" == "$active_host" ] ; then
                DESCRIPTION="$ipcidr@$active_host"
                if [ -z "$ipcidr" ] ; then
                    ERR_CODE=1
                    ERR_MSG+="$ipcidr should be active on $node\n"
                    ERR_LOG="pcs status"
                elif [ $(cubectl node exec -np "arping -c 1 -w 1 $ipaddr >/dev/null && arp -n $ipaddr" | grep "^${ipaddr}" | awk '{print $1, $3}' | sort -u | wc -l) -gt 1 ] ; then
                    ERR_CODE=3
                    ERR_MSG+="stale VIP in arp table\n"
                    ERR_LOG="cubectl node exec -p arp -e -n $ipaddr"
                fi
            else
                if [ -n "$ipcidr" ] ; then
                    ERR_CODE=2
                    ERR_MSG+="$ipcidr shouldn't be active on $node\n"
                    ERR_LOG="pcs status"
                fi
            fi
        done
    fi

    _health_fail_log
}

_health_vip_auto_repair()
{
    if [ "$ERR_CODE" == "3" ] ; then
        Quiet -n cubectl node exec -np "arp -d $ipaddr ; arping -c 1 -w 1 $ipaddr"
    fi
}

health_vip_repair()
{
    local active_host=$($HEX_CFG status_pacemaker | awk '/IPaddr2/{print $5}')
    if [ -n "$active_host" ] ; then
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            local ipaddr=$(remote_run $node ip addr list | awk '/ secondary /{print $2}')
            local ifname=$(remote_run $node ip addr list | awk '/ secondary /{print $NF}')
            if [ "$node" == "$active_host" ] ; then
                if [ -z "$ipaddr" ] ; then
                    pcs resource disable vip
                    pcs resource enable vip
                    Quiet -n cubectl node exec -np "arp -d $ipaddr ; arping -c 1 -w 1 $ipaddr"
                fi
            else
                if [ -n "$ipaddr" ] ; then
                    ip addr del $ipaddr dev $ifname
                fi
            fi
        done
    fi
}

health_haproxy_ha_report()
{
    local active_host=$($HEX_CFG status_pacemaker | awk '/haproxy-ha/{print $5}')
    if [ -n "$active_host" ] ; then
        DESCRIPTION="$ipaddr@$active_host"
        ERR_MSG+="($active_host)\n"
        ERR_MSG+="`remote_run $active_host $HEX_SDK haproxy_stats /run/haproxy/admin.sock`\n"
    else
        DESCRIPTION="non-HA"
    fi
    _health_report ${FUNCNAME[0]}
}

health_haproxy_ha_check()
{
    local active_host=$($HEX_CFG status_pacemaker | awk '/haproxy-ha/{print $5}')
    if [ -n "$active_host" ] ; then
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            if [ "$node" == "$active_host" ] ; then
                if ! is_remote_running $node haproxy-ha ; then
                    ERR_CODE=1
                    ERR_MSG+="haproxy-ha on $node is not running\n"
                    ERR_LOG="journalctl -n $ERR_LOGSIZE -u haproxy-ha"
                fi
            fi
        done
    fi

    _health_fail_log
}

health_haproxy_ha_repair()
{
    local active_host=$($HEX_CFG status_pacemaker | awk '/haproxy-ha/{print $5}')
    if [ -n "$active_host" ] ; then
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            if [ "$node" == "$active_host" ] ; then
                if ! is_remote_running $node haproxy-ha ; then
                    remote_systemd_restart $node haproxy-ha
                fi
            fi
        done
    fi
}

health_haproxy_report()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        ERR_MSG+="($node)\n"
        ERR_MSG+="`remote_run $node $HEX_SDK haproxy_stats /run/haproxy/admin-local.sock`\n"
    done
    _health_report ${FUNCNAME[0]}
}

health_haproxy_check()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node haproxy >/dev/null 2>&1 ; then
            ERR_CODE=1
            ERR_MSG+="haproxy on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u haproxy"
        fi
    done

    _health_fail_log
}

health_haproxy_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node haproxy >/dev/null 2>&1 ; then
            remote_systemd_restart $node haproxy
        fi
    done
}

health_httpd_report()
{
    _health_report ${FUNCNAME[0]}
}

health_httpd_check()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node httpd ; then
            ERR_CODE=1
            ERR_MSG+="httpd on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u httpd"
        fi
        local i=2
        # monasca(8070)
        # keystone(5000) placement(8778) mellon(5443)
        for port in 8070 5000 8778 5443 ; do
            $CURL -sf http://$node:$port >/dev/null
            # 0: ok, 22: http error (page not found)
            if [ "$?" -ne "0" -a "$?" -ne "22" ] ; then
                ERR_CODE=$i
                ERR_MSG+="http port $port on $node doesn't respond\n"
                ERR_LOG="netstat -tunpl | grep $port"
            fi
            let "i = $i + 1"
        done

        if ! is_edge_node ; then
            # barbican(9311)
            $CURL -sf http://$node:9311 >/dev/null
            # 0: ok, 22: http error (page not found)
            if [ "$?" -ne "0" -a "$?" -ne "22" ] ; then
                ERR_CODE=$i
                ERR_MSG+="http port 9311 on $node doesn't respond\n"
                ERR_LOG="netstat -tunpl | grep 9311"
            fi
        fi
    done

    _health_fail_log
}

health_httpd_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node httpd ; then
            remote_systemd_restart $node httpd
        fi
        for port in 9090 8070 8776 5000 8778 ; do
            $CURL -sf http://$node:$port >/dev/null
            # 0: ok, 22: http error (page not found)
            if [ "$?" -ne "0" -a "$?" -ne "22" ] ; then
                remote_systemd_restart $node httpd
            fi
        done

        if ! is_edge_node ; then
            # barbican(9311)
            $CURL -sf http://$node:9311 >/dev/null
            # 0: ok, 22: http error (page not found)
            if [ "$?" -ne "0" -a "$?" -ne "22" ] ; then
                remote_systemd_restart $node httpd
            fi
        fi
    done
}

health_nginx_report()
{
    _health_report ${FUNCNAME[0]}
}

health_nginx_check()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node nginx >/dev/null 2>&1 ; then
            ERR_CODE=1
            ERR_MSG+="nginx on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u nginx"
        fi
        local i=2
        # ui(8083)
        # skyline(9999)
        for port in 8083 9999 ; do
            $CURL -sf http://$node:$port >/dev/null
            # 0: ok, 22: http error (page not found)
            if [ "$?" -ne "0" -a "$?" -ne "22" ] ; then
                ERR_CODE=$i
                ERR_MSG+="http port $port on $node doesn't respond\n"
                ERR_LOG="netstat -tunpl | grep $port"
            fi
            let "i = $i + 1"
        done
    done

    _health_fail_log
}

_health_nginx_auto_repair()
{
    if [ "$ERR_CODE" == "1" ] ; then
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            if ! is_remote_running $node nginx >/dev/null 2>&1 ; then
                remote_systemd_restart $node nginx
            fi
        done
    elif [ "$ERR_CODE" == "2" ] ; then
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            $CURL -sf http://$node:8083 >/dev/null
            # 0: ok, 22: http error (page not found)
            if [ "$?" -ne "0" -a "$?" -ne "22" ] ; then
                remote_systemd_restart $node nginx
            fi
        done
    elif [ "$ERR_CODE" == "3" ] ; then
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            $CURL -sf http://$node:9999 >/dev/null
            # 0: ok, 22: http error (page not found)
            if [ "$?" -ne "0" -a "$?" -ne "22" ] ; then
                remote_systemd_restart $node nginx
            fi
        done
    fi
}

health_nginx_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node nginx >/dev/null 2>&1 ; then
            remote_systemd_restart $node nginx
        fi

        # ui(8083)
        # skyline(9999)
        for port in 8083 9999 ; do
            $CURL -sf http://$node:$port >/dev/null
            # 0: ok, 22: http error (page not found)
            if [ "$?" -ne "0" -a "$?" -ne "22" ] ; then
                remote_systemd_restart $node nginx
            fi
        done
    done
}

health_api_report()
{
    _health_report ${FUNCNAME[0]}
}

health_api_check()
{
    local port=8082
    local api_log="/var/log/cube-cos-api/cube-cos-api.log"

    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node cube-cos-api >/dev/null 2>&1 ; then
            ERR_CODE=1
            ERR_MSG+="cube-cos-api on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u cube-cos-api"
            continue
        fi

        if [ -e $api_log ] ; then
            tail -n 10 $api_log | grep -q "saml client not found"
            if [ "$?" -eq 0 ] ; then
                ERR_CODE=2
                ERR_MSG+="saml client is not ready for cube-cos-api\n"
                ERR_LOG=$(tail -n 10 $api_log)
                continue
            fi
        fi

        $CURL -sf http://$node:$port >/dev/null
        # 0: ok, 22: http error (page not found)
        if [ "$?" -ne "0" -a "$?" -ne "22" ] ; then
            ERR_CODE=3
            ERR_MSG+="http port $port on $node doesn't respond\n"
            ERR_LOG="netstat -tunpl | grep $port"
        fi
    done

    _health_fail_log
}

_health_api_auto_repair()
{
    if [ "$ERR_CODE" == "1" ] ; then
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            if ! is_remote_running $node cube-cos-api >/dev/null 2>&1 ; then
                remote_systemd_restart $node cube-cos-api
            fi
        done
    elif [ "$ERR_CODE" == "2" ] || [ "$ERR_CODE" == "3" ] ; then
        $HEX_SDK api_idp_config $(shared_ip)
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            $CURL -sf http://$node:8082 >/dev/null
            # 0: ok, 22: http error (page not found)
            if [ "$?" -ne "0" -a "$?" -ne "22" ] ; then
                remote_systemd_restart $node cube-cos-api
            fi
        done
    fi
}

health_api_repair()
{
    $HEX_SDK api_idp_config $(shared_ip)
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node cube-cos-api >/dev/null 2>&1 ; then
            remote_systemd_restart $node cube-cos-api
        fi
        
        $CURL -sf http://$node:8082 >/dev/null
        # 0: ok, 22: http error (page not found)
        if [ "$?" -ne "0" -a "$?" -ne "22" ] ; then
            remote_systemd_restart $node cube-cos-api
        fi
    done
}

health_skyline_report()
{
    _health_report ${FUNCNAME[0]}
}

health_skyline_check()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node nginx >/dev/null 2>&1 ; then
            ERR_CODE=1
            ERR_MSG+="nginx on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u nginx"
        fi
        if ! is_remote_running $node skyline-apiserver >/dev/null 2>&1 ; then
            ERR_CODE=2
            ERR_MSG+="skyline-apiserver on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u skyline-apiserver"
        fi
    done

    _health_fail_log
}

health_skyline_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node nginx >/dev/null 2>&1 ; then
            remote_systemd_restart $node nginx
        fi
        if ! is_remote_running $node skyline-apiserver >/dev/null 2>&1 ; then
            remote_systemd_restart $node skyline-apiserver
        fi
    done
}

health_memcache_report()
{
    _health_report ${FUNCNAME[0]}
}

health_memcache_check()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node memcached ; then
            ERR_CODE=1
            ERR_MSG+="memcached on $node is not running\n"
            ERR_LOG="systemctl status memcached"
        fi
    done

    _health_fail_log
}

health_memcache_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        remote_systemd_restart $node memcached
    done
}

health_keycloak_report()
{
    ERR_MSG+="`cubectl config status keycloak`\n"
    _health_report ${FUNCNAME[0]}
}

health_keycloak_check()
{
    if ! cubectl config check keycloak 2>/dev/null ; then
        ERR_CODE=1
        ERR_MSG+="`cubectl config status keycloak ; k3s kubectl get events -n keycloak | grep -v -i normal | head`\n"
        ERR_LOG+="k3s kubectl describe node $HOSTNAME"
    fi

    _health_fail_log
}

health_keycloak_repair()
{
    cubectl config repair keycloak
}

health_ceph_report()
{
    ERR_MSG+="`$CEPH -s`\n"
    _health_report ${FUNCNAME[0]}
}

health_ceph_check()
{
    local stats=$($CEPH status -f json)
    local service_stats="$(echo $stats | jq -r .health.status)"

    ERR_LOG="$HEX_SDK cmd $CEPH -s"
    if [ "$service_stats" = "HEALTH_WARN" ] ; then
        ERR_CODE=1
    elif [ "$service_stats" = "HEALTH_ERR" ] ; then
        ERR_CODE=2
    fi

    ERR_MSG+="$service_stats\n"
    _health_fail_log
}

_health_ceph_auto_repair()
{
    if [ "$ERR_CODE" == "1" ] ; then
        if $CEPH health detail | grep "application not enabled on pool '.mgr'" ; then
            Quiet -n $CEPH osd pool application enable .mgr mgr
        fi
    fi
}

health_ceph_mon_report()
{
    _health_report ${FUNCNAME[0]}
}

health_ceph_mon_check()
{
    local stats=$($CEPH status -f json)
    local total=$(echo $stats | jq -r .monmap.num_mons)
    local online=$(echo $stats | jq -r .quorum_names[] | wc -l)

    ERR_LOG="/var/log/ceph/ceph-mon*.log"
    if echo $stats | jq -r .health.checks.MON_MSGR2_NOT_ENABLED.summary.message | grep -q "have not enabled msgr2" ; then
        ERR_CODE=1
    elif [ "$total" != "$online" ] ; then
        ERR_CODE=2
    elif echo $stats | jq -r .health | grep -q "mon.* has slow ops" ; then
        ERR_CODE=3
    fi

    _health_fail_log
}

_health_ceph_mon_auto_repair()
{
    if [ "$ERR_CODE" == "1" ] ; then # msgr2 not enabled
        $HEX_SDK ceph_mon_msgr2_enable
    elif [ "$ERR_CODE" == "2" ] ; then # not all online
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            if ! echo $online | grep -q $node ; then
                remote_systemd_restart $node ceph-mon@$node
            fi
        done
    fi
}

health_ceph_mon_repair()
{
    local stats=$($CEPH status -f json)
    local online=$(echo $stats | jq -r .quorum_names[])

    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! echo $online | grep -q $node ; then
            remote_systemd_restart $node ceph-mon@$node
        fi
    done
}

health_ceph_mgr_report()
{
    _health_report ${FUNCNAME[0]}
}

health_ceph_mgr_check()
{
    local active=$($CEPH mgr stat -f json | jq -r .active_name)
    local cnt=0
    local stats=$($CEPH status -f json)
    local total=${#CUBE_NODE_CONTROL_HOSTNAMES[@]}
    local standbys=$(echo $stats | jq -r .mgrmap.num_standbys)
    local MEM=$($HEX_SDK remote_run $active "ps aux | tr -s ' ' | grep \"^ceph \$(pgrep ceph-mgr)\" | cut -d' ' -f4 | cut -d '.' -f1")

    if [ "$total" -gt 1 ] ; then        # ha
        let "online = $standbys + 1"
    else
        if [ "x$active" = "x" ] ; then
            online=0
        else
            online=1
        fi
    fi
    ERR_LOG="$HEX_SDK cmd $CEPH -s"
    if [ "$total" != "$online" ] ; then
        ERR_CODE=1
    elif echo $stats | jq -r .health | grep -q "Failed to list/create InfluxDB database" ; then
        ERR_CODE=2
    elif echo $stats | jq -r .health | grep -q "influx.* has failed:" ; then
        ERR_CODE=3
    elif echo $stats | jq -r .health | grep -q "Module 'devicehealth' has failed: table Device already exists" ; then
        ERR_CODE=4
    elif [ ${MEM:-1} -gt 10 ] ; then
        ERR_CODE=6
    else
        if grep -q "ha = false" $SETTINGS_TXT ; then
            timeout 5 curl -I -k https://${active}:7443/ceph/ 2>/dev/null | grep -q "200 OK" || ERR_CODE=5
        else
            timeout 5 curl -I -k https://${active}:7442/ceph/ 2>/dev/null | grep -q "200 OK" || ERR_CODE=5
        fi
    fi

    ERR_MSG+="`echo $stats | jq -r .mgrmap`\n"

    _health_fail_log
}

_health_ceph_mgr_auto_repair()
{
    if [ "$ERR_CODE" == "1" ] ; then
        Quiet cubectl node exec -r control "systemctl reset-failed ; systemctl restart ceph-mgr@\$HOSTNAME"
    elif [ "$ERR_CODE" == "2" ] ; then
        if [ "$influx_hn" = "non-HA" ] ; then
            influx_hn=$(hostname)
        fi
        $CEPH config set mgr mgr/influx/hostname $influx_hn
        $CEPH config set mgr mgr/influx/interval 60
    elif [ "$ERR_CODE" == "3" ] ; then
        $CEPH mgr module disable influx
        $CEPH mgr module enable influx
    elif [ "$ERR_CODE" == "4" ] ; then
        cubectl node exec -r control -p "systemctl stop ceph-mgr@\$HOSTNAME && sleep 5"
        $CEPH osd pool rename .mgr .mgr-old
        cubectl node exec -r control -p "systemctl start ceph-mgr@\$HOSTNAME"
        $CEPH osd pool delete .mgr-old .mgr-old --yes-i-really-really-mean-it
    elif [ "$ERR_CODE" == "5" ] ; then
        $CEPH mgr module disable dashboard
        $CEPH mgr module enable dashboard
    elif [ "$ERR_CODE" == "6" ] ; then
        $CEPH mgr fail
    fi
}

health_ceph_mgr_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        remote_run $node $HEX_CFG restart_ceph_mgr
    done
}

health_ceph_mds_report()
{
    _health_report ${FUNCNAME[0]}
}

health_ceph_mds_check()
{
    local stats=$($CEPH status -f json | jq -r .fsmap)
    local total=${#CUBE_NODE_CONTROL_HOSTNAMES[@]}
    local active=$(echo $stats | jq -r .up)
    local standbys=$(echo $stats | jq '.["up:standby"]')
    local hotstandbys=$(echo $stats | jq | grep 'up:standby-replay' | wc -l)
    local num_ctrlnode=${#CUBE_NODE_CONTROL_HOSTNAMES[@]}
    local num_nodes=${#CUBE_NODE_LIST_HOSTNAMES[@]}
    local vip=$($HEX_SDK -f json health_vip_report | jq -r .description | cut -d"/" -f1)
    [ "x$vip" != "xnon-HA" ] || vip=$CUBE_NODE_CONTROL_HOSTNAMES
    local nfs_dir=$(mktemp -u /tmp/nfs-XXXX)
    mkdir -p $nfs_dir
    if [ -z "$standbys" ] ; then
        standbys=0
    fi
    let "online = $active + $standbys + $hotstandbys"

    ERR_LOG="$HEX_SDK cmd ceph -s"
    if [ "$total" != "$online" ] ; then
        ERR_CODE=1
    elif [ $(cubectl node exec -pn -- "mountpoint -- $CEPHFS_STORE_DIR"  | grep "is a mountpoint" | wc -l) -lt $num_nodes ] ; then
        ERR_CODE=2
    elif ! timeout $SRVSTO mount ${vip}:/nfs $nfs_dir 2>/dev/null ; then
        timeout $SRVSTO umount -l $nfs_dir/ 2>/dev/null || true
        ERR_CODE=3
    elif ! touch $nfs_dir/.alive >/dev/null 2>&1 ; then
        ERR_CODE=4
    elif [ $(cubectl node exec -pn -- "systemctl show -p SubState nfs-ganesha" | grep running| wc -l) -lt $num_ctrlnode ] ; then
        ERR_CODE=5
    fi

    rm -f $nfs_dir/.alive
    timeout $SRVSTO umount -l $nfs_dir/ 2>/dev/null || true
    rmdir $nfs_dir

    ERR_MSG+="$stats\n"
    _health_fail_log
}

_health_ceph_mds_auto_repair()
{
    if [ "$ERR_CODE" == "1" ] ; then
        Quiet cubectl node exec -r control "systemctl reset-failed ; systemctl restart ceph-mds@\$HOSTNAME"
    elif [ "$ERR_CODE" == "2" ] ; then
        Quiet cubectl node exec -pn -- $HEX_SDK ceph_mount_cephfs
    elif [ "$ERR_CODE" == "3" -o "$ERR_CODE" == "4" -o "$ERR_CODE" == "5" ] ; then
        Quiet cubectl node exec -r control -p "systemctl restart nfs-ganesha"
    fi
}

health_ceph_mds_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        remote_run $node "systemctl reset-failed"
        remote_run $node $HEX_CFG restart_ceph_mds
    done

    for i in {1..10}; do
        sleep 1
        $CEPH fs status | grep -q active && break
    done

    Quiet cubectl node exec -pn "$HEX_SDK ceph_mount_cephfs"
    Quiet cubectl node exec -r control -pn "systemctl restart nfs-ganesha"
}

health_ceph_osd_report()
{
    _health_report ${FUNCNAME[0]}
}

health_ceph_osd_check()
{
    local stats=$($CEPH status -f json)
    local total=$(echo $stats | jq -r .osdmap.num_osds)
    local uposd=$(echo $stats | jq -r .osdmap.num_up_osds)
    local inosd=$(echo $stats | jq -r .osdmap.num_in_osds)
    if [ "$total" != "$uposd" ] ; then
        ERR_CODE=1
    elif [ "$total" != "$inosd" ] ; then
        ERR_CODE=2
    elif cubectl node exec -pn "$HEX_SDK ceph_osd_list" | sort -t. -n -k2 | egrep -q "warning|fail" ; then
        ERR_CODE=3
        ERR_LOG="dmesg | grep -i -e fail -e error"
    fi

    ERR_MSG+="`echo $stats | jq -r .osdmap`\n"
    _health_fail_log
}

health_ceph_osd_repair()
{
    if [ $($CEPH osd tree down | grep host | awk '{print $4}' | sort -u | wc -l) -gt 0 ] ; then
        readarray osd_array <<<"$($CEPH osd tree | awk '/ down /{print $1}' | sort)"
        declare -p osd_array > /dev/null
        for osd_entry in "${osd_array[@]}" ; do
            local osd=$(echo $osd_entry | head -c -1)
            local host=$(ceph_get_host_by_id $osd)
            remote_run $host "timeout $SRVLTO $HEX_SDK ceph_osd_restart $osd"
        done
    fi
}

health_ceph_rgw_report()
{
    _health_report ${FUNCNAME[0]}
}

health_ceph_rgw_check()
{
    local total=${#CUBE_NODE_CONTROL_HOSTNAMES[@]}
    local online=$($CEPH -s | awk '/rgw:/{print $2}')
    if [ "$total" != "$online" ] ; then
        ERR_CODE=1
        ERR_LOG="$HEX_SDK cmd $CEPH -s"
    fi

    ERR_MSG+="$online/$total rgw are online\n"
    _health_fail_log
}

health_ceph_rgw_repair()
{
    local online=$($CEPH -s -f json | jq -r .servicemap.services.rgw.daemons[] | jq -r .metadata.hostname)

    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! echo "$online" | grep -q $node ; then
            remote_run $node $HEX_CFG restart_ceph_rgw
        fi
    done
}

health_rbd_target_report()
{
    _health_report ${FUNCNAME[0]}
}

health_rbd_target_check()
{
    # FIXME: ceph-iscsi for el9/python3.9 is not yet available (Latest is ceph-iscsi 3.6-2 el8 which depends on python3.6)
    if [[ $(python3 --version) =~ 3.9 ]] ; then
        ERR_CODE=0
    else
        for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
            local osd_count=$($CEPH osd status 2>/dev/nul | grep " $node " | wc -l)
            if [ "$osd_count" != "0" ] ; then
                if ! is_remote_running $node rbd-target-api ; then
                    ERR_CODE=1
                    ERR_MSG+="rbd-target-api on $node is not running.\n"
                elif ! is_remote_running $node rbd-target-gw ; then
                    ERR_CODE=2
                    ERR_MSG+="rbd-target-gw on $node is not running.\n"
                fi
            fi
        done
    fi
    _health_fail_log
}

health_rbd_target_repair()
{
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        local osd_count=$($CEPH osd status 2>/dev/nul | grep " $node " | wc -l)
        if [ "$osd_count" != "0" ] ; then
            if ! is_remote_running $node rbd-target-api ; then
                remote_systemd_restart $node rbd-target-api
            elif ! is_remote_running $node rbd-target-gw ; then
                remote_systemd_restart $node rbd-target-gw
            fi
        fi
    done
}

health_nova_report()
{
    [ "$VERBOSE" != "1" ] || $OPENSTACK compute service list
    _health_report ${FUNCNAME[0]}
}

health_nova_check()
{
    stale_api_check_repair openstack-nova-api 8774 nova-api python3

    local http_stats=$(influx -host $(shared_id) -database monasca -format json -execute "select last(value) from http_status where service = 'compute'" | jq .results[0].series[0].values[0][1])
    local service_stats="$($OPENSTACK compute service list -f value -c Binary -c Host -c Status -c State 2>/dev/null)"
    local scheduler_up=$(echo "$service_stats" | grep scheduler | grep -i enabled | grep -i up | wc -l )
    local scheduler_down=$(echo "$service_stats" | grep scheduler | grep -i enabled | grep -i down | wc -l )
    local conductor_up=$(echo "$service_stats" | grep conductor | grep -i enabled | grep -i up | wc -l )
    local conductor_down=$(echo "$service_stats" | grep conductor | grep -i enabled | grep -i down | wc -l )
    local compute_up=$(echo "$service_stats" | grep compute | grep -v ironic | grep -i enabled | grep -i up | wc -l )
    local compute_down=$(echo "$service_stats" | grep compute | grep -v ironic | grep -i enabled | grep -i down | wc -l )

    if [ "$http_stats" != "0" ] ; then
        ERR_CODE=1
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-nova-api"
    elif [ -z "$service_stats" ] ; then
        ERR_CODE=2
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-nova-api"
    elif [ "$scheduler_up" == "0" -o "$scheduler_down" != "0" ] ; then
        ERR_CODE=3      
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-nova-scheduler"
    elif [ "$conductor_up" == "0" -o "$conductor_down" != "0" ] ; then
        ERR_CODE=4
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-nova-conductor"
    elif [ "$compute_up" == "0" -o "$compute_down" != "0" ] ; then
        ERR_CODE=5
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-nova-compute"
    fi

    ERR_MSG+="$service_stats\n"
    _health_fail_log
}

_health_nova_auto_repair()
{
    if [ "$ERR_CODE" != "0" ] ; then
        readarray entry_array <<<"$(echo -e "$ERR_MSG" | awk '/enabled.*down/{print $1" "$2}' | sort)"
        declare -p entry_array > /dev/null
        for entry in "${entry_array[@]}" ; do
            local srv=$(echo $entry | awk '{print $1}')
            local host=$(echo $entry | awk '{print $2}')
            if [ -n "$host" ] ; then
                remote_systemd_restart $host openstack-$srv
            fi
        done
    fi
}

health_nova_repair()
{
    Quiet -n cubectl node exec -pn $HEX_CFG restart_nova
}

health_ironic_report()
{
    _health_report ${FUNCNAME[0]}
}

health_ironic_check()
{
    source $HEX_TUN $SETTINGS_TXT ironic.enabled
    if [ "$T_ironic_enabled" != "true" ] ; then
        return 0
    else
        ERR_MSG+="`$OPENSTACK baremetal driver list`\n"
    fi

    stale_api_check_repair openstack-ironic-api 6385 ironic-api python3
    stale_api_check_repair openstack-ironic-inspector 5050 ironic-inspecto python3

    local service_stats="$($OPENSTACK compute service list -f value -c Binary -c Host -c Status -c State 2>/dev/null)"
    local ironic_up=$(echo "$service_stats" | grep compute | grep ironic | grep -i enabled | grep -i up | wc -l )
    local ironic_down=$(echo "$service_stats" | grep compute | grep ironic | grep -i enabled | grep -i down | wc -l )
    if [ -z "$service_stats" ] ; then
        ERR_CODE=1
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-nova-compute"
    elif [ "$ironic_up" == "0" -o "$ironic_down" != "0" ] ; then
        ERR_CODE=2
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-nova-compute"
    else
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            if ! is_remote_running $node openstack-ironic-api ; then
                ERR_CODE=3
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-ironic-api"
            elif ! is_remote_running $node openstack-ironic-conductor ; then
                ERR_CODE=4
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-ironic-conductor"
            elif ! is_remote_running $node openstack-ironic-inspector ; then
                ERR_CODE=5
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-ironic-inspector"
            fi
        done
    fi

    ERR_MSG+="$service_stats\n"
    _health_fail_log
}

_health_ironic_auto_repair()
{
    if [ "$ERR_CODE" != "0" ] ; then
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            if ! is_remote_running $node openstack-ironic-api ; then
                remote_systemd_restart $node openstack-ironic-api
            elif ! is_remote_running $node openstack-ironic-conductor ; then
                remote_systemd_restart $node openstack-ironic-conductor
            elif ! is_remote_running $node openstack-ironic-inspector ; then
                remote_systemd_restart $node openstack-ironic-inspector
            fi
        done

        readarray entry_array <<<"$(echo -e "$ERR_MSG" | awk '/ironic.*enabled.*down/{print $1" "$2}' | sort)"
        declare -p entry_array > /dev/null
        for entry in "${entry_array[@]}" ; do
            local srv=$(echo $entry | awk '{print $1}')
            local host=$(echo $entry | awk '{print $2}' | awk -F'-' '{print $1}' | tr -d '\n')
            if [ -n "$host" ] ; then
                remote_systemd_restart $host openstack-$srv
            fi
        done
    fi
}

health_ironic_repair()
{
    Quiet -n cubectl node exec -pn $HEX_CFG restart_ironic
}

health_cyborg_report()
{
    ERR_MSG+="Accelerator:\n"
    ERR_MSG+="`$OPENSTACK accelerator device list 2>/dev/null`\n"
    ERR_MSG+="GPU Resource Provider:\n"
    ERR_MSG+="`$OPENSTACK resource provider list -c uuid -c name --resource PGPU=1 2>/dev/null`\n"
    ERR_MSG+="Accelerator Request:\n"
    ERR_MSG+="`$OPENSTACK accelerator arq list 2>/dev/null`\n"
    ERR_MSG+="Accelerator Device Profile:\n"
    ERR_MSG+="`$OPENSTACK accelerator device profile list 2>/dev/null`\n"
    _health_report ${FUNCNAME[0]}
}

health_cyborg_check()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node cyborg-api ; then
            ERR_MSG+="cyborg-api on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u cyborg-api"
            ERR_CODE=3 && break
        elif ! is_remote_running $node cyborg-conductor ; then
            ERR_MSG+="cyborg-conductor on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u cyborg-conductor"
            ERR_CODE=4 && break
        fi
    done

    for node in "${CUBE_NODE_COMPUTE_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node cyborg-agent ; then
            ERR_MSG+="cyborg-agent on $node is not running\n"
            err_code=5 && break
        fi
    done

    _health_fail_log
}

_health_cyborg_auto_repair()
{
    if [ "$ERR_CODE" != "0" ] ; then
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            if ! is_remote_running $node cyborg-api ; then
                remote_systemd_restart $node cyborg-api
            elif ! is_remote_running $node cyborg-conductor ; then
                remote_systemd_restart $node cyborg-conductor
            fi
        done

        for node in "${CUBE_NODE_COMPUTE_HOSTNAMES[@]}" ; do
            if ! is_remote_running $node cyborg-agent ; then
                remote_systemd_restart $node cyborg-agent
            fi
        done
    fi
}

health_cyborg_repair()
{
    Quiet -n cubectl node exec -pn $HEX_CFG restart_cyborg
}

health_neutron_report()
{
    _health_report ${FUNCNAME[0]}
}

health_neutron_check()
{
    stale_api_check_repair neutron-server 9696 neutron-server server

    local service_stats="$($OPENSTACK network agent list -f value -c Binary -c Alive -c Host 2>/dev/null)"
    local metadata_up=$(echo "$service_stats" | grep neutron-ovn-metadata-agent | grep -i True | wc -l )
    local metadata_down=$(echo "$service_stats" | grep neutron-ovn-metadata-agent | grep -i False | wc -l )
    local vpn_up=$(echo "$service_stats" | grep neutron-ovn-vpn-agent | grep -i True | wc -l )
    local vpn_down=$(echo "$service_stats" | grep neutron-ovn-vpn-agent | grep -i False | wc -l )
    local control_up=$(echo "$service_stats" | grep ovn-controller | grep -i True | wc -l )
    local control_down=$(echo "$service_stats" | grep ovn-controller | grep -i False | wc -l )

    ERR_LOG="journalctl -n $ERR_LOGSIZE -u neutron-server"
    if [ -z "$service_stats" ] ; then
        ERR_CODE=2
    elif [ "$metadata_up" == "0" -o "$metadata_down" != "0" ] ; then
        ERR_CODE=3
    elif [ "$vpn_up" == "0" -o "$vpn_down" != "0" ] ; then
        ERR_CODE=4
    elif [ "$control_up" == "0" -o "$control_down" != "0" ] ; then
        ERR_CODE=5
    fi

    if [ $ERR_CODE -eq 0 ] ; then
        # create a dummy port for e2e test
        net_id=$($OPENSTACK subnet list | awk '/ lb-mgmt-subnet / {print $6}')
        if [ -n "$net_id" ] ; then
            suffix=$(echo $RANDOM | md5sum | head -c 4)
            port_id=$($OPENSTACK port create --project admin --device-owner cube:diag --host=$HOSTNAME -c id -f value --network $net_id diag-$HOSTNAME-$suffix 2>/dev/null)
            if [ -n "$port_id" ] ; then
                $OPENSTACK port delete $port_id
            else
                ERR_CODE=6
            fi
        fi
    fi

    ERR_MSG+="$service_stats\n"
    _health_fail_log
}

_health_neutron_auto_repair()
{
    if [ "$ERR_CODE" != "0" ] ; then
        $OPENSTACK port list -f value -c ID -c Name | grep "diag[-]" | cut -d " " -f1 | xargs -i $OPENSTACK port delete {}
        if [ $ERR_CODE -eq 6 ] ; then
            Quiet -n cubectl node exec -r control -pn -- $HEX_SDK os_neutron_worker_scale
        else
            $HEX_SDK ovn_neutron_db_sync
            readarray entry_array <<<"$(echo -n "$ERR_MSG" | awk '/False/{print $1" "$3}' | sort)"
            declare -p entry_array > /dev/null
            for entry in "${entry_array[@]}" ; do
                local srv=$(echo $entry | awk '{print $2}')
                local host=$(echo $entry | awk '{print $1}')
                if [ -n "$host" ] ; then
                    remote_systemd_restart $host $srv
                fi
            done
        fi
    fi
}

health_neutron_repair()
{
    Quiet -n cubectl node exec -pn $HEX_CFG bootstrap neutron

    $HEX_SDK ovn_neutron_db_sync

    local net_id=$($OPENSTACK subnet list | awk '/ lb-mgmt-subnet / {print $6}')
    if [ -n "$net_id" ] ; then
        $OPENSTACK port delete $($OPENSTACK port list --network $net_id -f value -c ID -c Name 2>/dev/null | grep diag | awk '{print $1}') >/dev/null 2>&1
    fi

    local agent_list=$($OPENSTACK network agent list -f json -c ID -c Alive)
    for i in $(echo $agent_list | jq -r ".[].ID") ; do
        alive=$(echo $agent_list | jq -r ".[] | select(.ID == \"$i\").Alive")
        if [ "x$alive" = "xfalse" ] ; then
            $OPENSTACK network agent delete $i
        fi
    done
}

health_glance_report()
{
    DESCRIPTION+="images: $($OPENSTACK image list -f value -c ID | wc -l )"
    _health_report ${FUNCNAME[0]}
}

health_glance_check()
{
    stale_api_check_repair openstack-glance-api 9292 glance-api python3

    local http_stats=$(influx -host $(shared_id) -database monasca -format json -execute "select last(value) from http_status where service = 'image-service'" | jq .results[0].series[0].values[0][1])
    ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-glance-api"
    if [ "$http_stats" != "0" ] ; then
        ERR_CODE=1
    else
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            if ! is_remote_running $node openstack-glance-api ; then
                ERR_CODE=2
                ERR_MSG+="glance-api on $node is down\n"
            fi
        done
    fi

    _health_fail_log
}

_health_glance_auto_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node openstack-glance-api ; then
            remote_systemd_restart $node openstack-glance-api
        fi
    done
}

health_glance_repair()
{
    Quiet -n cubectl node exec -pn $HEX_CFG restart_glance
}

health_cinder_report()
{
    [ "$VERBOSE" != "1" ] || $OPENSTACK volume service list
    _health_report ${FUNCNAME[0]}
}

health_cinder_check()
{
    stale_api_check_repair openstack-cinder-api 8776 cinder-api python3

    local http_stats=$(influx -host $(shared_id) -database monasca -format json -execute "select last(value) from http_status where service = 'block-storage'" | jq .results[0].series[0].values[0][1])
    local service_stats="$($OPENSTACK volume service list -f value -c Binary -c Status -c State 2>/dev/null)"
    local scheduler_up=$(echo "$service_stats" | grep scheduler | grep -i enabled | grep -i up | wc -l )
    local scheduler_down=$(echo "$service_stats" | grep scheduler | grep -i enabled | grep -i down | wc -l )
    local volume_up=$(echo "$service_stats" | grep volume | grep -i enabled | grep -i up | wc -l )
    local volume_down=$(echo "$service_stats" | grep volume | grep -i enabled | grep -i down | wc -l )
    local backup_up=$(echo "$service_stats" | grep backup | grep -i enabled | grep -i up | wc -l )
    local backup_down=$(echo "$service_stats" | grep backup | grep -i enabled | grep -i down | wc -l )

    if [ "$http_stats" != "0" ] ; then
        ERR_CODE=1
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-cinder-volume"
    elif [ -z "$service_stats" ] ; then
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-cinder-api"
        ERR_CODE=2
    elif [ "$scheduler_up" == "0" -o "$scheduler_down" != "0" ] ; then
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-cinder-scheduler"
        ERR_CODE=3
    elif [ "$volume_up" == "0" -o "$volume_down" != "0" ] ; then
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-cinder-volume"
        ERR_CODE=4
    elif [ "$backup_up" == "0" -o "$backup_down" != "0" ] ; then
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-cinder-backup"
        ERR_CODE=5
    fi

    ERR_MSG+="$service_stats\n"
    _health_fail_log
}

_health_cinder_auto_repair()
{
    readarray entry_array <<<"$(echo "$ERR_MSG" | awk '/enabled.*down/{print $1" "$2}' | sort)"
    declare -p entry_array > /dev/null
    for entry in "${entry_array[@]}" ; do
        local srv=$(echo $entry | awk '{print $1}')
        local host=$(echo $entry | awk '{print $2}' | tr -d '\n')
        if [ "$srv" == "cinder-volume" ] ; then
            if [ $(cubectl node list -r control | wc -l) -eq 1 ] ; then
                systemctl restart openstack-$srv
            else
                Quiet -n pcs resource cleanup cinder-volume
                Quiet -n pcs resource enable cinder-volume
                Quiet -n pcs resource restart cinder-volume
            fi
        else
            if [ -n "$host" -a -n "$srv" ] ; then
                remote_systemd_restart $host openstack-$srv
            fi
        fi
    done
}

health_cinder_repair()
{
    Quiet -n cubectl node exec -pn $HEX_CFG restart_cinder
}

health_manila_report()
{
    _health_report ${FUNCNAME[0]}
}

health_manila_check()
{
    stale_api_check_repair openstack-manila-api 8786 manila-api python3
    local service_stats="$($MANILA service-list 2>/dev/null)"
    local scheduler_up=$(echo "$service_stats" | grep manila-scheduler | grep -i enabled | grep -i up | wc -l )
    local scheduler_down=$(echo "$service_stats" | grep manila-scheduler | grep -i enabled | grep -i down | wc -l )
    local share_up=$(echo "$service_stats" | grep manila-share | grep -i enabled | grep -i up | wc -l )
    local share_down=$(echo "$service_stats" | grep manila-share | grep -i enabled | grep -i down | wc -l )
    local share_total=$(cubectl node list -r compute -j | jq -r .[].hostname | head -3 | wc -l)

    if [ -z "$service_stats" ] ; then
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-manila-api"
        ERR_CODE=2
    elif [ "$scheduler_up" == "0" -o "$scheduler_down" != "0" ] ; then
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-manila-scheduler"
        ERR_CODE=3
    elif [ "$share_up" != "$share_total" -o "$share_down" != "0" ] ; then
        ERR_CODE=4
    fi

    ERR_MSG+="$service_stats\n"
    _health_fail_log
}

_health_manila_auto_repair()
{
    if [ $($OPENSTACK network list | grep manila_service_network | wc -l) -gt 1 ] ; then
        for NID in $($OPENSTACK network list -f value -c ID -c Name | grep manila_service_network | cut -d' ' -f1) ; do
            $OPENSTACK port list --network $NID -f value -c ID | xargs -i $OPENSTACK port delete {}
            $OPENSTACK network delete $NID
        done
    fi
    readarray entry_array <<<"$(echo "$ERR_MSG" | awk '/enabled.*down/{print $4" "$6}' | sort)"
    declare -p entry_array > /dev/null
    for entry in "${entry_array[@]}" ; do
        local srv=$(echo $entry | awk '{print $1}')
        local host=$(echo $entry | awk '{print $2}' | awk -F'@' '{print $1}' | tr -d '\n')
        if [ -n "$host" ] ; then
            if [ -n "$srv" -a "$srv" == "manila-share" ] ; then
                $HEX_SDK os_manila_service_remove $host $srv
            fi
            remote_systemd_restart $host openstack-$srv
        fi
    done
    for node in "${CUBE_NODE_COMPUTE_HOSTNAMES[@]}" ; do
        if [ -n "$node" ] ; then
            remote_systemd_restart $node openstack-manila-share
        fi
    done
}

health_manila_repair()
{
    Quiet -n cubectl node exec -pn $HEX_CFG restart_manila
}

health_swift_report()
{
    _health_report ${FUNCNAME[0]}
}

health_swift_check()
{
    local service_stats="$($OPENSTACK object store account show -f json 2>/dev/null)"
    local object_count=$(echo "$service_stats" | jq -r .Objects)

    ERR_LOG="netstat -tunpl | grep 8888"
    $CURL -sf http://$HOSTNAME:8888 >/dev/null
    if [ $? -ne 0 ] ; then
        ERR_CODE=1
    elif [ -z "$service_stats" ] ; then
        ERR_CODE=2
    elif [ ! $object_count -ge 0 ] ; then
        ERR_CODE=3
    fi

    local containers=$(echo "$service_stats" | jq -r .Containers)
    local objects=$(echo "$service_stats" | jq -r .Objects)
    DESCRIPTION+="tenant: admin, "
    DESCRIPTION+="containers: ${containers}, "
    DESCRIPTION+="objects: ${objects}"
    ERR_MSG+="$service_stats\n"
    _health_fail_log
}

health_heat_report()
{
    _health_report ${FUNCNAME[0]}
}

health_heat_check()
{
    stale_api_check_repair openstack-heat-api 8004 heat-api python3
    stale_api_check_repair openstack-heat-api-cfn 8000 heat-api-cfn python3

    local http_stats=$(influx -host $(shared_id) -database monasca -format json -execute "select last(value) from http_status where service = 'orchestration'" | jq .results[0].series[0].values[0][1])
    local service_stats="$($OPENSTACK orchestration service list -f value -c Hostname -c Binary -c Status | sort | uniq 2>/dev/null)"
    local engine_up=$(echo "$service_stats" | grep -i up | wc -l )
    local engine_down=$(echo "$service_stats" | grep -i down | wc -l )

    if [ "$http_stats" != "0" ] ; then
        ERR_CODE=1
    elif [ -z "$service_stats" ] ; then
        ERR_CODE=2
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-heat-api"
    elif [ "$engine_up" == "0" ] ; then
        ERR_CODE=3
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-heat-engine"
    fi

    DESCRIPTION+="engine up/down: ${engine_up}/${engine_down}"
    ERR_MSG+="$service_stats\n"
    _health_fail_log
}

_health_heat_auto_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node openstack-heat-api ; then
            remote_systemd_restart $node openstack-heat-api
        elif ! is_remote_running $node openstack-heat-api-cfn ; then
            remote_systemd_restart $node openstack-heat-api-cfn
        fi
    done

    readarray entry_array <<<"$(echo "$ERR_MSG" | awk '/down/{print $1" "$2}' | sort)"
    declare -p entry_array > /dev/null
    for entry in "${entry_array[@]}" ; do
        local srv=$(echo $entry | awk '{print $2}')
        local host=$(echo $entry | awk '{print $1}')
        if [ -n "$host" ] ; then
            remote_systemd_restart $host openstack-$srv
        fi
    done
}

health_heat_repair()
{
    Quiet -n cubectl node exec -r control -pn $HEX_CFG restart_heat
}

health_octavia_report()
{
    _health_report ${FUNCNAME[0]}
}

health_octavia_check()
{
    stale_api_check_repair octavia-api 9876 octavia-api python3

    local http_stats=$(influx -host $(shared_id) -database monasca -format json -execute "select last(value) from http_status where service = 'octavia'" | jq .results[0].series[0].values[0][1])
    if [ "$http_stats" != "0" ] ; then
        ERR_CODE=1
    else
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            if ! is_remote_running $node octavia-api ; then
                ERR_MSG+="octavia-api on $node is not running\n"
                ERR_CODE=3
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u octavia-api"
            elif ! is_remote_running $node octavia-housekeeping ; then
                ERR_MSG+="octavia-housekeeping on $node is not running\n"
                ERR_CODE=4
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u octavia-housekeeping"
            fi
        done
        ERR_LOG="ip addr show"
        for node in "${CUBE_NODE_COMPUTE_HOSTNAMES[@]}" ; do
            if ! remote_run $node ovs-vsctl port-to-br octavia-hm0 >/dev/null 2>&1 ; then
                ERR_MSG+="no octavia-hm0 ovn port found on $node\n"
                ERR_CODE=5
            elif remote_run $node ip link show octavia-hm0 | grep -q DOWN ; then
                ERR_MSG+="no link octavia-hm0 found on $node\n"
                ERR_CODE=6
            elif ! remote_run $node route -n | grep -q octavia-hm0 ; then
                ERR_MSG+="no route from octavia-hm0 found on $node\n"
                ERR_CODE=7
            elif ! is_remote_running $node octavia-worker ; then
                ERR_MSG+="octavia-worker on $node is not running\n"
                ERR_CODE=8
            elif ! is_remote_running $node octavia-health-manager ; then
                ERR_MSG+="octavia-health-manager on $node is not running\n"
                ERR_CODE=9
            fi
        done
    fi

    _health_fail_log
}

_health_octavia_auto_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node octavia-api ; then
            remote_systemd_restart $node octavia-api
        elif ! is_remote_running $node octavia-housekeeping ; then
            remote_systemd_restart $node octavia-housekeeping
        fi
    done

    for node in "${CUBE_NODE_COMPUTE_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node octavia-worker ; then
            remote_systemd_restart $node octavia-worker
        elif ! is_remote_running $node octavia-health-manager ; then
            remote_systemd_restart $node octavia-health-manager
        fi
    done
}

health_octavia_repair()
{
    # master node should run first before other nodes
    local master=$CUBE_NODE_CONTROL_HOSTNAMES
    Quiet -n remote_run $master $HEX_CFG reinit_octavia
    Quiet -n cubectl node exec -pn $HEX_CFG reinit_octavia
}

health_designate_report()
{
    [ "$VERBOSE" != "1" ] || $OPENSTACK dns service list
    _health_report ${FUNCNAME[0]}
}

health_designate_check()
{
    stale_api_check_repair designate-api 9001 designate-api python3

    local http_stats=$(influx -host $(shared_id) -database monasca -format json -execute "select last(value) from http_status where service = 'dns'" | jq .results[0].series[0].values[0][1])
    local service_stats="$($OPENSTACK dns service list -f value -c hostname -c service_name -c status 2>/dev/null)"
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

    if [ "$http_stats" != "0" ] ; then
        ERR_CODE=1
    elif [ -z "$service_stats" ] ; then
        ERR_CODE=2
    elif [ "$api_up" == "0" -o "$api_down" != "0" ] ; then
        ERR_CODE=9
    elif [ "$central_up" == "0" -o "$central_down" != "0" ] ; then
        ERR_CODE=10
    elif [ "$worker_up" == "0" -o "$worker_down" != "0" ] ; then
        ERR_CODE=11
    elif [ "$producer_up" == "0" -o "$producer_down" != "0" ] ; then
        ERR_CODE=12
    elif [ "$mdns_up" == "0" -o "$mdns_down" != "0" ] ; then
        ERR_CODE=13
    else
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            if ! is_remote_running $node designate-api ; then
                ERR_CODE=3
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u designate-api"
            elif ! is_remote_running $node designate-central ; then
                ERR_CODE=4
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u designate-central"
            elif ! is_remote_running $node designate-worker ; then
                ERR_CODE=5
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u designate-worker"
            elif ! is_remote_running $node designate-producer ; then
                ERR_CODE=6
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u designate-producer"
            elif ! is_remote_running $node designate-mdns ; then
                ERR_CODE=7
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u designate-mdns"
            elif ! is_remote_running $node named ; then
                ERR_CODE=8
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u named"
            fi
        done
    fi

    ERR_MSG+="$service_stats\n"
    _health_fail_log
}

_health_designate_auto_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node designate-api ; then
            remote_systemd_restart $node designate-api
        elif ! is_remote_running $node designate-central ; then
            remote_systemd_restart $node designate-central
        elif ! is_remote_running $node designate-worker ; then
            remote_systemd_restart $node designate-worker
        elif ! is_remote_running $node designate-producer ; then
            remote_systemd_restart $node designate-producer
        elif ! is_remote_running $node designate-mdns ; then
            remote_systemd_restart $node designate-mdns
        elif ! is_remote_running $node named ; then
            local master=$(cubectl node list -r control -j | jq -r .[].hostname | head -n 1)
            remote_run $master /usr/local/bin/cubectl node rsync -r control /etc/designate/rndc.key
            remote_systemd_restart $node named
        fi
    done

    readarray entry_array <<<"$(echo "$ERR_MSG" | awk '/DOWN/{print $1" "$2}' | sort)"
    declare -p entry_array > /dev/null
    for entry in "${entry_array[@]}" ; do
        local srv=$(echo $entry | awk '{print $2}')
        local host=$(echo $entry | awk '{print $1}')
        if [ -n "$host" ] ; then
            remote_systemd_restart $host designate-$srv
        fi
    done
}

health_designate_repair()
{
    local master=$CUBE_NODE_CONTROL_HOSTNAMES
    Quiet -n remote_run $master /usr/local/bin/cubectl node rsync -r control /etc/designate/rndc.key
    Quiet -n cubectl node exec -r control -pn $HEX_CFG restart_designate
}

health_masakari_report()
{
    _health_report ${FUNCNAME[0]}
}

health_masakari_check()
{
    stale_api_check_repair masakari-api 15868 masakari-api python3

    $CURL -sf http://$HOSTNAME:15868 >/dev/null
    if [ $? -ne 0 ] ; then
        ERR_CODE=1
    else
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            if ! is_remote_running $node masakari-api ; then
                ERR_MSG+="masakari-api on $node is not running\n"
                ERR_CODE=3
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u masakari-api"
            elif ! is_remote_running $node masakari-engine ; then
                ERR_MSG+="masakari-engine on $node is not running\n"
                ERR_CODE=4
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u masakari-engine"
            fi
        done
        for node in "${CUBE_NODE_COMPUTE_HOSTNAMES[@]}" ; do
            if ! is_remote_running $node masakari-processmonitor ; then
                ERR_MSG+="masakari-processmonitor on $node is not running\n"
                ERR_CODE=5
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u masakari-processmonitor"
            elif ! is_remote_running $node masakari-hostmonitor ; then
                ERR_MSG+="masakari-hostmonitor on $node is not running\n"
                ERR_CODE=6
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u masakari-hostmonitor"
            elif ! is_remote_running $node masakari-instancemonitor ; then
                ERR_MSG+="masakari-instancemonitor on $node is not running\n"
                ERR_CODE=7
                ERR_LOG="journalctl -n $ERR_LOGSIZE -u masakari-instancemonitor"
            fi
        done
    fi

    _health_fail_log
}

_health_masakari_auto_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node masakari-api ; then
            remote_systemd_restart $node masakari-api
        elif ! is_remote_running $node masakari-engine ; then
            remote_systemd_restart $node masakari-engine
        fi
    done
    for node in "${CUBE_NODE_COMPUTE_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node masakari-processmonitor ; then
            remote_systemd_restart $node masakari-processmonitor
        elif ! is_remote_running $node masakari-hostmonitor ; then
            remote_systemd_restart $node masakari-hostmonitor
        elif ! is_remote_running $node masakari-instancemonitor ; then
            remote_systemd_restart $node masakari-instancemonitor
        fi
    done
}

health_masakari_repair()
{
    Quiet -n cubectl node exec -pn $HEX_CFG restart_masakari
}

health_monasca_report()
{
    _health_report ${FUNCNAME[0]}
}

health_monasca_check()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node monasca-persister ; then
            ERR_MSG+="monasca-persister on $node is not running\n"
            ERR_CODE=3
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u monasca-persister"
        fi
    done
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node monasca-collector ; then
            ERR_MSG+="monasca-collector on $node is not running\n"
            ERR_CODE=4
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u monasca-collector"
        elif ! is_remote_running $node monasca-forwarder ; then
            ERR_MSG+="monasca-forwarder on $node is not running\n"
            ERR_CODE=5
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u monasca-forwarder"
        elif ! is_remote_running $node monasca-statsd ; then
            ERR_MSG+="monasca-statsd on $node is not running\n"
            ERR_CODE=6
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u monasca-statsd"
        fi
    done

    _health_fail_log
}

_health_monasca_auto_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node monasca-persister ; then
            remote_systemd_restart $node monasca-persister
        fi
    done
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node monasca-collector ; then
            remote_systemd_restart $node monasca-collector
        elif ! is_remote_running $node monasca-forwarder ; then
            remote_systemd_restart $node monasca-forwarder
        elif ! is_remote_running $node monasca-statsd ; then
            remote_systemd_restart $node monasca-statsd
        fi
    done
}

health_monasca_repair()
{
    Quiet -n cubectl node exec -pn $HEX_CFG restart_monasca
}

health_senlin_report()
{
    [ "$VERBOSE" != "1" ] || $OPENSTACK cluster service list
    _health_report ${FUNCNAME[0]}
}

health_senlin_check()
{
    stale_api_check_repair openstack-senlin-api 8777 senlin-api python3

    local service_stats="$($OPENSTACK cluster service list -f value -c host -c binary -c status -c state 2>/dev/null)"
    local engine_up=$(echo "$service_stats" | grep senlin-engine | grep -i enabled | grep -i up | wc -l )
    local engine_down=$(echo "$service_stats" | grep senlin-engine | grep -i enabled | grep -i down | wc -l )
    local conductor_up=$(echo "$service_stats" | grep senlin-conductor | grep -i enabled | grep -i up | wc -l )
    local conductor_down=$(echo "$service_stats" | grep senlin-conductor | grep -i enabled | grep -i down | wc -l )
    local hmgr_up=$(echo "$service_stats" | grep senlin-health-manager | grep -i enabled | grep -i up | wc -l )
    local hmgr_down=$(echo "$service_stats" | grep senlin-health-manager | grep -i enabled | grep -i down | wc -l )

    if [ -z "$service_stats" ] ; then
        ERR_CODE=2
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-senlin-api"
    elif [ "$engine_up" == "0" -o "$engine_down" != "0" ] ; then
        ERR_CODE=3
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-senlin-engine"
    elif [ "$conductor_up" == "0" -o "$conductor_down" != "0" ] ; then
        ERR_CODE=4
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-senlin-conductor"
    elif [ "$hmgr_up" == "0" -o "$hmgr_down" != "0" ] ; then
        ERR_CODE=5
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-senlin-health-manager"
    fi

    ERR_MSG+="$service_stats\n"
    _health_fail_log
}

_health_senlin_auto_repair()
{
    readarray entry_array <<<"$(echo "$ERR_MSG" | awk '/enabled.*down/{print $1" "$2}' | sort)"
    declare -p entry_array > /dev/null
    for entry in "${entry_array[@]}" ; do
        local srv=$(echo $entry | awk '{print $1}')
        local host=$(echo $entry | awk '{print $2}')
        if [ -n "$host" ] ; then
            remote_systemd_restart $host openstack-$srv
        fi
    done
}

health_senlin_repair()
{
    Quiet -n cubectl node exec -r control -p $HEX_CFG restart_senlin
}

health_watcher_report()
{
    [ "$VERBOSE" != "1" ] || $OPENSTACK optimize service list
    _health_report ${FUNCNAME[0]}
}

health_watcher_check()
{
    stale_api_check_repair openstack-watcher-api 9322 watcher-api python3

    local service_stats="$($OPENSTACK optimize service list -f value -c Name -c Host -c Status 2>/dev/null)"
    local applier_up=$(echo "$service_stats" | grep watcher-applier | grep -i ACTIVE | wc -l )
    local applier_down=$(echo "$service_stats" | grep watcher-applier | grep -i FAILED | wc -l )
    local engine_up=$(echo "$service_stats" | grep watcher-decision-engine | grep -i ACTIVE | wc -l )
    local engine_down=$(echo "$service_stats" | grep watcher-decision-engine | grep -i FAILED | wc -l )

    if [ -z "$service_stats" ] ; then
        ERR_CODE=2
    elif [ "$applier_up" == "0" -o "$applier_down" != "0" ] ; then
        ERR_CODE=3
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-watcher-applier"
    elif [ "$engine_up" == "0" -o "$engine_down" != "0" ] ; then
        ERR_CODE=4
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u openstack-watcher-decision-engine"
    fi

    ERR_MSG+="$service_stats\n"
    _health_fail_log
}

_health_watcher_auto_repair()
{
    readarray entry_array <<<"$(echo "$ERR_MSG" | awk '/FAILED/{print $1" "$2}' | sort)"
    declare -p entry_array > /dev/null
    for entry in "${entry_array[@]}" ; do
        local srv=$(echo $entry | awk '{print $1}')
        local host=$(echo $entry | awk '{print $2}')
        if [ -n "$host" ] ; then
            remote_systemd_restart $host openstack-$srv
        fi
    done
}

health_watcher_repair()
{
    Quiet -n cubectl node exec -r control -p $HEX_CFG restart_watcher
}

health_k3s_report()
{
    _health_report ${FUNCNAME[0]}
}

health_k3s_check()
{
    if ! cubectl config check k3s 2>/dev/null ; then
        ERR_CODE=1
        ERR_LOG="journalctl -n $ERR_LOGSIZE -u k3s"
    fi

    ERR_MSG+="`cubectl config status k3s`\n"
    _health_fail_log
}

health_k3s_repair()
{
    Quiet -n cubectl config repair k3s
}

health_rancher_report()
{
    _health_report ${FUNCNAME[0]}
}

health_rancher_check()
{
    T_rancher_enabled=$(grep rancher.enabled $SETTINGS_TXT | tail -1 | awk -F'= ' '{print $2}' | tr -d '\n')
    if [ "$T_rancher_enabled" == "false" ] ; then
        return 0
    fi

    if ! cubectl config check rancher 2>/dev/null ; then
        ERR_CODE=1
    fi

    ERR_MSG+="`cubectl config status rancher`\n"
    _health_fail_log
}

health_rancher_repair()
{
    Quiet -n cubectl config repair rancher
}

# purge existing rancher data (USE WITH CAUTIONS)
health_rancher_rebuild()
{
    Quiet -n cubectl node exec cubectl config reset --hard rancher k3s
    Quiet -n cubectl node exec cubectl config commit k3s rancher
}

health_opensearch_report()
{
    _health_report ${FUNCNAME[0]}
}

health_opensearch_check()
{
    ERR_LOG="journalctl -n $ERR_LOGSIZE -u opensearch"
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node opensearch ; then
            err_code=1
            ERR_MSG+="opensearch on $node is not running\n"
        fi
    done
    local node_total=${#CUBE_NODE_CONTROL_HOSTNAMES[@]}
    local stats=$($CURL -q http://localhost:9200/_cluster/health 2>/dev/null)
    local status=$(echo $stats | jq -r .status)
    local online=$(echo $stats | jq -r .number_of_nodes)

    if [ "$node_total" != "$online" ] ; then
        ERR_CODE=2
    elif [ "$status" != "green" ] ; then
        ERR_CODE=3
    fi

    ERR_MSG+="$stats\n"
    _health_fail_log
}

health_opensearch_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        remote_systemd_restart $node opensearch
    done
}


health_zookeeper_report()
{
    _health_report ${FUNCNAME[0]}
}

health_zookeeper_check()
{
    local node_total=$(cubectl node list -r control | wc -l)

    ERR_LOG="journalctl -n $ERR_LOGSIZE -u zookeeper"
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node zookeeper ; then
            ERR_CODE=1
            ERR_MSG+="zookeeper on $node is not running\n"
        fi
        local online=$(echo dump | nc $node 2181 | grep brokers | wc -l)
        if [ "$node_total" != "$online" ] ; then
            ERR_CODE=2
            ERR_MSG+="$online/$node_total brokers are online\n"
        fi
    done

    _health_fail_log
}

health_zookeeper_repair()
{
    Quiet -n $HEX_SDK _health_datapipe_deep_repair
}

health_kafka_report()
{
    _health_report ${FUNCNAME[0]}
}

health_kafka_check()
{
    ERR_LOG="journalctl -n $ERR_LOGSIZE -u kafka"
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node kafka ; then
            ERR_CODE=1
            ERR_MSG+="kafka on $node is not running\n"
        fi
    done

    # check the last line of telegraf log
    if journalctl -u telegraf -n 1 | grep -q "E\!.*Failed.*telegraf.*metrics" ; then
        ERR_CODE=2
        ERR_MSG+="kafka fails to get sys/host metrics\n"
    fi

    # check the last 5 minutes from monasca persister log
    if ! awk -v dt="$(date '+%Y-%m-%d %T' -d '-5 minutes')" -F, '$1 > dt' /var/log/monasca/persister.log | grep -q "Processed .* messages from topic 'metrics'" ; then
        ERR_CODE=3
        ERR_MSG+="kafka fails to get instance metrics\n"
    fi

    # check the last 3 seconds from logstash log
    if awk -v dt="$(date '+%Y-%m-%dT%H:%M:%S' -d '3 second ago')" -F'[[,]' '$2 > dt' /var/log/logstash/logstash.log | grep -q "NOT_LEADER_OR_FOLLOWER" ; then
        ERR_CODE=4
        ERR_MSG+="kafka queues has no leader\n"
    fi

    if awk -v dt="$(date '+%Y-%m-%dT%H:%M:%S' -d '3 second ago')" -F'[[,]' '$2 > dt' /var/log/logstash/logstash.log | grep -q "NOT_COORDINATOR" ; then
        ERR_CODE=5
        ERR_MSG+="kafka queues has no coordinator\n"
    fi

    local queue_num=$($HEX_SDK kafka_stats | grep "PartitionCount: 6" | wc -l)
    # the six most important queues: telegraf-metrics, telegraf-hc-metrics, metrics, logs, transformed-logs, alarms
    if [ $queue_num -lt 6 ] ; then
        ERR_CODE=6
        ERR_MSG+="kafka has no built-in queues\n"
    fi

    _OVERRIDE_MAX_ERR=18 _health_fail_log
}

_health_kafka_auto_repair()
{
    if [ "$ERR_CODE" == "2" ] ; then
        if journalctl -u telegraf -n 1 | grep -q "E\!.*Failed.*telegraf-metrics" ; then
            $HEX_CFG recreate_kafka_topic "telegraf-metrics"
        fi
        if journalctl -u telegraf -n 1 | grep -q "E\!.*Failed.*telegraf-hc-metrics" ; then
            $HEX_CFG recreate_kafka_topic "telegraf-hc-metrics"
        fi
        if journalctl -u telegraf -n 1 | grep -q "E\!.*Failed.*telegraf-events-metrics" ; then
            $HEX_CFG recreate_kafka_topic "telegraf-events-metrics"
        fi
    elif [ "$ERR_CODE" == "3" ] ; then
        $HEX_CFG recreate_kafka_topic "metrics"
        Quiet -n cubectl node -r control exec -pn systemctl restart monasca-persister
    elif [ "$ERR_CODE" == "4" ] ; then
        $HEX_CFG recreate_kafka_topic "transformed-logs"
    elif [ "$ERR_CODE" == "5" ] ; then
        $HEX_CFG recreate_kafka_topic "__consumer_offsets"
    elif [ "$ERR_CODE" == "6" ] ; then
        $HEX_CFG update_kafka_topics
    fi
}

health_kafka_repair()
{
    Quiet -n _health_datapipe_deep_repair
    # reset error count to bring back auto_repair()
    rm -f /tmp/health_kafka_error.count
}

health_telegraf_report()
{
    _health_report ${FUNCNAME[0]}
}

health_telegraf_check()
{
    ERR_LOG="journalctl -n $ERR_LOGSIZE -u telegraf"
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        if ! ssh root@$node ps ax 2>/dev/null | grep -v grep | grep -q /usr/bin/telegraf ; then
            ERR_CODE=1
            ERR_MSG+="telegraf on $node is not running\n"
        fi
    done

    _health_fail_log
}

health_telegraf_repair()
{
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        if ! ssh root@$node ps ax 2>/dev/null | grep -v grep | grep -q /usr/bin/telegraf ; then
            remote_systemd_restart $node telegraf
        fi
    done
}

health_influxdb_report()
{
    _health_report ${FUNCNAME[0]}
}

health_influxdb_check()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if remote_run $node $HEX_SDK is_moderator_node >/dev/null 2>&1 ; then
            continue
        fi
        if ! is_remote_running $node influxdb ; then
            ERR_CODE=1
            ERR_MSG+="influxdb on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u influxdb"
        fi
        $CURL -sf http://$node:8086 >/dev/null
        if [ $? -eq 7 ] ; then
            ERR_CODE=2
            ERR_MSG+="influxdb on $node doesn't respond\n"
            ERR_LOG="netstat -tunpl | grep 8086"
        fi
    done

    _health_fail_log
}

health_influxdb_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if remote_run $node $HEX_SDK is_moderator_node >/dev/null 2>&1 ; then
            continue
        fi
        if ! is_remote_running $node influxdb ; then
            remote_systemd_restart $node influxdb
        fi
        $CURL -sf http://$node:8086 >/dev/null
        if [ $? -eq 7 ] ; then
            remote_systemd_restart $node influxdb
        fi
    done
}


health_kapacitor_report()
{
    _health_report ${FUNCNAME[0]}
}

health_kapacitor_check()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! ssh root@$node ps ax 2>/dev/null | grep -v grep | grep -q /usr/bin/kapacitord ; then
            ERR_CODE=1
            ERR_MSG+="kapacitor on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u kapacitor"
        fi
        $CURL -sf http://$node:9092 >/dev/null
        if [ $? -eq 7 ] ; then
            ERR_CODE=2
            ERR_MSG+="kapacitor on $node doesn't respond\n"
            ERR_LOG="netstat -tunpl | grep 8086"
        fi
    done

    _health_fail_log
}

health_kapacitor_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! ssh root@$node ps ax 2>/dev/null | grep -v grep | grep -q /usr/bin/kapacitord ; then
            remote_systemd_restart $node kapacitor
        fi
        $CURL -sf http://$node:9092 >/dev/null
        if [ $? -eq 7 ] ; then
            remote_systemd_restart $node kapacitor
        fi
    done
}

health_grafana_report()
{
    _health_report ${FUNCNAME[0]}
}

health_grafana_check()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node grafana-server ; then
            ERR_CODE=1
            ERR_MSG+="grafana on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u grafana-server"
        fi
        $CURL -sf http://$node:3000 >/dev/null
        if [ $? -eq 7 ] ; then
            ERR_CODE=2
            ERR_MSG+="grafana on $node doesn't respond\n"
            ERR_LOG="netstat -tunpl | grep 3000"
        fi
    done

    _health_fail_log
}

health_grafana_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node grafana-server ; then
            remote_systemd_restart $node grafana-server
        fi
        $CURL -sf http://$node:3000 >/dev/null
        if [ $? -eq 7 ] ; then
            remote_systemd_restart $node grafana-server
        fi
    done
}


health_filebeat_report()
{
    _health_report ${FUNCNAME[0]}
}

health_filebeat_check()
{
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node filebeat ; then
            ERR_CODE=1
            ERR_MSG+="filebeat on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u filebeat"
        fi
    done

    _health_fail_log
}

health_filebeat_repair()
{
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node filebeat ; then
            remote_systemd_restart $node filebeat
        fi
    done
}

health_auditbeat_report()
{
    _health_report ${FUNCNAME[0]}
}

health_auditbeat_check()
{
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node auditbeat ; then
            ERR_CODE=1
            ERR_MSG+="auditbeat on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u auditbeat"
        fi
    done

    _health_fail_log
}

health_auditbeat_repair()
{
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node auditbeat ; then
            remote_systemd_restart $node auditbeat
        fi
    done
}


health_logstash_report()
{
    _health_report ${FUNCNAME[0]}
}

health_logstash_check()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if cubectl node list -r control | grep "^${ctrl}," | grep -q moderator ; then
            continue
        fi
        if ! is_remote_running $node logstash ; then
            ERR_CODE=1
            ERR_MSG+="logstash on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u logstash"
        fi
    done

    _health_fail_log
}

health_logstash_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if cubectl node list -r control | grep "^${ctrl}," | grep -q moderator ; then
            continue
        fi
        if ! is_remote_running $node logstash ; then
            remote_systemd_restart $node logstash
        fi
    done
}

health_opensearch-dashboards_report()
{
    _health_report ${FUNCNAME[0]}
}

health_opensearch-dashboards_check()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node opensearch-dashboards ; then
            ERR_CODE=1
            ERR_MSG+="opensearch-dashboards on $node is not running\n"
            ERR_LOG="journalctl -n $ERR_LOGSIZE -u opensearch-dashboards"
        fi
        $CURL -sf http://$node:5601 >/dev/null
        if [ $? -eq 7 ] ; then
            ERR_CODE=2
            ERR_MSG+="opensearch-dashboards on $node doesn't respond\n"
            ERR_LOG="netstat -tunpl | grep 5601"
        fi
    done

    _health_fail_log
}

health_opensearch-dashboards_repair()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if ! is_remote_running $node opensearch-dashboards ; then
            remote_systemd_restart $node opensearch-dashboards
        fi
        $CURL -sf http://$node:5601 >/dev/null
        if [ $? -eq 7 ] ; then
            remote_systemd_restart $node opensearch-dashboards
        fi
    done
}

_health_neutron_deep_repair()
{
    # OVN DBs location: non-HA -> /var/lib/ovn/, HA -> /etc/ovn/
    Quiet -n cubectl node -r control exec -pn -- rm -f /etc/ovn/ovnnb_db.db /etc/ovn/ovnsb_db.db /var/lib/ovn/ovnnb_db.db /var/lib/ovn/ovnsb_db.db
    Quiet -n cubectl node exec -pn -- rm -f /etc/openvswitch/conf.db
    Quiet -n $HEX_SDK health_neutron_repair
}

_health_datapipe_deep_repair()
{
    Quiet -n cubectl node -r control exec -pn systemctl stop zookeeper kafka logstash kapacitor influxdb monasca-forwarder monasca-persister telegraf
    Quiet -n sleep 10
    Quiet -n cubectl node -r control exec -pn rm -rf /tmp/zookeeper/* /var/lib/kafka/* /var/lib/logstash/*

    Quiet -n cubectl node -r control exec -pn systemctl stop zookeeper kafka logstash kapacitor influxdb monasca-forwarder monasca-persister telegraf
    Quiet -n sleep 10
    Quiet -n cubectl node -r control exec -pn rm -rf /tmp/zookeeper/* /var/lib/kafka/* /var/lib/logstash/*

    Quiet -n cubectl node -r control exec -pn $HEX_CFG bootstrap kafka
    Quiet -n cubectl node -r control exec -pn $HEX_CFG bootstrap logstash
    Quiet -n cubectl node -r control exec -pn $HEX_CFG bootstrap kapacitor
    Quiet -n $HEX_CFG update_kafka_topics
    Quiet -n cubectl node -r control exec -pn systemctl reset-failed
    Quiet -n cubectl node -r control exec -pn systemctl start kapacitor influxdb monasca-forwarder monasca-persister telegraf
    Quiet -n cubectl node -r control exec -pn systemctl restart httpd
}

health_hypervisor_check()
{
    [ `cubectl node exec -pn "[ -e $CUBE_DONE ] && echo 0" | wc -l` -eq ${#CUBE_NODE_LIST_HOSTNAMES[@]} ] || return 1
    local max=10
    for node in "${CUBE_NODE_COMPUTE_HOSTNAMES[@]}" ; do
        local srv=
        if ! is_remote_running $node libvirtd ; then
            srv=libvirtd
        elif ! is_remote_running $node openstack-nova-compute ; then
            srv=openstack-nova-compute
        fi
        [ -n "$srv" ] || continue

        # Only control node with VIP takes actions
        if [ $($HEX_CFG status_pacemaker | awk '/IPaddr2/{print $5}') = $(hostname) ] ; then
            for cnt in $(seq $max) ; do
                echo "Failed to run $srv on node: $node ($cnt)"
                if remote_systemd_restart $node $srv ; then
                    sleep 5
                fi
                if is_remote_running $node $srv ; then
                    echo "On $node $srv is successfully restarted"
                    break
                fi
            done
            if [ $cnt -ge $max ] ; then
                echo "Ceph entering maintenance mode to avoid data reblancing"
                $HEX_SDK ceph_enter_maintenance
                echo "Stopping server instances on node: $node"
                remote_run $node reboot || true

                while ping -c 1 $node >/dev/null ; do
                    echo "Waiting for cluster to detect problematic node: $node"
                    sleep 10
                done

                sleep 30 && $OPENSTACK server list --long || true

                if $HEX_SDK os_post_failure_host_evacuation $node | grep "still in use" ; then
                    sleep 60
                    $HEX_SDK os_post_failure_host_evacuation $node
                fi
                echo "Evacuating server instances from $node"
                break
            fi
        fi
    done
}

health_nodelist_report()
{
    _health_report ${FUNCNAME[0]}
}

health_nodelist_check()
{
    local thisnode="$CUBE_NODE_LIST_JSON"
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        local nextnode=$(remote_run $node "cubectl node list -j")
        if [ "x$thisnode" != "x$nextnode" ] ; then
            ERR_CODE=1
            ERR_MSG+="$nextnode\n"
            ERR_LOG="cubectl node list"
        fi
    done

    ERR_MSG+="$thisnode\n"
    _health_fail_log
}

health_mongodb_report()
{
    ERR_MSG+="`$MONGODB --quiet --eval 'rs.status().members.map(member => ({name: member.name, health: member.health, stateStr: member.stateStr, lastHeartbeatMessage: member.lastHeartbeatMessage, syncSourceHost: member.syncSourceHost, uptime: member.uptime}))'`\n"
    _health_report ${FUNCNAME[0]}
}

health_mongodb_check()
{
    # check the mongodb ping-pong
    local is_connected="$($MONGODB --quiet --eval 'db.adminCommand("ping").ok' 2>/dev/null)"
    # check the mongodb quorum status which will impact the read/write operation
    local primary_count="$($MONGODB --quiet --eval 'rs.status().members.filter(member => member.stateStr === "PRIMARY").length' 2>/dev/null)"
    # check the overall node status between the registered nodes and the actual nodes
    local node_total=${#CUBE_NODE_CONTROL_HOSTNAMES[@]}
    local registered_node_count="$($MONGODB --quiet --eval 'rs.status().members.length' 2>/dev/null)"
    # check if any node is unavailable
    # the case here usually means the read/write is fine for whole cluster,
    # just some nodes are not reachable but which will not impact the cluster quorum
    local unavailable_count="$($MONGODB --quiet --eval 'rs.status().members.filter(member => member.stateStr === "(not reachable/healthy)").length' 2>/dev/null)"

    ERR_LOG="journalctl -n $ERR_LOGSIZE -u mongodb"
    if [ $? -ne 0 -o -z "$is_connected" ] ; then
        ERR_CODE=1
        ERR_MSG+="mongodb is not running\n"
    elif [ ${is_connected:-0} -ne 1 ] ; then
        ERR_CODE=1
        ERR_MSG+="mongodb can be accessed, but basic functions are not working properly\n"
    elif [ ${primary_count:-0} -eq 0 ] ; then
        ERR_CODE=2
        ERR_MSG+="mongodb quorum is lost, writes are blocked\n"
    elif [ ${node_total:-0} -ne ${registered_node_count:-0} ] ; then
        ERR_CODE=3      
        ERR_MSG+="$registered_node_count/$node_total nodes are online\n"
    elif [ ${unavailable_count:-0} -gt 0 ] ; then
        ERR_CODE=4
        ERR_MSG+="$unavailable_count nodes are unavailable\n"
    else
        $MONGODB --quiet --eval 'JSON.stringify(db.getSiblingDB("admin").getUser("admin"))' 2>/dev/null | jq -r '.roles[].role' | grep -q "readWriteAnyDatabase"
        local could_read_write_db=$?
        if [ ${could_read_write_db:-0} -ne 0 ] ; then
            ERR_CODE=5
            ERR_MSG+="user admin could not read write mongodb"
        fi
    fi

    _health_fail_log
}

_health_mongodb_auto_repair()
{
    # notice:
    # code 3:     it's not repairable automatically because the case might be caused by multiple reasons
    #             during cube.cos installation or migration, so the repair process is not deterministic
    #
    # true_fail:  when this value is not zero, it means the previous repair process was continuously unsuccessful.
    #             therefore, it is better not to perform any auto-repair until the issue is investigated and fixed manually.
    # auto repair for the cases like:
    # code 1: mongodb is not running well
    # code 2: mongodb quorum is lost, but the database can still be read

    if [ "$ERR_CODE" == "1" -o "$ERR_CODE" == "2" ] ; then
        health_mongodb_repair
    elif [ "$ERR_CODE" == "4" ] ; then
        # code 4: mongodb quorum is fine, but some nodes are not reachable
        result="$($MONGODB --quiet --eval 'rs.status().members.filter(member => member.stateStr === "(not reachable/healthy)").map(member => member.name).join(" ")')"
        IFS=' ' read -r -a unavailable_nodes <<< "$result"
        for node in "${unavailable_nodes[@]}"; do
            hostname="$(echo "$node" | sed 's/:.*//')"
            remote_systemd_restart $hostname mongodb
        done
    elif [ "$ERR_CODE" == "5" ] ; then
        # code 5: user admin needs role readWriteAnyDatabase
        $HEX_SDK mongodb_add_read_write_role
    fi
}

health_mongodb_repair()
{
    Quiet -n cubectl node exec -pn $HEX_SDK mongodb_repair_keyfile_ownership
    Quiet -n cubectl node exec -pn $HEX_CFG restart_mongodb
    Quiet -n $HEX_SDK mongodb_add_read_write_role
}

health_node_report()
{
    printf "+%12s+%7s+%15s+%15s+\n" | tr " " "-"
    printf "| %-10s | %5s | %13s | %13s |\n" "" " CPU " "     Disk    " "    Memory   "
    printf "+%12s+%7s+%7s+%7s+%7s+%7s+\n" | tr " " "-"
    printf "| %-10s | %5s | %5s | %5s | %5s | %5s |\n" "Host" "Usage" "Usage" "Avail" "Usage" "Avail"
    printf "+%12s+%7s+%7s+%7s+%7s+%7s+\n" | tr " " "-"
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        if ping -c 1 -w 1 $node >/dev/null ; then
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

health_db_select()
{
    local component=$1
    local limit=${2:-10}
    local tagfield="component,code,description,node,log"
    local flag=

    if [ "$FORMAT" = "json" ] ; then
        flag="-format json -pretty"
    fi
    [ "$VERBOSE" != "1" ] || tagfield+=",detail"

    if [ "x$1" = "x" ] ; then
        for component in $($HEX_SDK toggle_health_check | cut -d":" -f1) ; do
            $INFLUX $flag -database events -execute "select $tagfield from health where component='$component' order by desc limit $limit"
        done
    else
        $INFLUX $flag -database events -execute "select $tagfield from health where component='$component' order by desc limit $limit"
    fi
}

health_log_dump()
{
    local component=$1
    local n_from_last=${2:-1}
    local s3_log=$(health_db_select ${component:-NOSUCHCOMPONENT} 2>/dev/null | grep s3 | sed -n ${n_from_last}p | grep -o "s3://log/.*")

    if [ "x$s3_log" != "x" ] ; then
        $HEX_SDK os_s3_object_get admin $s3_log /tmp/$s3_log
        cat /tmp/$s3_log
        rm -f /tmp/$s3_log
    fi
}

health_log_detail()
{
    local component=$1
    local n_from_last=${2:-1}
    local flag="-format json"

    [ $n_from_last -ge 1 ] || Error "invalid index $n_from_last"
    local timestamp=$(VERBOSE=1 FORMAT= health_db_select $component $n_from_last | tail -1 | awk '{print $1}')
    if [ "$FORMAT" = "json" ] ; then
        $INFLUX $flag -database events -execute "select time,detail from health where (component='$component' and time=$timestamp)"
    else
        echo -n "$(date -d @${timestamp:0:10}) - "
        $INFLUX $flag -database events -execute "select time,detail from health where (component='$component' and time=$timestamp)" | jq -r .results[].series[].values[][] | tr ";" "\n"
    fi
}

_health_log_purge()
{
    local duration=$($INFLUX -format json -execute 'SHOW RETENTION POLICIES ON events' | jq -r .results[].series[].values[0][] | sed -n 2p)
    local duration_days=$(echo "${duration%h*} / 24" | bc)
    [ $duration_days -lt 365 ] || Error "duration_days: $duration_days"

    $HEX_SDK os_s3_list admin log | while read -r line; do
        createDate=$(echo $line | awk {'print $1" "$2'})
        createDate=$(date -d"$createDate" +%s)
        keepDate=$(date --date "${duration_days} days ago" +%s)
        if [ $createDate -lt $keepDate ] ; then
            fileName=$(echo $line | awk {'print $4'})
            [ "x$fileName" = "x" ] || $HEX_SDK os_s3_object_delete admin $fileName
        fi
    done
}
