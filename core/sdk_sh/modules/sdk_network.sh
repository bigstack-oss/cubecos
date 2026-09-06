# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

network_calculate_top()
{
    local router=$1
    local top=$2
    local netns=$3

    if [ "$VERBOSE" == "1" ] ; then
        $netns conntrack -L
    fi
    $netns conntrack -L 2>/dev/null | awk -v router=${router} -v top=${top} -v format=$FORMAT '
    $1=="tcp" {
        split($5, a, "=");
        split($6, b, "=");
        tcp_src[a[2]] += 1;
        tcp_dst[b[2]] += 1;
    }
    $1=="udp" {
        split($4, a, "=");
        split($5, b, "=");
        udp_src[a[2]] += 1;
        udp_dst[b[2]] += 1;
    }
    $1=="icmp" {
        split($4, a, "=");
        split($5, b, "=");
        icmp_src[a[2]] += 1;
        icmp_dst[b[2]] += 1;
    }
    $1=="unknown" {
        split($4, a, "=");
        split($5, b, "=");
        unknown_src[a[2]] += 1;
        unknown_dst[b[2]] += 1;
    }
    function sort(arr, num) {
        for (i = 0 ; i < num ; i++) {
            key = "";
            high = 0;
            for (k in arr) {
                if ((arr[k]+0) > high && length(k) > 1) {
                    high = arr[k]+0;
                    key = k;
                }
            }
            arr[i] = key " " high;
            delete arr[key];
        }
    }
    END {
        sort(tcp_src, top);
        sort(tcp_dst, top);
        sort(udp_src, top);
        sort(udp_dst, top);
        sort(icmp_src, top);
        sort(icmp_dst, top);
        sort(unknown_src, top);
        sort(unknown_dst, top);
        if (format == "pretty") {
            printf("\ntop tcp\n%-17s%6s    %-17s%6s\n", "source", "num", "destination", "num");
        }
        for (i = 0 ; i < top ; i++) {
            split(tcp_src[i], src, " ");
            split(tcp_dst[i], dst, " ");
            if (format == "pretty") {
                printf("%-17s%6s    %-17s%6s\n", src[1], src[2], dst[1], dst[2]);
            }
            if (format == "line") {
                if (src[2] > 0)
                  printf("vrouter.top,router=%s,proto=tcp,dir=src,ip=%s count=%d\n", router, src[1], src[2]);
                if (dst[2] > 0)
                  printf("vrouter.top,router=%s,proto=tcp,dir=dst,ip=%s count=%d\n", router, dst[1], dst[2]);
            }
        }
        if (format == "pretty") {
            printf("\ntop udp\n%-17s%6s    %-17s%6s\n", "source", "num", "destination", "num");
        }
        for (i = 0 ; i < top ; i++) {
            split(udp_src[i], src, " ");
            split(udp_dst[i], dst, " ");
            if (format == "pretty") {
                printf("%-17s%6s    %-17s%6s\n", src[1], src[2], dst[1], dst[2]);
            }
            if (format == "line") {
                if (src[2] > 0)
                  printf("vrouter.top,router=%s,proto=udp,dir=src,ip=%s count=%d\n", router, src[1], src[2]);
                if (dst[2] > 0)
                  printf("vrouter.top,router=%s,proto=udp,dir=dst,ip=%s count=%d\n", router, dst[1], dst[2]);
            }
        }
        if (format == "pretty") {
            printf("\ntop icmp\n%-17s%6s    %-17s%6s\n", "source", "num", "destination", "num");
        }
        for (i = 0 ; i < top ; i++) {
            split(icmp_src[i], src, " ");
            split(icmp_dst[i], dst, " ");
            if (format == "pretty") {
                printf("%-17s%6s    %-17s%6s\n", src[1], src[2], dst[1], dst[2]);
            }
            if (format == "line") {
                if (src[2] > 0)
                  printf("vrouter.top,router=%s,proto=icmp,dir=src,ip=%s count=%d\n", router, src[1], src[2]);
                if (dst[2] > 0)
                  printf("vrouter.top,router=%s,proto=icmp,dir=dst,ip=%s count=%d\n", router, dst[1], dst[2]);
            }
        }
        if (format == "pretty") {
            printf("\ntop unknown\n%-17s%6s    %-17s%6s\n", "source", "num", "destination", "num");
        }
        for (i = 0 ; i < top ; i++) {
            split(unknown_src[i], src, " ");
            split(unknown_dst[i], dst, " ");
            if (format == "pretty") {
                printf("%-17s%6s    %-17s%6s\n", src[1], src[2], dst[1], dst[2]);
            }
            if (format == "line") {
                if (src[2] > 0)
                  printf("vrouter.top,router=%s,proto=unknown,dir=src,ip=%s count=%d\n", router, src[1], src[2]);
                if (dst[2] > 0)
                  printf("vrouter.top,router=%s,proto=unknown,dir=dst,ip=%s count=%d\n", router, dst[1], dst[2]);
            }
        }
        if (format == "pretty") {
            printf("\n");
        }
    }'
}

network_virtual_router_stats()
{
    local top=${1:-5}
    local max=$(cat /proc/sys/net/netfilter/nf_conntrack_max)
    local sess_count=$(cat /proc/sys/net/netfilter/nf_conntrack_count)
    local sess_pcnt=$((sess_count*100/max))
    local total_count=$sess_count
    local netns=

    if [ "$FORMAT" == "pretty" ] ; then
        echo "default"
        echo "---------------------------------------------------------"
        echo "session: $sess_count(${sess_pcnt}%)"
        echo "   top$top:"
    fi
    if [ "$FORMAT" == "line" ] ; then
        printf "vrouter.stats,router=default sess_count=$sess_count,sess_pcnt=$sess_pcnt\n"
    fi
    network_calculate_top "default" $top

    readarray rt_array <<<"$($IP netns list | grep qrouter | awk '{print $1}'| sort)"
    declare -p rt_array > /dev/null
    for rt_entry in "${rt_array[@]}" ; do
        local rt_name=$(echo $rt_entry | tr -d '\n')
        [ ! -n "$rt_name" ] && continue
        netns="$IP netns exec $rt_name"
        if [ "$FORMAT" == "pretty" ] ; then
            echo $rt_name
            echo "---------------------------------------------------------"
        fi
        local rid=$(echo $rt_name | cut -d"-" -f2-)
        local router_ip=$($netns $IP addr | grep qg- | grep inet | egrep -v "/32" | awk '{print $2}' | awk -F'/' '{print $1}' )
        local router_port=$($netns $IP addr | grep qg- | grep inet | egrep -v "/32" | awk '{print $5}' )
        local gateway_ip=$($netns $IP addr | grep qr- | grep inet | egrep -v "/32" | awk '{print $2}' | awk -F'/' '{print $1}' )
        local gateway_port=$($netns $IP addr | grep qr- | grep inet | egrep -v "/32" | awk '{print $5}' )
        local fip_count=$($netns $IP addr | grep qg- | grep '/32' | awk '{print $2}' | awk -F'/' '{print $1}' | wc -l)
        sess_count=$($netns cat /proc/sys/net/netfilter/nf_conntrack_count)
        sess_pcnt=$((sess_count*100/max))
        if [ -n "$router_ip" ] ; then
            total_count=$(( total_count + sess_count ))
            if [ "$FORMAT" == "pretty" ] ; then
                echo "  state: active"
                echo "session: $sess_count(${sess_pcnt}%)"
                echo "    fip: $fip_count"
                # ha configs
                shell_name=$(ls /var/lib/neutron/ha_confs/$rid/ha_check_script_*.sh 2>/dev/null | awk -F'/' '{print $NF}')
                if [ -n "$shell_name" ] ; then
                    vrrp_pid=$(cat /var/lib/neutron/ha_confs/$rid.pid-vrrp 2>/dev/null)
                    shell_act=$(cat /var/lib/neutron/ha_confs/$rid/ha_check_script_*.sh 2>/dev/null | grep ping | awk '{print $1" "$6}')
                    echo "     ha: Keepalived_vrrp[$vrrp_pid]: $shell_name '$shell_act'"
                fi
                readarray gw_ip_array <<<"$($netns $IP addr | grep qr- | grep inet | egrep -v "/32" | awk '{print $2}' | awk -F'/' '{print $1}' )"
                declare -p gw_ip_array > /dev/null
                readarray gw_port_array <<<"$($netns $IP addr | grep qr- | grep inet | egrep -v "/32" | awk '{print $5}' )"
                declare -p gw_port_array > /dev/null
                for i in "${!gw_ip_array[@]}" ; do
                    local gw_ip=$(echo ${gw_ip_array[i]} | tr -d '\n')
                    local gw_port=$(echo ${gw_port_array[i]} | tr -d '\n')
                    if [ $i -eq 0 ] ; then
                        printf "  ports: (%14s) %15s <-> %15s (%14s)\n" "$router_port" "$router_ip" "$gw_ip" "$gw_port"
                    else
                        printf "  %40s -> %15s (%14s)\n" "" "$gw_ip" "$gw_port"
                    fi
                done
                echo "   top$top:"
            fi
            if [ "$FORMAT" == "line" ] ; then
                printf "vrouter.stats,router=$rt_name,router_ip=$router_ip fip_count=$fip_count,sess_count=$sess_count,sess_pcnt=$sess_pcnt\n"
            fi
            network_calculate_top $rt_name $top "$netns"
        else
            [ "$FORMAT" == "pretty" ] && printf "  state: backup\n\n"
        fi
    done

    [ "$FORMAT" == "pretty" ] && printf "total_count=$total_count max=$max\n\n" || /bin/true
}

network_host_ping()
{
    for h in $(cubectl node list | awk -F',' '{print $1}') ; do
        local attrs=$(cubectl node list -j | jq ".[] | select(.hostname==\"$h\")")
        local mgmt=$(ping -c 1 -w 1 $(echo $attrs | jq -r .ip.management) 2>/dev/null| tail -1 | awk '{print $4}' | cut -d '/' -f 2)
        local prov=$(ping -c 1 -w 1 $(echo $attrs | jq -r .ip.provider) 2>/dev/null| tail -1 | awk '{print $4}' | cut -d '/' -f 2)
        local over=$(ping -c 1 -w 1 $(echo $attrs | jq -r .ip.overlay) 2>/dev/null| tail -1 | awk '{print $4}' | cut -d '/' -f 2)
        local stor=$(ping -c 1 -w 1 $(echo $attrs | jq -r .ip.storage) 2>/dev/null| tail -1 | awk '{print $4}' | cut -d '/' -f 2)
        echo "host.health,proto=icmp,checker=$HOSTNAME,host=$h,type=management,ip=$(echo $attrs | jq -r .ip.management) resp=$mgmt"
        echo "host.health,proto=icmp,checker=$HOSTNAME,host=$h,type=storage,ip=$(echo $attrs | jq -r .ip.storage) resp=$stor"
        if [ "$(echo $attrs | jq -r .ip.provider)" != "null" ] ; then
            echo "host.health,proto=icmp,checker=$HOSTNAME,host=$h,type=provider,ip=$(echo $attrs | jq -r .ip.provider) resp=$prov"
        fi
        if [ "$(echo $attrs | jq -r .ip.overlay)" != "null" ] ; then
            echo "host.health,proto=icmp,checker=$HOSTNAME,host=$h,type=overlay,ip=$(echo $attrs | jq -r .ip.overlay) resp=$over"
        fi
    done
}

network_device_ping()
{
    if [ ! -f $DEV_LIST ] ; then
        return
    fi

    for ping in $(cat $DEV_LIST | grep -v "role=cube" | awk -F"ping=" '{print $2}' | awk -F',' '{print $1}') ; do
        ping=$(echo $ping | tr -d '\n' | tr -d '\r')
        if [ -n "$ping" ] ; then
            local h=$(cat $DEV_LIST | grep "ping=$ping" | awk -F"hostname=" '{print $2}' | awk -F',' '{print $1}' | tr -d '\n' | tr -d '\r')
            local s=$(cat $DEV_LIST | grep "ping=$ping" | awk -F"ip=" '{print $2}' | awk -F',' '{print $1}' | tr -d '\n' | tr -d '\r')
            local resp=$(ping -c 1 -w 1 $ping 2>/dev/null| tail -1 | awk '{print $4}' | cut -d '/' -f 2)
            if [ -z "$resp" ] ; then
                resp=-1
            fi
            if [ -n "$h" ] ; then
                echo "ipmi_sensor,name=ping_checker,host=$HOSTNAME,hostname=$h,ip=$ping resp=$resp"
            else
                echo "ipmi_sensor,name=ping_checker,host=$HOSTNAME,hostname=$s,ip=$ping resp=$resp"
            fi
        fi
    done
    for host in $(cat $DEV_LIST | grep -v "role=cube" | awk -F"hostname=" '{print $2}' | awk -F',' '{print $1}') ; do
        host=$(echo $host | tr -d '\n' | tr -d '\r')
        if [ -n "$host" ] ; then
            echo "ipmi_sensor,name=host_marker,host=$HOSTNAME,hostname=$host value=1"
        fi
    done
}

network_device_link()
{
    local file=$1

    if [ ! -f $file ] ; then
        return
    fi

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}" ; do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        scp $file root@$ctrl:$DEV_LIST
        remote_run $ctrl hex_config bootstrap telegraf
    done
}

_init_network_chain()
{
    local chain="${1:-""}"

    if [ -z "$chain" ] ; then
        return 0
    fi

    iptables -n --list $chain >/dev/null 2>&1 || iptables -N $chain
    iptables -F $chain
}

_set_ipt_service_int()
{
    local chain=SERVICE-INT
    _init_network_chain "$chain"

    # we should allow all local traffics
    iptables -A $chain -i lo -j ACCEPT

    source hex_tuning $SETTINGS_TXT cubesys.controller.ip
    [ "x$T_cubesys_controller_ip" = "x" ] || iptables -A $chain -s $T_cubesys_controller_ip -j ACCEPT

    source hex_tuning $SETTINGS_TXT cubesys.control.vip
    [ "x$T_cubesys_control_vip" = "x" ] || iptables -A $chain -s $T_cubesys_control_vip -j ACCEPT

    for A in $(cubectl node list -j | jq -r .[].ip.management | sort -u) ; do
        iptables -A $chain -s $A -j ACCEPT
    done

    local ipt_rc=/etc/appliance/state/iptables_service-int
    # -p tcp --dport 22 -j ACCEPT
    # -j DROP
    while read -r rule ; do
        [ -z "$rule" ] || iptables -A $chain $rule
    done < $ipt_rc

    iptables -A $chain -p tcp --match multiport --dports 5900:5999 -j DROP # drop all direct vnc access, except for internal nodes
    iptables -A $chain -p tcp --dport 3306 -j DROP # drop Database Open Access (database-open-access 3306)
    iptables -A $chain -p tcp --dport 5672 -j DROP # drop AMQP Cleartext Authentication (amqp-cleartext-authentication 5672), except for internal nodes
    iptables -A $chain -p tcp --dport 15672 -j DROP # drop RabbitMQ management UI/API (rabbitmq-management 15672), except for internal nodes
    iptables -A $chain -p tcp --dport 25672 -j DROP # drop RabbitMQ Erlang distribution (erlang-distribution 25672), except for internal nodes
    iptables -A $chain -p icmp --icmp-type timestamp-request -j DROP # drop ICMP timestamp requests

    iptables -nv -L INPUT 2>/dev/null | grep -q $chain || iptables -A INPUT -j $chain
}

_set_ipt_service_out()
{
    local chain=SERVICE-OUT
    _init_network_chain "$chain"

    # drop ICMP timestamp replies
    iptables -A "$chain" -p icmp --icmp-type timestamp-reply -j DROP

    iptables -nv -L OUTPUT 2>/dev/null | grep -q $chain || iptables -A OUTPUT -j $chain
}

network_ipt_serviceint()
{
    _set_ipt_service_int
    _set_ipt_service_out
}

network_ipt_restore()
{
    [ ! -e /run/iptables ] || iptables-restore < /run/iptables
}

# Air-gap simulation (validation): drop the node's egress to public dests so any
# install step reaching the internet fails; allow loopback + all private /
# link-local / multicast (driver + intra-cluster stay reachable). Driver-set via
# the airgap_sim marker; clear cluster-wide with
# `cubectl exec -p 'hex_sdk airgap_sim_clear'`. Idempotent.
airgap_sim_apply()
{
    touch /etc/appliance/state/airgap_sim
    # already fully applied? leave the chain untouched so DROP counters keep
    # accumulating -- re-applying with a flush zeroes them and makes air-gap
    # violations unauditable (the agent re-applies periodically)
    if [ "$(iptables -S CUBE_AIRGAP 2>/dev/null | grep -c .)" -eq 8 ] &&
       iptables -C OUTPUT -j CUBE_AIRGAP 2>/dev/null ; then
        return 0
    fi
    iptables -nL CUBE_AIRGAP >/dev/null 2>&1 && iptables -F CUBE_AIRGAP || iptables -N CUBE_AIRGAP
    iptables -A CUBE_AIRGAP -o lo -j RETURN
    local net
    for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 224.0.0.0/4 ; do
        iptables -A CUBE_AIRGAP -d $net -j RETURN
    done
    iptables -A CUBE_AIRGAP -j DROP
    iptables -C OUTPUT -j CUBE_AIRGAP 2>/dev/null || iptables -I OUTPUT 1 -j CUBE_AIRGAP
}

airgap_sim_clear()
{
    rm -f /etc/appliance/state/airgap_sim
    while iptables -C OUTPUT -j CUBE_AIRGAP 2>/dev/null ; do iptables -D OUTPUT -j CUBE_AIRGAP ; done
    iptables -F CUBE_AIRGAP 2>/dev/null
    iptables -X CUBE_AIRGAP 2>/dev/null
}

# Bond aggregator health, 802.3ad only.
#
# The failure this exists for: cc1 on accept-3cc sat unreachable for 14 hours with
# every conventional signal healthy -- both slaves UP/LOWER_UP at 1000Mbps, MII
# Status up, the provider bridge holding the management IP, OVS forwarding with a
# NORMAL flow and 493M packets counted. What was actually wrong was one bit: the
# active aggregator's actor port state had lost Synchronization, so no slave was
# collecting or distributing, and ARP failed to every peer including the gateway
# in both directions. Nothing in the health SDK could see that -- health_link_check
# only pings, which cannot tell "the peer is down" from "my own bond is wedged".
#
# Do NOT use Actor Churn State for this. It reads "churned" on perfectly healthy
# nodes here, because the peer never answers LACPDUs and the bond runs permanently
# defaulted; measured identical on all three nodes while two served traffic and one
# black-holed. The active aggregator's Synchronization bit is what separates them.
_network_bond_list()
{
    cat /sys/class/net/bonding_masters 2>/dev/null
}

# 0 = this bond's active aggregator has a synchronized slave, 1 = it does not.
# A missing bond, or one that is not 802.3ad, is reported healthy: there is no
# aggregator that could be out of sync.
_network_bond_synced()
{
    local bond=$1 f=/proc/net/bonding/$bond
    [ -r "$f" ] || return 0
    grep -q "Bonding Mode: IEEE 802.3ad" "$f" || return 0

    awk '
        # the active aggregator id is indented under its own header; the per-slave
        # one starts at column 0, which is how the two are told apart
        /Active Aggregator Info:/ { inhdr = 1 ; next }
        inhdr && /Aggregator ID:/ { active = $3 ; inhdr = 0 ; next }
        /^Slave Interface:/       { agg = "" ; actor = 0 ; next }
        /^Aggregator ID:/         { agg = $3 ; next }
        /details actor lacp pdu:/ { actor = 1 ; next }
        actor && /port state:/ {
            # Synchronization is bit 3 (0x08) of the actor port state:
            # 79 has it, 71 does not
            if (agg == active && int($3) % 16 >= 8) synced = 1
            actor = 0
        }
        END { exit(synced ? 0 : 1) }
    ' "$f"
}

# Ground truth, used as a second opinion before bouncing anything: a bond whose
# aggregator looks odd but is still carrying traffic must be left alone.
_network_bond_reachable()
{
    local gw peer
    gw=$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}')
    [ -n "$gw" ] && ping -c 1 -W 2 "$gw" >/dev/null 2>&1 && return 0
    for peer in "${CUBE_NODE_LIST_IPS[@]}" ; do
        [ "x$peer" = "x$(hostname -i 2>/dev/null | awk '{print $1}')" ] && continue
        ping -c 1 -W 2 "$peer" >/dev/null 2>&1 && return 0
    done
    return 1
}

# 0 = every bond on this node is healthy, 1 = at least one is not. Prints a line
# per bond, so it doubles as the operator-facing diagnostic:
#   hex_sdk network_bond_check
network_bond_check()
{
    local bond rc=0
    for bond in $(_network_bond_list) ; do
        if _network_bond_synced "$bond" ; then
            echo "$bond synced"
        else
            echo "$bond NOT synced (active aggregator has no synchronized slave)"
            rc=1
        fi
    done
    return $rc
}

# Bounce the slaves one at a time to force LACP renegotiation, stopping as soon as
# the aggregator synchronizes. Safe by construction: it only ever runs on a bond
# that is already carrying nothing.
network_bond_repair()
{
    local bond slaves s
    for bond in $(_network_bond_list) ; do
        _network_bond_synced "$bond" && continue
        slaves=$(cat /sys/class/net/$bond/bonding/slaves 2>/dev/null)
        log_error "network_bond_repair: $bond active aggregator has no synchronized slave, bouncing [$slaves] to force LACP renegotiation"
        for s in $slaves ; do
            ip link set "$s" down 2>/dev/null
            sleep 3
            ip link set "$s" up 2>/dev/null
            sleep 12
            if _network_bond_synced "$bond" ; then
                log_info "network_bond_repair: $bond synchronized after bouncing $s"
                break
            fi
        done
        _network_bond_synced "$bond" || log_error "network_bond_repair: $bond still not synchronized after bouncing every slave"
    done
}

# cron entry point. Deliberately not wired into the health SDK: every repair path
# there is driven from a *reachable* node over ssh, and a node whose bond has lost
# sync is by definition not reachable -- it has to fix itself, locally, with no
# dependency on the telemetry or cluster stack.
network_bond_watchdog()
{
    local now stamp=/run/network_bond_watchdog.last

    # one decision path shared with the operator command, rather than a second
    # copy of the loop that can drift from it
    network_bond_check >/dev/null 2>&1 && return 0

    # still passing traffic? then the aggregator reading is not worth acting on
    _network_bond_reachable && return 0

    # Rate limit. A bounce takes ~15s per slave and briefly drops the link, so a
    # fault this cannot fix must not turn into a permanent flap.
    now=$(date +%s)
    if [ -r $stamp ] && [ $(( now - $(cat $stamp 2>/dev/null || echo 0) )) -lt ${BOND_WATCHDOG_HOLDOFF:-900} ] ; then
        return 0
    fi
    echo "$now" > $stamp

    /usr/sbin/hex_log_event -e ETH00003W "interface=host,host=$HOSTNAME,category=network,service=bonding,action=aggregator_desynchronized"
    network_bond_repair
    if network_bond_check >/dev/null 2>&1 ; then
        /usr/sbin/hex_log_event -e ETH00004I "interface=host,host=$HOSTNAME,category=network,service=bonding,action=aggregator_resynchronized"
    fi
}
