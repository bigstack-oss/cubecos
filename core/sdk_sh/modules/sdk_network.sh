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

network_cluster_link()
{
    local file=$1

    if [ ! -f $file ] ; then
        return
    fi

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}" ; do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        scp $file root@$ctrl:$CLS_LIST
        remote_run $ctrl hex_config bootstrap lmi
    done
}

network_app_link()
{
    local file=$1

    if [ ! -f $file ] ; then
        return
    fi

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}" ; do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        scp $file root@$ctrl:$APP_BUNDLE
        remote_run $ctrl mkdir -p $APP_IMG_DIR
        remote_run $ctrl unzip -o -j $APP_BUNDLE -d $APP_IMG_DIR
        remote_run $ctrl mv $APP_IMG_DIR/app.lst $APP_LIST
        remote_run $ctrl chown -R www-data:www-data $APP_IMG_DIR
        remote_run $ctrl hex_config bootstrap lmi
    done
}

network_ipt_serviceint()
{
    local policy=${1:-ACCEPT}
    local chain=SERVICE-INT

    iptables $table -n --list $chain >/dev/null 2>&1 || iptables -N $chain
    iptables -F $chain

    source hex_tuning /etc/settings.txt cubesys.controller.ip
    [ "x$T_cubesys_controller_ip" = "x" ] || iptables -A $chain -s $T_cubesys_controller_ip -j ACCEPT

    source hex_tuning /etc/settings.txt cubesys.control.vip
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

    iptables -nv -L INPUT 2>/dev/null | grep -q $chain || iptables -A INPUT -j $chain
}
