# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

VSCTL="/usr/bin/ovs-vsctl"
IP_CMD="/usr/sbin/ip"
ROUTE_CMD="/usr/sbin/route"

ovn_db_check()
{
    local name=$1
    local db=$2

    if ovsdb-tool db-is-standalone $db ; then
        echo "standalone $name"
    elif ovsdb-tool db-is-clustered $db ; then
        if ovsdb-tool check-cluster $db ; then
            echo "healthy clustered $name"
        else
            echo "unhealthy clustered $name"
        fi
    fi
}

ovn_nb_check()
{
    ovn_db_check nb /var/lib/openvswitch/ovnnb_db.db
}

ovn_sb_check()
{
    ovn_db_check sb /var/lib/openvswitch/ovnsb_db.db
}

ovn_run()
{
    echo -e "\n\n[`whoami`@`hostname`~]# $1 "
    eval "$1"
}

ovn_db_show()
{
    local nb=$(grep ^[^#] /etc/neutron/plugins/ml2/ml2_conf.ini | awk -F'= ' '/ovn_nb_connection/{print $2}')
    local sb=$(grep ^[^#] /etc/neutron/plugins/ml2/ml2_conf.ini | awk -F'= ' '/ovn_sb_connection/{print $2}')
    local ovsdb=$(grep ^[^#] /etc/neutron/plugins/networking-ovn/networking-ovn-metadata-agent.ini | awk -F'= ' '/ovsdb_connection/{print $2}')

    ovn_run "ovn-nbctl --db=$nb show"
    ovn_run "ovn-sbctl --db=$sb show"
    ovn_run "ovs-vsctl --db=$ovsdb show"
}

ovn_ovs_dump()
{
    local table=$1
    local ovsdb=$2

    [ -z "$ovsdb" ] && ovsdb=$(grep ^[^#] /etc/neutron/plugins/networking-ovn/networking-ovn-metadata-agent.ini | awk -F'= ' '/ovsdb_connection/{print $2}')

    if [ "$table" == "all" ] ; then
        ovn_run "ovsdb-client dump $ovsdb"
    elif [ -n "$table" ] ; then
        ovn_run "ovsdb-client dump $ovsdb $table"
        ovn_run "ovs-vsctl --db=$ovsdb list $table"
    else
        ovn_run "ovsdb-client list-tables $ovsdb"
    fi
}

ovn_nb_dump()
{
    local table=$1
    local nb=$2

    [ -z "$nb" ] && nb=$(grep ^[^#] /etc/neutron/plugins/ml2/ml2_conf.ini | awk -F'= ' '/ovn_nb_connection/{print $2}')

    if [ "$table" == "all" ] ; then
        ovn_run "ovsdb-client dump $nb"
    elif [ -n "$table" ] ; then
        ovn_run "ovsdb-client dump $nb $table"
        ovn_run "ovn-nbctl --db=$nb list $table"
    else
        ovn_run "ovsdb-client list-tables $nb"
    fi
}

ovn_sb_dump()
{
    local table=$1
    local sb=$2

    [ -z "$sb" ] && sb=$(grep ^[^#] /etc/neutron/plugins/ml2/ml2_conf.ini | awk -F'= ' '/ovn_sb_connection/{print $2}')

    if [ "$table" == "all" ] ; then
        ovn_run "ovsdb-client dump $sb"
    elif [ -n "$table" ] ; then
        ovn_run "ovsdb-client dump $sb $table"
        ovn_run "ovn-sbctl --db=$sb list $table"
    else
        ovn_run "ovsdb-client list-tables $sb"
    fi
}

ovn_sb_flow_list()
{
    local sb=$(grep ^[^#] /etc/neutron/plugins/ml2/ml2_conf.ini | awk -F'= ' '/ovn_sb_connection/{print $2}')
    ovn_run "ovn-sbctl --db=$sb lflow-list"
}

ovn_neutron_db_sync()
{
    master_info="$(pcs status resources ovndb_servers 2>/dev/null | grep Promoted)"
    [[ "${master_info}" == *"$(hostname)"* ]] && ovn-sbctl --all destroy mac_binding

    if is_control_node ; then
        neutron-ovn-db-sync-util --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini --ovn-neutron_sync_mode repair >/dev/null 2>&1
    fi
}

ovn_bridge_phy_port_add_v4()
{
    local bridge=$1
    local port=$2
    local cidrs=$(ip -4 addr show $port | grep "^    inet .* $port" | awk '{print $2}')
    local defgw=$(ip -4 route | grep "^default.*$port" | awk '{print $3}')

    # clean up tasks
    local obrig=$(GetParentIfname $port)
    if [ -n "$obrig" -a "$obrig" != "$port" ] ; then
        if [ "$bridge" != "$obrig" ] ; then
            $VSCTL --if-exists del-port $obrig $port
            if [ $($VSCTL list-ports $obrig | wc -l) -eq 0 ] ; then
                $VSCTL --if-exists del-br $obrig
            fi
        fi
    fi

    $VSCTL --may-exist add-br $bridge

    # clear target bridge for target port
    for p in $($VSCTL list-ports $bridge | grep -v "patch-provnet-.*-to-br-int") ; do
        if [ "$p" != "$port" ] ; then
            $VSCTL --if-exists del-port $bridge $p
        fi
    done

    if ! $IP_CMD link show $bridge | grep -q "UP" ; then
        $IP_CMD link set $bridge up
    fi

    # sync mtu from parent interface
    $IP_CMD link set dev $bridge mtu $(cat /sys/class/net/$port/mtu) >/dev/null 2>&1

    if ! $IP_CMD -4 addr show $bridge | grep -q "inet" ; then
        for cidr in $cidrs ; do
            $IP_CMD -4 addr add $cidr dev $bridge
        done
    fi

    if [ -n "$defgw" ] ; then
        if ! $IP_CMD -4 route | grep "^default.*$bridge" ; then
            $ROUTE_CMD add default gw $defgw $bridge
        fi
    fi

    $VSCTL --may-exist add-port $bridge $port

    if $IP_CMD -4 addr show $port | grep -q "inet" ; then
        for cidr in $cidrs ; do
            $IP_CMD -4 addr del $cidr dev $port
        done
    fi
}

ovn_bridge_phy_port_remove_v4()
{
    local bridge=$1
    local port=$2

    if ! $IP_CMD link show | grep -q ": $bridge" ; then
        return
    fi

    local cidrs=$(ip -4 addr show $bridge | grep "^    inet .* $bridge" | awk '{print $2}')
    local defgw=$(ip -4 route | grep "^default.*$bridge" | awk '{print $3}')

    if ! $IP_CMD link show $port | grep -q "UP" ; then
        $IP_CMD link set $port up
    fi

    if ! $IP_CMD -4 addr show $port | grep -q "inet" ; then
        for cidr in $cidrs ; do
            $IP_CMD -4 addr add $cidr dev $port
        done
    fi

    if [ -n "$defgw" ] ; then
        if ! $IP_CMD -4 route | grep "^default.*$port" ; then
            $ROUTE_CMD add default gw $defgw $port
        fi
    fi

    $VSCTL --if-exists del-port $bridge $port

    if $IP_CMD -4 addr show $bridge | grep -q "inet" ; then
        for cidr in $cidrs ; do
            $IP_CMD -4 addr del $cidr dev $bridge
        done
    fi

    $VSCTL --if-exists del-br $bridge
}

ovn_sflow_cardinality_show()
{
    influx -host $(shared_id) -format json -database "telegraf" -execute "show series cardinality on telegraf from telegraf.hc.sflow" | jq -c .results[0].series[0].values[][]
}

ovn_sflow_status()
{
    local brIntId=$(ovs-vsctl list sflow | grep "header.*192" -B 4 | grep "_uuid.*:" | awk '{print $NF}' | tr -d '\n')
    [ -n "$brIntId" ]
}

ovn_sflow_list()
{
    ovs-vsctl list sflow
}

ovn_bridge_sflow_enable()
{
    local mgmtIf=$1
    local sharedId=$2
    if [ -n "$mgmtIf" -a -n "$sharedId" ] ; then
        local brIntId=$(ovs-vsctl list sflow | grep "header.*192" -B 4 | grep "_uuid.*:" | awk '{print $NF}' | tr -d '\n')
        if [ -z "$brIntId" ] ; then
            ovs-vsctl -- --id=@sflow create sflow agent=$mgmtIf target=\"$sharedId:6343\" header=192 sampling=512 polling=10 -- set bridge br-int sflow=@sflow >/dev/null
        fi
        local provId=$(ovs-vsctl list sflow | grep "header.*128" -B 4 | grep "_uuid.*:" | awk '{print $NF}' | tr -d '\n')
        if [ -z "$provId" ] ; then
            ovs-vsctl -- --id=@sflow create sflow agent=$mgmtIf target=\"$sharedId:6343\" header=128 sampling=512 polling=10 -- set bridge provider sflow=@sflow >/dev/null
        fi

        touch /etc/appliance/state/sflow_enabled
    fi
}

ovn_bridge_sflow_disable()
{
    local brIntId=$(ovs-vsctl list sflow | grep "header.*192" -B 4 | grep "_uuid.*:" | awk '{print $NF}' | tr -d '\n')
    if [ -n "$brIntId" ] ; then
        ovs-vsctl remove bridge br-int sflow $brIntId
    fi
    local provId=$(ovs-vsctl list sflow | grep "header.*128" -B 4 | grep "_uuid.*:" | awk '{print $NF}' | tr -d '\n')
    if [ -n "$provId" ] ; then
        ovs-vsctl remove bridge provider sflow $provId
    fi

    rm -f /etc/appliance/state/sflow_enabled
}
