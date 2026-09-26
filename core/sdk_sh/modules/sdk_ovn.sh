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

# --- chassis first, central last: the previous OVN central beside the image's ----------
#
# OVN supports an ovn-controller newer than ovn-northd and the NB/SB databases, never
# older: a newer northd writes logical flows an older controller cannot parse (24.03's
# lr_in_learn_neighbor mac_cache_use drops every routed packet on a 23.03 chassis). A roll
# reboots every control node before any compute, so on a hop that moves OVN an upgraded
# control node keeps the central it carried across until every chassis runs the image's
# OVN, and ovn_central_switch then moves the cluster over in one step. How pacemaker runs
# the carried central is in core/neutron/cube-ovndb-servers.
#
# OVN_COMPAT_VER is the OVN minor the previous release's central may still run, and
# OVN_COMPAT_DIR this image's copy of that central, which core/neutron/neutron.mk lays
# out only on a hop that moves OVN. 3.1.20 moved it, 23.03 -> 24.03 (#1551); epoxy
# does not (#1277), so this image has no such copy and never holds a central back. What
# it still has to handle is a 3.1.20 cluster whose switch never completed: a control
# node that brings the 23.03 databases across converts them before its central starts
# (ovn_central_compat_enter). The next hop that moves OVN sets OVN_COMPAT_VER to the
# minor it leaves -- here and in cube-ovndb-servers, cube-ovn-ctl-compat,
# ovn-northd-compat.conf and config_neutron.cpp -- and lays the copy out again.
#
# The databases in OVN_COMPAT_DB_DIR are the mode itself -- no separate marker to drift
# -- and /etc/ovn is CONFIG_MIGRATE'd where /etc/appliance/state is not. Paths named,
# not inlined: the tests point them somewhere writable.
OVN_COMPAT_VER=${OVN_COMPAT_VER:-23.03}
OVN_COMPAT_DIR=${OVN_COMPAT_DIR:-/opt/ovn-$OVN_COMPAT_VER}
OVN_COMPAT_DB_DIR=${OVN_COMPAT_DB_DIR:-/etc/ovn/compat-$OVN_COMPAT_VER}
OVN_DB_DIR=${OVN_DB_DIR:-/etc/ovn}
OVN_SCHEMA_DIR=${OVN_SCHEMA_DIR:-/usr/share/ovn}

ovn_central_compat_active()
{
    [ -e $OVN_COMPAT_DB_DIR/ovnnb_db.db ]
}

# CONFIG_MIGRATE_POST(neutron), on the first boot of the new partition: after /etc/ovn is
# copied across and before bootstrap starts pacemaker, whose first start of this node's
# ovndb_servers would otherwise hand the previous central's databases to this image's
# ovn-ctl to convert. Role and HA come from the previous root, since the new one is not
# configured yet.
ovn_central_compat_enter()   # <prev-root-dir>
{
    local prev=$1 d
    # The previous release's roll left this node running its carried central -- the
    # switch never completed -- and this image has no such central to go on running.
    # Convert the databases here, as ovn_central_switch would have, rather than leave
    # pacemaker a central it cannot start. Every chassis already runs this OVN: the
    # previous release's own chassis do. The copy is the one this node shut down with,
    # so what the promoted central took since is not in it; migrate_neutron_ovn_sync
    # repairs the northbound from neutron's database once this node's central is up.
    if [ ! -d $OVN_COMPAT_DIR ] ; then
        ovn_central_compat_active || return 0
        local ts=$(date +%Y%m%d-%H%M%S)
        log_warning "ovn_central_compat_enter: this node carried an OVN $OVN_COMPAT_VER central across, which this image cannot run; converting its databases"
        ovn_central_convert_local $ts && return 0
        log_error "ovn_central_compat_enter: converting the OVN $OVN_COMPAT_VER databases failed; restoring them"
        ovn_central_restore_local $ts
        return 1
    fi
    [ -e $OVN_DB_DIR/ovnnb_db.db ] && [ -e $OVN_DB_DIR/ovnsb_db.db ] || return 0
    ovn_central_compat_active && return 0

    source hex_tuning $prev/etc/settings.txt cubesys.role
    source hex_tuning $prev/etc/settings.txt cubesys.ha
    case "$T_cubesys_role" in
        control|control-network|control-converged|edge-core|moderator) ;;
        *) return 0 ;;
    esac
    # a lone control node reboots its central and its chassis together: no mixed window
    [ "$T_cubesys_ha" = "true" ] || return 0

    # only the previous central's databases; anything else is this image's already
    for d in nb sb ; do
        [ "$(ovsdb-tool db-version $OVN_DB_DIR/ovn${d}_db.db 2>/dev/null)" = \
          "$(ovsdb-tool schema-version $OVN_COMPAT_DIR/share/ovn/ovn-$d.ovsschema 2>/dev/null)" ] || return 0
    done

    mkdir -p $OVN_COMPAT_DB_DIR || return 1
    mv -f $OVN_DB_DIR/ovnnb_db.db $OVN_DB_DIR/ovnsb_db.db $OVN_COMPAT_DB_DIR/ || return 1
    log_info "ovn_central_compat_enter: keeping the OVN $OVN_COMPAT_VER central until every chassis runs this image's OVN"
}

# 0 only if every chassis-bearing node runs this node's OVN minor -- the precondition for
# moving the central to it. Chassis-bearing by role bit (cubectl -r compute: compute,
# control-converged, edge-core) and read from the running daemon, not the package. Same
# fail-safe contract as os_neutron_version_uniform(): unreachable = unknown = not uniform.
ovn_chassis_version_uniform()
{
    local want h v hosts
    want=$(ovn-northd --version 2>/dev/null | awk 'NR==1{print $NF}' | cut -d. -f1,2)
    hosts=$(cubectl node list -r compute -j 2>/dev/null | jq -r '.[].hostname')
    [ -n "$want" ] && [ -n "$hosts" ] || return 1
    for h in $hosts ; do
        v=$(remote_run $h "ovn-appctl -t ovn-controller version 2>/dev/null" | awk 'NR==1{print $NF}' | cut -d. -f1,2)
        if [ "$v" != "$want" ] ; then
            log_info "ovn_chassis_version_uniform: $h runs ovn-controller ${v:-(unknown)}, not $want"
            return 1
        fi
    done
}

# On one node, with its ovndb_servers stopped: convert the carried central's databases
# into the default location and drop the mode. The carried files are kept as the backup
# #1276 asked for -- the conversion is one-way.
ovn_central_convert_local()   # <timestamp>
{
    ovn_central_compat_active || return 0
    local bk=$OVN_DB_DIR/backup-$OVN_COMPAT_VER-$1 d
    mkdir -p $bk || return 1
    for d in nb sb ; do
        # a default database this node had before it took the carried one: keep it aside
        if [ -e $OVN_DB_DIR/ovn${d}_db.db ] ; then
            mv -f $OVN_DB_DIR/ovn${d}_db.db $bk/ovn${d}_db.db.default || return 1
        fi
        cp -a $OVN_COMPAT_DB_DIR/ovn${d}_db.db $bk/ || return 1
        # compact first, as ovs-lib's upgrade_db does: convert replays every log record
        # against the new schema, not just the final state
        ovsdb-tool compact $OVN_COMPAT_DB_DIR/ovn${d}_db.db || return 1
        ovsdb-tool convert $OVN_COMPAT_DB_DIR/ovn${d}_db.db $OVN_SCHEMA_DIR/ovn-$d.ovsschema \
            $OVN_DB_DIR/ovn${d}_db.db || return 1
    done
    rm -rf $OVN_COMPAT_DB_DIR
}

# Undo ovn_central_convert_local <timestamp> on a node, for a switch that failed part-way.
ovn_central_restore_local()   # <timestamp>
{
    local bk=$OVN_DB_DIR/backup-$OVN_COMPAT_VER-$1 d
    [ -e $bk/ovnnb_db.db ] && [ -e $bk/ovnsb_db.db ] || return 0
    mkdir -p $OVN_COMPAT_DB_DIR || return 1
    for d in nb sb ; do
        cp -a $bk/ovn${d}_db.db $OVN_COMPAT_DB_DIR/ || return 1
        rm -f $OVN_DB_DIR/ovn${d}_db.db
        if [ -e $bk/ovn${d}_db.db.default ] ; then
            mv -f $bk/ovn${d}_db.db.default $OVN_DB_DIR/ovn${d}_db.db || return 1
        fi
    done
}

# ssh for ovn_central_switch, bounded the way cmd() is (connect, liveness and total
# time) and without remote_run's Error exit: once the central is stopped, every
# failure has to be handled, not abort the switch half-way or hang it on a wedged node.
_ovn_ssh()   # <host> <command>
{
    timeout ${CMD_SSH_TIMEOUT:-600} ssh -o LogLevel=quiet -o ConnectTimeout=10 \
        -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o BatchMode=yes root@"$@"
}

# Move the OVN central off the carried OVN_COMPAT_VER onto this image's OVN once every
# chassis runs it. Called when a roll completes, from cluster_start, or by hand; a no-op
# unless a control node still runs the carried central.
#
# One step, not node by node: across a major OVN change a backup cannot replicate from
# an active of the other version, either way round (23.03 -> 24.03 changed NB and SB
# column types), so a node switched early would hold a stale copy and promoting it would
# drop everything written since. Instead the central is stopped everywhere, every node's
# carried databases are converted, and it is started again. The VIP holder -- promoted
# before and after, the promotion follows the VIP -- converts the authoritative copy and
# the others resync from it. The chassis keep their flows while the NB/SB are down:
# seconds of control plane, no data plane.
ovn_central_switch()
{
    is_control_node || return 0
    source hex_tuning $SETTINGS_TXT cubesys.ha
    [ "$T_cubesys_ha" = "true" ] || return 0
    source hex_tuning $SETTINGS_TXT cubesys.control.vip
    local vip=$T_cubesys_control_vip
    [ -n "$vip" ] || return 1

    # one orchestrator, the node whose databases are the ones that count
    if ! ip -o addr show | grep -qF " $vip/" ; then
        remote_run $vip "$HEX_SDK ovn_central_switch"
        return $?
    fi
    exec 9>/run/ovn_central_switch.lock
    flock -n 9 || { log_info "ovn_central_switch: already running" ; return 0 ; }

    local want h compat="" ctrls
    want=$(ovn-northd --version 2>/dev/null | awk 'NR==1{print $NF}' | cut -d. -f1,2)
    ctrls=$(cubectl node list -r control -j 2>/dev/null | jq -r '.[].hostname')
    [ -n "$want" ] && [ -n "$ctrls" ] || return 1

    # Nothing is touched until every control node is reachable and has the new central:
    # past the disable below a failure has to be undone, not just reported.
    for h in $ctrls ; do
        if ! is_sshable $h ; then
            log_info "ovn_central_switch: $h is unreachable; staying on the $OVN_COMPAT_VER central"
            return 1
        fi
        if [ "$(_ovn_ssh $h 'ovn-northd --version 2>/dev/null' | awk 'NR==1{print $NF}' | cut -d. -f1,2)" != "$want" ] ; then
            log_info "ovn_central_switch: $h is not on OVN $want yet"
            return 0
        fi
        _ovn_ssh $h "test -e $OVN_COMPAT_DB_DIR/ovnnb_db.db" && compat="$compat $h"
    done
    [ -n "$compat" ] || return 0
    ovn_chassis_version_uniform || return 0

    local ts=$(date +%Y%m%d-%H%M%S) done="" rc=0
    log_info "ovn_central_switch: moving the OVN central to $want ($OVN_COMPAT_VER on$compat)"
    trap 'pcs resource enable ovndb_servers-clone' EXIT
    if ! pcs resource disable ovndb_servers-clone --wait=180 ; then
        log_error "ovn_central_switch: ovndb_servers did not stop; staying on the $OVN_COMPAT_VER central"
        return 1
    fi
    for h in $ctrls ; do
        if _ovn_ssh $h "$HEX_SDK ovn_central_convert_local $ts" ; then
            done="$done $h"
        else
            log_error "ovn_central_switch: converting the databases on $h failed; restoring $OVN_COMPAT_VER"
            rc=1
            break
        fi
    done
    if [ $rc -ne 0 ] ; then
        for h in $done $h ; do
            _ovn_ssh $h "$HEX_SDK ovn_central_restore_local $ts" || \
                log_error "ovn_central_switch: could not restore the $OVN_COMPAT_VER databases on $h"
        done
    fi
    trap - EXIT
    if ! pcs resource enable ovndb_servers-clone --wait=180 ; then
        log_error "ovn_central_switch: ovndb_servers did not come back"
        return 1
    fi
    [ $rc -eq 0 ] || return 1

    local nb=$(ovsdb-client get-schema-version unix:/var/run/ovn/ovnnb_db.sock OVN_Northbound 2>/dev/null)
    if [ "$nb" != "$(ovsdb-tool schema-version $OVN_SCHEMA_DIR/ovn-nb.ovsschema)" ] ; then
        log_error "ovn_central_switch: the promoted northbound is at ${nb:-(unreachable)}"
        return 1
    fi
    log_info "ovn_central_switch: the OVN central runs $want on every control node ($OVN_COMPAT_VER databases kept in $OVN_DB_DIR/backup-$OVN_COMPAT_VER-$ts)"
}
