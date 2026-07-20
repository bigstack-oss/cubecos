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
    ovn_db_check nb /var/lib/ovn/ovnnb_db.db
}

ovn_sb_check()
{
    ovn_db_check sb /var/lib/ovn/ovnsb_db.db
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

    # allow time for interfaces to appear
    for i in {1..10} ; do sleep 1 ; ip link show $bridge >/dev/null 2>&1 && break ; done
    for i in {1..10} ; do sleep 1 ; ip link show $port >/dev/null 2>&1 && break ; done

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

# --- OVN metadata liveness (nb_cfg progress) --------------------------------
# Alive=False just means the agent's sb-cfg lags nb_cfg (normal while it re-syncs after a
# reconnect). Track progress toward nb_cfg: catching-up self-heals, only a stuck (frozen)
# sb-cfg needs a restart. All OVN reads are bulk -- a fixed 3 calls per pass regardless of
# node count, since metadata runs on every compute. Mechanism/rationale in PR #1094.
_ovn_nb_cfg() { ovn-nbctl --timeout=5 get NB_Global . nb_cfg 2>/dev/null ; }

# One bulk snapshot of every chassis' metadata sb-cfg: "<hostname> <sbcfg>" per line.
# Joins Chassis (name->hostname) with Chassis_Private (name->external_ids) on chassis name
# -- two ovn-sbctl reads total, independent of node count. Empty if OVN can't be read.
_ovn_metadata_sbcfg_all()
{
    local chassis priv
    chassis=$(ovn-sbctl --timeout=5 -f csv --no-headings --columns=name,hostname list Chassis 2>/dev/null | tr -d '"')
    priv=$(ovn-sbctl --timeout=5 -f csv --no-headings --columns=name,external_ids list Chassis_Private 2>/dev/null | tr -d '"')
    [ -n "$chassis" ] && [ -n "$priv" ] || return 1
    awk '
        FNR==NR { i=index($0,","); host[substr($0,1,i-1)]=substr($0,i+1); next }
        { i=index($0,","); nm=substr($0,1,i-1)
          if (match($0,/neutron:ovn-metadata-sb-cfg=[0-9]+/)) {
              s=substr($0,RSTART,RLENGTH); sub(/.*=/,"",s)
              if (nm in host) print host[nm], s
          }
        }
    ' <(printf '%s\n' "$chassis") <(printf '%s\n' "$priv")
}

# Classify the given metadata hosts from ONE bulk snapshot (3 ovn calls total, not per host).
# Sets OVN_META_STUCK (frozen/unreadable -> restart) and OVN_META_CATCHING (advancing -> leave
# alone). A per-host state file holds the last sb-cfg, to tell advancing from frozen.
_ovn_metadata_classify()   # <hosts>
{
    OVN_META_STUCK=""; OVN_META_CATCHING=""
    local target snap h cur last statef
    declare -A _sb
    target=$(_ovn_nb_cfg)
    snap=$(_ovn_metadata_sbcfg_all)
    while read -r h cur ; do [ -n "$h" ] && _sb[$h]=$cur ; done <<< "$snap"
    for h in $1 ; do
        cur=${_sb[$h]:-} ; statef=${_OVN_SBCFG_DIR:-/run}/health_neutron_sbcfg_$h
        last=$(cat "$statef" 2>/dev/null)
        [ -n "$cur" ] && echo "$cur" > "$statef"
        if [ -z "$target" ] || [ -z "$cur" ] ; then OVN_META_STUCK+="$h "                    # can't tell -> repairable
        elif [ "$cur" -ge "$target" ] 2>/dev/null ; then :                                    # caught up
        elif [ -n "$last" ] && [ "$cur" -le "$last" ] 2>/dev/null ; then OVN_META_STUCK+="$h " # frozen
        else OVN_META_CATCHING+="$h "                                                         # advancing / first-seen
        fi
    done
}

# Alive=False metadata agents that are stuck (frozen sb-cfg); records them in OVN_META_STUCK.
_ovn_metadata_stuck_hosts()   # <service_stats>
{
    local hosts=$(echo "$1" | grep neutron-ovn-metadata-agent | grep -i False | awk '{print $3}')
    _ovn_metadata_classify "$hosts"
    [ -n "$OVN_META_STUCK" ]
}

# Wait only while progress is observable, capped by an absolute deadline. Each pass is a fixed
# 3 bulk ovn calls, so it scales to 100+ metadata agents; a failed/timed-out read yields stuck
# (not catching), so we bail instead of burning the budget. Manual repair() path only.
_ovn_metadata_wait_caught_up()   # <timeout-secs, default 120>
{
    local timeout=${1:-120} deadline hosts
    hosts=$($OPENSTACK network agent list -f value -c Binary -c Alive -c Host 2>/dev/null \
            | grep neutron-ovn-metadata-agent | grep -i False | awk '{print $3}')
    [ -n "$hosts" ] || return 0
    deadline=$(( $(date +%s) + timeout ))
    while [ "$(date +%s)" -lt "$deadline" ] ; do
        _ovn_metadata_classify "$hosts"
        [ -z "$OVN_META_CATCHING" ] && return 0
        sleep 10
    done
    return 0
}

# hand the OVN SB master to a peer before this host reboots (moving the VIP
# moves the master -- it is colocated with the promoted ovndb_servers)
ovn_sb_evacuate_host()
{
    local host=${1:-$(hostname)}
    # single node: nowhere to hand the master to
    [ "$(cubectl node list 2>/dev/null | wc -l)" -le 1 ] && return 0

    # 'pcs status' prints:  * Promoted: [ sky141 ]   (and a separate Unpromoted line,
    # which must not match here). Take the first host inside the brackets.
    local promoted=$(pcs status 2>/dev/null \
                     | sed -n 's/.*\* Promoted: \[ *\([^]]*\)\].*/\1/p' | awk '{print $1}')
    [ -n "$promoted" ] || return 0
    [ "$promoted" = "$host" ] || return 0

    local target=$(cubectl node list -r control -j 2>/dev/null | jq -r '.[].hostname' 2>/dev/null \
                   | grep -v "^$host$" | head -1)
    [ -n "$target" ] || return 0

    log_info "ovn_sb_evacuate_host: moving OVN SB master + VIP off $host to $target before reboot"
    Quiet -n timeout 60 pcs resource move vip "$target"

    # Settled = every chassis has acked the current nb_cfg, i.e. all OVSDB
    # clients have reconnected to the new master and caught up.
    local i nb acks settled=0
    for i in $(seq 1 60) ; do
        nb=$(_ovn_nb_cfg)
        acks=$(_ovn_metadata_sbcfg_all | awk '{print $2}')
        if [ -n "$nb" ] && [ -n "$acks" ] \
           && ! echo "$acks" | awk -v t="$nb" '$1 < t {f=1} END{exit !f}' ; then
            settled=1 ; break
        fi
        sleep 2
    done
    Quiet -n timeout 30 pcs resource clear vip

    if [ "$settled" = 1 ] ; then
        log_info "ovn_sb_evacuate_host: SB master on $target; all chassis acked nb_cfg=$nb"
    else
        log_warning "ovn_sb_evacuate_host: chassis did not all ack nb_cfg=$nb within 120s (acks: $(echo $acks | tr '\n' ' '))"
    fi
    return 0
}
