# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

COOKIE_FILE=/tmp/cookie.txt
LOGIN_PAGE=/tmp/login.html
EP_SNAPSHOT=/var/appliance-db/os_endpoint.snapshot
NEUTRON_AGENT_CACHE=/var/appliance-db/neutron_agent.list

os_wsgi_conf_update()
{
    local infs=$(ls /etc/httpd/conf.d/*-wsgi.conf.in)
    local addr=$1

    for inf in $infs ; do
        sed -e "s/@BIND_ADDR@/$addr:/" $inf > /etc/httpd/conf.d/$(basename $inf .in)
    done
}

os_get_horizon_sessionid()
{
    local horizon_host=https://$1
    local horizon_domain=$2
    local horizon_user=$3
    local horizon_password=$4

    rm -rf $COOKIE_FILE $LOGIN_PAGE

    #first curl to get the token on cookie file
    $CURL -k -c $COOKIE_FILE -b $COOKIE_FILE --output $LOGIN_PAGE -s "$horizon_host/horizon/auth/login/"

    horizon_region=`cat $LOGIN_PAGE | grep id_region | awk '{print $4}' | awk -F '"' '{print $2}'`
    token=`cat $COOKIE_FILE | grep csrftoken | sed 's/^.*csrftoken\s*//'`

    data="username=$horizon_user&password=$horizon_password&region=$horizon_region&domain=$horizon_domain&csrfmiddlewaretoken=$token"

    #now we can authenticate
    $CURL -k -c $COOKIE_FILE -b $COOKIE_FILE --output /dev/null -s -d "$data" --referer "$horizon_host/horizon/" "$horizon_host/horizon/auth/login/"

    #verify the presence of sessionid
    sessionid=`cat $COOKIE_FILE | grep sessionid | sed 's/^.*sessionid\s*//'`
    echo -n $sessionid
}

os_list_domain_basic()
{
    $OPENSTACK domain list -f value -c Name | grep -v 'heat'
}

os_list_domain()
{
    echo -n $($OPENSTACK domain list -f value -c Name | grep -v 'heat' | tr '\n' ',' | head -c -1)
}

os_list_project_by_domain_basic()
{
    local domain=$1
    $OPENSTACK project list --domain $domain -f value -c Name | grep -v 'service'
}

os_list_project_by_domain()
{
    local domain=$1
    echo -n $($OPENSTACK project list --domain $domain -f value -c Name | grep -v 'service' |  tr '\n' ',' | head -c -1)
}

os_list_local_user_by_domain_project()
{
    local domain=$1
    local tenant=$2
    $OPENSTACK user list -f value -c Name --domain $domain --project $tenant | grep -v "(IAM)\|$RESERVED_USERS"
}

os_user_list()
{
    $OPENSTACK user list -f value -c Name | grep -v "(IAM)\|$RESERVED_USERS"
}

os_get_user_id_by_name()
{
    local user=$1
    echo -n $($OPENSTACK user show $user -f value -c id)
}

os_get_project_id_by_name()
{
    local tenant=$1
    echo -n $($OPENSTACK project show $tenant -f value -c id)
}

os_get_instance_id_by_tenant_and_name()
{
    local tenant=$1
    local instance=$2
    local tenant_id=$(os_get_project_id_by_name $tenant)
    echo -n $(nova list --tenant $tenant_id --fields id,name | grep " $instance " | awk '{print $2}')
}

os_get_instance_name_by_id()
{
    local instance_id=$1
    local status=${2:-ACTIVE}
    $OPENSTACK server list --all-projects --status $status -f json -c ID -c Name | jq --arg instance_id "$instance_id" '.[] | select(.ID==$instance_id)' | jq -r .Name | tr -d '\n'
}

os_get_instance_by_node()
{
    local node=${1:-$HOSTNAME}
    local status=${2:-ACTIVE}
    $OPENSTACK server list --all-projects --status $status --long -f json | jq --arg node "$node" '.[] | select(.Host==$node)' | jq -r .Name
}

os_get_instance_list_by_node()
{
    local node=${1:-$HOSTNAME}
    local status=${2:-ACTIVE}
    $OPENSTACK server list --all-projects --status $status --host $node
}

os_get_instance_count_by_cluster()
{
    for node in $(cubectl node list -r compute -j | jq -r .[].hostname) ; do
        echo "${node}(`os_get_instance_by_node $node | wc -l`)"
    done
}

os_get_instance_name_by_port_id()
{
    local port_id=$1
    local status=${2:-ACTIVE}
    local device_id=$($OPENSTACK port show $port_id -f json | jq -r .device_id | tr -d '\n')
    os_get_instance_name_by_id $device_id $status
}

os_get_auth_url_by_ep_type()
{
    local type=$1
    cat $EP_SNAPSHOT | grep "identity.*$type" | awk '{print $5}' | tr -d '\n'
}

os_get_region()
{
    cat $EP_SNAPSHOT | grep "identity.*public" | awk '{print $2}' | tr -d '\n'
}

os_list_public_net_by_domain()
{
    local domain=$1
    $OPENSTACK network list --external --project-domain $domain -f value -c Name
}

os_list_public_share_net_by_domain()
{
    local domain=$1
    [ -z "$domain" ] || local ARG_DOMAIN="--project-domain $domain"
    $OPENSTACK network list --external $ARG_DOMAIN --share -f value -c Name
}

os_list_private_net_by_domain_project()
{
    local domain=$1
    local tenant=$2
    $OPENSTACK network list --internal --project-domain $domain --project $tenant -f value -c Name
}

os_list_router_by_domain_project()
{
    local domain=$1
    local tenant=$2
    $OPENSTACK router list --project-domain $domain --project $tenant -f value -c Name
}

os_list_flavor()
{
    if [ "$VERBOSE" == "1" ] ; then
        $OPENSTACK flavor list --public -f value -c Name -c VCPUs -c RAM -c Disk | awk '{print "name: "$1", cpu: "$4", mem: "$2"mb, disk: "$3"gb"}'
    else
        $OPENSTACK flavor list --public -f value -c Name
    fi
}

os_list_image()
{
    $OPENSTACK image list -f value -c Name | sort | uniq
}

os_list_keypair_by_user()
{
    local domain=$1
    local tenant=$2
    local user=$3
    local pass=$4

    export OS_USERNAME=$user
    export OS_PASSWORD=$pass
    export OS_PROJECT_NAME=$tenant
    export OS_USER_DOMAIN_NAME=$domain
    export OS_PROJECT_DOMAIN_NAME=$domain
    $OPENSTACK keypair list -f value -c Name
}

os_create_keypair_by_user()
{
    local domain=$1
    local tenant=$2
    local user=$3
    local pass=$4
    local name=$5

    export OS_USERNAME=$user
    export OS_PASSWORD=$pass
    export OS_PROJECT_NAME=$tenant
    export OS_USER_DOMAIN_NAME=$domain
    export OS_PROJECT_DOMAIN_NAME=$domain
    $OPENSTACK keypair create $name
}

os_list_sg_by_domain_project()
{
    local domain=$1
    local tenant=$2
    $OPENSTACK security group list --project-domain $domain --project $tenant -f value -c Name
}

os_get_network_id_by_domain_project_network()
{
    local domain=$1
    local tenant=$2
    local network=$3
    $OPENSTACK network list --project-domain $domain --project $tenant -f value -c ID -c Name | grep $network | awk '{print $1}' | tr -d '\n'
}

os_get_subnet_id_by_domain_project_network()
{
    local domain=$1
    local tenant=$2
    local network=$3
    $OPENSTACK network show $network -f json | jq -r .subnets[0] | tr -d '\n'
}

os_get_router_id_by_domain_project_router()
{
    local domain=$1
    local tenant=$2
    local router=$3
    $OPENSTACK router list --project-domain $domain --project $tenant -f value -c ID -c Name | grep $router | awk '{print $1}' | tr -d '\n'
}

os_neutron_agent_remove()
{
    local host=$1
    local binary=$2
    local agent_id=$($OPENSTACK network agent list -f value -c ID -c Host -c Binary | grep "$host.*$binary" | awk '{print $1}')
    if [ -n "$agent_id" ] ; then
        $OPENSTACK network agent delete $agent_id
    fi
}

os_neutron_worker_scale()
{
    is_control_node || return 0

    for CPU in $(for P in `pgrep -f "neutron-server.*api worker"` ; do ! systemctl status neutron-server --no-pager | grep -q $P || ps --no-headers -p $P -o %cpu ; done) ; do
        if [ -n $CPU -a ${CPU%.*} -ge 90 ] ; then
            eval $(grep api_workers /etc/neutron/neutron.conf | sed "s/ //g")
            local TH=$(echo "$(cat /proc/cpuinfo | grep processor | wc -l) / 2" | bc)
            if [ $((api_workers++)) -le $TH ] ; then
                sed -i "s/^api_workers.*/api_workers = $api_workers/" /etc/neutron/neutron.conf
                systemctl restart neutron-server
                break
            fi
        fi
    done
}

os_instance_ha_helper()
{
    # Do not intervene bootstrap processes
    [ -e /run/cube_commit_done ] >/dev/null 2>&1 || return 0
    # Proceed only when instance_ha is enabled
    [ $(timeout $SRVSTO $OPENSTACK segment list -f value -c name | wc -l) -ne 0 ] || return 0
    # Do nothing if another node is taking actions
    local helping=/mnt/cephfs/nova/instance_ha.helping
    local cmp_lst=$(timeout $SRVSTO $OPENSTACK compute service list -f json)
    local down_host=$(echo $cmp_lst | jq -r '.[] | select (.Binary == "nova-compute" and .Status == "disabled" and .State == "down").Host' | sort -u)
    if [ -e $helping ] ; then
        # Remove stale lock if it exceeds 60 min
        duration=$(echo $(( ($(date +%s) - $(stat $helping -c %Y)) / 60 )))
        [ ${duration:-60} -lt 60 ] || rm -f $helping
        [ "x$down_host" != "x$(cat $helping)" ] || rm -f $helping
        return 0
    fi

    hostname > $helping # mutex lock

    # Fail over Ceph dashboard which doesn't work automatically with new active ceph-mgr
    # SDK auto repair cannot help because when inst-ha takes place, not all nodes complete bootstrap
    local active=$($CEPH mgr stat -f json | jq -r .active_name)
    if ! timeout $SRVSTO curl -I -k https://${active}:7442/ceph/ 2>/dev/null | grep -q "200 OK" ; then
        $CEPH mgr module disable dashboard
        echo "ceph mgr module disable dashboard" >> $helping
        $CEPH mgr module enable dashboard
        echo "ceph mgr module enable dashboard" >> $helping
    fi
    mountpoint -- $CEPHFS_STORE_DIR  | grep -q "is a mountpoint" || timeout $SRVTO cubectl node exec -pn "$HEX_SDK ceph_mount_cephfs"

    local vip=/mnt/cephfs/nova/cluster.vip
    if [ ! -e $vip ] ; then
        timeout $SRVSTO $HEX_SDK -f json health_vip_report | jq -r .description > $vip
    else
        old_vip=$(cat $vip)
        new_vip=$(timeout $SRVSTO $HEX_SDK -f json health_vip_report | jq -r .description)
        if [ "x$old_vip" != "x$new_vip" ] ; then
            echo "old_vip=$old_vip" >> $helping
            echo "new_vip=$new_vip" >> $helping
            timeout $SRVTO $OPENSTACK network agent list -f json -c ID -c Alive | jq -r ".[] | select(.Alive == false).ID" | xargs -i $OPENSTACK network agent delete {}
            echo "removed non active network agent" >> $helping
            timeout $SRVTO cubectl node exec -r control -pn systemctl restart neutron-server
            echo "cubectl node exec -r control -pn systemctl restart neutron-server" >> $helping
            timeout $SRVTO cubectl node exec -r compute -pn "$OPENSTACK network agent list --host \$HOSTNAME | grep -q 'OVN Metadata .* :-)' || systemctl restart neutron-ovn-metadata-agent"e
            echo "cubectl node exec -r compute -pn systemctl restart neutron-ovn-metadata-agent" >> $helping
            timeout $SRVTO cubectl node exec -r compute -pn "$OPENSTACK network agent list --host \$HOSTNAME | grep -q 'VPN .* :-)' || systemctl restart neutron-ovn-vpn-agent"
            echdo "cubectl node exec -r compute -pn systemctl restart neutron-ovn-vpn-agent" >> $helping
            echo $new_vip > $vip
        else
            local NET_LST=$(timeout $SRVSTO $OPENSTACK network agent list -f json)
            for node in $(echo $NET_LST | jq -r '.[] | select (.Alive == false and .State == true and ."Agent Type" == "VPN Agent").Host' | sort -u) ; do
                if [ "x$node" != "x$down_host" ] ; then
                    timeout $SRVSTO $HEX_SDK remote_run $node systemctl restart neutron-ovn-vpn-agent
                    echo "$HEX_SDK remote_run $node systemctl restart neutron-ovn-vpn-agent" >> $helping
                fi
            done
            for node in $(echo $NET_LST | jq -r '.[] | select (.Alive == false and .State == true and ."Agent Type" == "OVN Metadata agent").Host' | sort -u) ; do
                if [ "x$node" != "x$down_host" ] ; then
                    timeout $SRVSTO $HEX_SDK remote_run $node systemctl restart neutron-ovn-metadata-agent
                    echo "$HEX_SDK remote_run $node systemctl restart neutron-ovn-metadata-agent" >> $helping
                fi
            done
        fi
    fi

    # Revive nova compute if it is enabled but service is down
    for node in $(echo $cmp_lst | jq -r '.[] | select (.Binary == "nova-compute" and .Status == "enabled" and .State == "down").Host' | sort -u) ; do
        timeout $SRVTO $HEX_SDK remote_run $node systemctl restart openstack-nova-compute
        echo "$HEX_SDK remote_run $node systemctl restart openstack-nova-compute" >> $helping
    done

    local notify_log=/mnt/cephfs/nova/notification.log
    local new_notify=$(timeout $SRVTO $OPENSTACK notification list -f value | grep COMPUTE_HOST | head -1)
    if [ ! -e $notify_log ] ; then
        echo $new_notify > $notify_log
    else
        if echo $new_notify | grep -q "finished COMPUTE_HOST" ; then
            echo $new_notify > $notify_log
        elif echo $new_notify | grep -q -e "new COMPUTE_HOST" -e "running COMPUTE_HOST" ; then
            :
        else
            local old_notify="$(head -1 $notify_log)"
            if [ "x$new_notify" = "x$old_notify" ] ; then
                fix_cnt="$(tail -1 $notify_log | cut -d":" -f1)"
                case $fix_cnt in
                    0|1|2|3|4|5|6|7|8|9)
                        ((fix_cnt++))
                        echo "${fix_cnt}:$HOSTNAME" >> $notify_log
                        ;;
                    *)
                        ;;
                esac
            else
                echo $new_notify > $notify_log
                fix_cnt=1
                echo "${fix_cnt}:$HOSTNAME" >> $notify_log
            fi
            if [ $fix_cnt -lt 10 ] ; then
                notify_id=$(echo $new_notify | cut -d" " -f1)
                local notify_detail=$(timeout $SRVSTO $OPENSTACK notification show $notify_id -f json)
                local srv_lst=$(timeout $SRVSTO $OPENSTACK server list --long --all-projects -f json)
                for ID in $(echo $srv_lst | jq -r .[].ID) ; do
                    local cur_status=$(echo $srv_lst | jq -r ".[] | select(.ID == \"${ID}\").\"Status\"")
                    local cur_host=$(echo $srv_lst | jq -r ".[] | select(.ID == \"${ID}\").Host")
                    if [ "x$cur_host" = "x$down_host" ] ; then
                        if [ "x$cur_status" = "xERROR" ] ; then
                            timeout $SRVSTO $HEX_SDK os_nova_instance_reset $ID
                            echo "$HEX_SDK os_nova_instance_reset $ID" >> $helping
                        fi
                        timeout $SRVTO nova evacuate $ID
                        echo "nova evacuate $ID" >> $helping
                    else
                        if [ "x$cur_status" = "xERROR" -o "x$cur_status" = "xREBUILD" ] ; then
                            timeout $SRVSTO $HEX_SDK os_nova_instance_reset $ID
                            echo "$HEX_SDK os_nova_instance_reset $ID" >> $helping
                            timeout $SRVSTO $HEX_SDK os_nova_instance_hardreboot $ID
                            echo "$HEX_SDK os_nova_instance_hardreboot $ID" >> $helping
                        fi
                    fi
                done
            fi
        fi
    fi
    rm -f $helping              # mutex unlock
}

os_get_network_id_by_tenant_and_name()
{
    local tenant=$1
    local network=$2
    local tenant_id=$(os_get_project_id_by_name $tenant)
    echo -n $($OPENSTACK network list --project $tenant_id -c ID -c Name | grep " $network " | awk '{print $2}')
}

os_list_network_by_project_basic()
{
    local tenant=$1
    local tid=$(os_get_project_id_by_name $tenant)
    $OPENSTACK network list --project $tid -f value -c Name | grep -v 'lb-mgmt-net\|manila_service_network'
}

os_get_network_alloc_pools_by_tenant_and_name()
{
    local tenant=$1
    local network=$2
    local tid=$(os_get_project_id_by_name $tenant)
    local subnet_id=$($OPENSTACK network list --project $tid -c Name -c Subnets | grep " $network " | awk '{print $4}')
    if [ -z "$subnet_id" ] ; then
        # shared network created in admin project
        subnet_id=$($OPENSTACK network list -c Name -c Subnets | grep " $network " | awk '{print $4}')
    fi
    if [ -n "$subnet_id" ] ; then
        $OPENSTACK subnet show $subnet_id | awk '/ allocation_pools /{print $4}' | tr -d '\n'
    fi
}

os_list_provider_network_basic()
{
    $OPENSTACK network list --provider-physical-network provider -f value -c Name
}

os_list_router_by_project_basic()
{
    local tenant=$1
    local tid=$(os_get_project_id_by_name $tenant)
    $OPENSTACK router list --project $tid -f value -c Name
}

os_list_loadbalancer_by_project_basic()
{
    local tenant=$1
    local tid=$(os_get_project_id_by_name $tenant)
    $OPENSTACK loadbalancer list --project $tid -f value -c name
}

os_neutron_network_opt_list()
{
    neutron net-update --help 2>/dev/null | grep "^  --" | awk -F'--' '{print $2}' | awk '{print $1}'
}

os_neutron_network_update()
{
    local tenant=$1
    local network=$2
    local type=$3
    local value=$4
    local nid=$(os_get_network_id_by_tenant_and_name $tenant $network)
    neutron net-update $nid --$type $value 2>/dev/null
}

os_neutron_network_show()
{
    local tenant=$1
    local network=$2
    local nid=$(os_get_network_id_by_tenant_and_name $tenant $network)
    $OPENSTACK network show $nid
}

os_neutron_quota_list()
{
    neutron quota-update --help 2>/dev/null | grep "The limit" -B 1 | grep "^  --" | awk -F'--' '{print $2}' | awk '{print $1}'
}

os_neutron_quota_update()
{
    local tenant=$1
    local type=$2
    local value=$3
    local tid=$(os_get_project_id_by_name $tenant)
    neutron quota-update --tenant-id $tid --$type $value 2>/dev/null
}

os_neutron_quota_show()
{
    local tenant=$1
    local tid=$(os_get_project_id_by_name $tenant)
    neutron quota-show --tenant-id $tid 2>/dev/null
}

os_neutron_agent_cache_renew()
{
    timeout 30 $OPENSTACK network agent list 2>/dev/null > $NEUTRON_AGENT_CACHE
}

os_neutron_agent_list()
{
    local output=""

    if [ -f "$NEUTRON_AGENT_CACHE" ] ; then
        local stats=$(cat $NEUTRON_AGENT_CACHE | grep ovn)
        if [ -z "$stats" ] ; then
            echo "{}"
            return
        fi
    else
        echo "{}"
        return
    fi

    while IFS= read -r line ; do
        local id=$(echo $line | awk -F'|' '{print $2}' | awk '{$1=$1;print}')
        local agent_type=$(echo $line | awk -F'|' '{print $3}' | awk '{$1=$1;print}')
        local host=$(echo $line | awk -F'|' '{print $4}' | awk '{$1=$1;print}')
        local alive=$(echo $line | awk -F'|' '{print $6}' | awk '{$1=$1;print}')
        if [ "$alive" == ":-)" ] ; then
            alive="true"
        else
            alive="false"
        fi
        local admin_state_up=$(echo $line | awk -F'|' '{print $7}' | awk '{$1=$1;print}')
        if [ "$state" == "UP" ] ; then
            admin_state_up="true"
        else
            admin_state_up="false"
        fi
        local binary=$(echo $line | awk -F'|' '{print $8}' | awk '{$1=$1;print}')
        local item="\"$id\": { \"binary\": \"$binary\", \"host\": \"$host\", \"start_flag\": true, \"agent_type\": \"$agent_type\", \"id\": \"$id\", \"alive\": $alive, \"admin_state_up\": $admin_state_up }"
        if [ -z "$output" ] ; then
            output="$item"
        else
            output="$output,$item"
        fi
    done <<< "$(cat $NEUTRON_AGENT_CACHE | grep ovn)"

    echo "{ $output }"
}

os_neutron_router_vpn_status()
{
    local rid=$1

    ip netns exec qvpn-$rid neutron-vpn-netns-wrapper --mount_paths=/etc:/var/lib/neutron/ipsec/$rid/etc,/var/run:/var/lib/neutron/ipsec/$rid/var/run --rootwrap_config=/etc/neutron/rootwrap.conf --cmd=ipsec,whack,--status,--rundir,/var/run
}

os_get_router_id_by_tenant_and_name()
{
    local tenant=$1
    local name=$2
    echo -n $($OPENSTACK router list --project $tenant -f value -c ID -c Name | grep $name | awk '{print $1}')
}

os_set_router_ext_gateway()
{
    local tenant=$1
    local router=$2
    local ipaddr=$3
    local router_id=$(os_get_router_id_by_tenant_and_name $tenant $router)
    local gateway_info=$($OPENSTACK router show $router -f json | jq .external_gateway_info)
    local ext_net_id=$(echo $gateway_info | jq -r ".network_id")
    local sub_net_id=$(echo $gateway_info | jq -r ".external_fixed_ips[0].subnet_id")
    neutron router-gateway-set --fixed-ip subnet_id=$sub_net_id,ip_address=$ipaddr $router_id $ext_net_id > /dev/null 2>&1
}

os_remove_floating_ip()
{
    local instance=$1
    local ipaddr=$2
    $OPENSTACK server remove floating ip $instance $ipaddr
    $OPENSTACK floating ip delete $ipaddr
}

os_del_all_tenant_fip()
{
    readarray map_array <<<"$($OPENSTACK server list --all-projects -c ID -c Networks -f value)"
    declare -p map_array > /dev/null
    for map_entry in "${map_array[@]}" ; do
        local instance_id=$(echo $map_entry | awk '{print $1}')
        local networks=$(echo $map_entry | awk '{for (i = 2 ; i <= NF ; i++) printf $i}')
        IFS=';' read -a net_array <<<"$networks"
        declare -p net_array > /dev/null
        for net_entry in "${net_array[@]}" ; do
            IFS=',' read -a fip_array <<<"$net_entry"
            declare -p fip_array > /dev/null
            for i in "${!fip_array[@]}" ; do
                if (( $i > 0 )) ; then
                    os_remove_floating_ip $instance_id ${fip_array[$i]}
                fi
            done
        done
    done
}

os_cinder_quota_list()
{
    cinder help quota-update 2>/dev/null | grep "^  --" | awk -F'--' '{print $2}' | awk '{print $1}' | grep -v "skip-validation"
}

os_cinder_quota_update()
{
    local tenant=$1
    local type=$2
    local value=$3
    local tid=$(os_get_project_id_by_name $tenant)
    cinder quota-update --$type $value $tid 2>/dev/null
}

os_cinder_quota_show()
{
    local tenant=$1
    local tid=$(os_get_project_id_by_name $tenant)
    cinder quota-show $tid 2>/dev/null
}

os_list_volume_by_tenant_basic()
{
    local tenant=$1

    if [ -n "$tenant" ] ; then
        local tid=$(os_get_project_id_by_name $tenant 2>/dev/null)
        local proj_flag="--project $tid"
    else
        local proj_flag="--all-projects"
    fi

    if [ "$VERBOSE" == "1" ] ; then
        local vols=$($OPENSTACK volume list $proj_flag -f json)
        local ins=$($OPENSTACK server list $proj_flag -f value -c ID -c Name)
        local idx=0
        for vid in $(echo $vols | jq -r .[].ID) ; do
            local status=$(echo $vols | jq -r --argjson i $idx '.[$i].Status')
            local size=$(echo $vols | jq -r --argjson i $idx '.[$i].Size')
            printf "volume: %s, status: %s, size: %sGB" $vid $status $size
            if [ "$status" == "in-use" ] ; then
                local device=$(echo $vols | jq -r --argjson i $idx '.[$i]."Attached to"[0].device')
                local srv_id=$(echo $vols | jq -r --argjson i $idx '.[$i]."Attached to"[0].server_id')
                local host=$(echo "$ins" | grep $srv_id | awk '{print $2}')
                printf ", attach: %s on %s" $device $host
            fi
            printf "\n"
            idx=$(( idx + 1 ))
        done
    else
        $OPENSTACK volume list $proj_flag -f value -c ID
    fi
}

# params:
# $1: volume meta file
# $*: volume id space separated list (required)
os_export_volume()
{
    local vol_meta_file=$1
    shift

    local vol_ids=$*

    [ -z "$vol_ids" ] && Error "no volume is given"

    readarray -t vol_array <<<"$vol_ids "
    declare -p vol_array > /dev/null
    for vol_id in ${vol_array[@]} ; do
        local vol_temp=$(MakeTemp)
        /usr/bin/mysqldump --no-create-db --no-create-info --replace cinder volumes -w"id='$vol_id'" > $vol_temp

        local user_id=$(cat $vol_temp | grep REPLACE | awk -F',' '{print $7}' | sed "s/'//g")
        local proj_id=$(cat $vol_temp | grep REPLACE | awk -F',' '{print $8}' | sed "s/'//g")
        local host=$(cat $vol_temp | grep REPLACE | awk -F',' '{print $9}' | sed "s/'//g")
        local type_id=$(cat $vol_temp | grep REPLACE | awk -F',' '{print $22}' | sed "s/'//g")
        local service_uuid=$(cat $vol_temp | grep REPLACE | awk -F',' '{print $38}' | sed "s/'//g")
        cat $vol_temp | sed -e "s/${user_id}/%user_id%/g" -e "s/${proj_id}/%proj_id%/g" -e "s/${host}/%host%/g" -e "s/${type_id}/%type_id%/g" \
                            -e "s/${service_uuid}/%service_uuid%/g" -e "s/in-use/available/g" -e "s/attached/detached/g" >> $vol_meta_file
        /usr/bin/mysqldump --no-create-db --no-create-info --replace \
                           cinder volume_admin_metadata volume_glance_metadata volume_metadata -w"volume_id='$vol_id'" >> $vol_meta_file
    done
}

# params:
# $1: user name (required)
# $2: project name (required)
# $2: host (required)
# $3: volume meta file (required)
os_import_volume()
{
    local user_id=$(os_get_user_id_by_name $1)
    local proj_id=$(os_get_project_id_by_name $2)
    local host=$3
    local type_id=$($OPENSTACK volume type show $4 | awk '/ id /{print $4}')
    local service_uuid=$(/usr/bin/mysql -u root -D cinder -e "select uuid from services where topic = 'cinder-volume'" -E | grep uuid | awk '{print $2}')
    local vol_meta_file=$5
    local vol_sql_file=$(MakeTemp)

    cat $vol_meta_file | sed -e "s/%user_id%/${user_id}/g" -e "s/%proj_id%/${proj_id}/g" -e "s/%host%/${host}/g" -e "s/%type_id%/${type_id}/g" -e "s/%service_uuid%/${service_uuid}/g" > $vol_sql_file
    mysql cinder < $vol_sql_file
}

os_imported_volume_delete()
{
    local volume_id=$1

    /usr/bin/mysql -u root -D cinder -e "delete from volume_admin_metadata where volume_id='$volume_id'"
    /usr/bin/mysql -u root -D cinder -e "delete from volume_glance_metadata where volume_id='$volume_id'"
    /usr/bin/mysql -u root -D cinder -e "delete from volume_attachment where volume_id='$volume_id'"
    /usr/bin/mysql -u root -D cinder -e "delete from volumes where id='$volume_id'"
}

os_volume_meta_sync()
{
    local host=$1
    local pass=$2
    local vol_id=$3
    local vol_info=$($OPENSTACK volume show $vol_id --format json)
    local user_id=$(echo "$vol_info" | jq -r ".user_id")
    local proj_id=$(echo "$vol_info" | jq -r ".\"os-vol-tenant-attr:tenant_id\"")
    local user=$($OPENSTACK user list -f value | grep "$user_id " | awk '{print $2}')
    local proj=$($OPENSTACK project list -f value | grep "$proj_id " | awk '{print $2}')
    if [ -n "$host" -a -n "$pass" -a -n "$vol_id" -a -n "$user" -a -n "$proj" ] ; then
        local vol_meta_file=$(MakeTemp)
        os_export_volume $vol_meta_file $vol_id
        if ! sshpass -p "$pass" scp $vol_meta_file root@$host:/tmp 2>/dev/null ; then
            echo "faided to copy volume metadata to $host. make sure password is correct"
            return 2
        fi
        if ! sshpass -p "$pass" ssh root@$host $HEX_SDK os_import_volume $user $proj "cube@ceph#ceph" "CubeStorage" $vol_meta_file 2>/dev/null ; then
            echo "faided to import volume meta on $host"
            return 3
        fi
        sshpass -p "$pass" ssh root@$host rm -f $vol_meta_file 2>/dev/null
    else
        echo "usage: os_volume_meta_sync <host> <pass> <vol_id>"
        return 1
    fi
}

os_image_list()
{
    local projects=$($OPENSTACK project list --domain default -f value | grep -v service)
    local images=$($OPENSTACK image list --long -f json)

    local o="{"
    for id in $(echo "$projects" | awk '{print $1}') ; do
        local name=$(echo "$projects" | grep $id | awk '{print $2}')
        local list=$(echo $images | jq --arg ID "$id" '[ .[] | select( .Project == $ID ) ]')
        o="$o \"$name\": $list,"
    done
    o="$o \"service\": []}"
    echo "$o" | jq -c .
}

os_image_delete()
{
    $OPENSTACK image delete $1
}

os_image_import_with_attrs()
{
    local type=$1
    local dir=$2
    local file=$3
    local name=$4
    local domain=$5
    local tenant=$6
    local visibility=$7
    local pool=$8

    local flags="--project-domain $domain --project $tenant --$visibility"

    if [ "$type" == "ide" ] ; then
        os_ide_image_import "$dir" "$file" "$name" "$flags" "$pool"
    elif [ "$type" == "efi" ] ; then
        os_efi_image_import "$dir" "$file" "$name" "$flags" "$pool"
    else
        os_image_import "$dir" "$file" "$name" "$flags" "$pool"
    fi
}

# params:
# $1: file dir (required)
# $2: file name  (required)
# $3: image name (required)
os_image_import()
{
    local dir=$1
    local file=$2
    local IMG=$dir/$file
    local name=$3
    local flags=${4:---public}
    local pool=${5:-glance-images}
    local properties=${6:---property hw_disk_bus=scsi --property hw_scsi_model=virtio-scsi --property hw_machine_type=q35 --property hw_video_model=vga}
    properties+=" --property hw_qemu_guest_agent=yes --property os_require_quiesce=yes"
    properties+=" --property hw_input_bus=virtio"

    if [[ $(qemu-img info $IMG | grep "file format") =~ raw ]] ; then
        local img_name=$IMG
    else
        local img_siz=$(qemu-img info $IMG | grep "^virtual size: " | grep -o "(.*bytes)" | grep -Eo "[0-9]+")
        local tmp_free=$(df /tmp | awk 'NR==2 {print $4}')
        local spc_free=$(df $dir | awk 'NR==2 {print $4}')

        if [ $tmp_free -gt $((img_siz / 1024)) ] ; then
            local img_raw=$(mktemp -u /tmp/${file##*/}_XXXX.raw)
        elif mount | grep $dir | grep -q 'ro,' ; then
            local img_raw=$(mktemp -u $CEPHFS_GLANCE_DIR/${file##*/}_XXXX.raw)
        elif [ $spc_free -gt $((img_siz / 1024)) ] ; then
            local img_raw=$(mktemp -u $dir/${file##*/}_XXXX.raw)
        else
            local img_raw=$(mktemp -u $CEPHFS_GLANCE_DIR/${file##*/}_XXXX.raw)
        fi

        echo "[$(date +"%T")] Converting image to RAW format ... "
        qemu-img convert -p -O raw $IMG $img_raw
        local img_name=$img_raw
    fi

    echo "[$(date +"%T")] Creating image $name ..."
    if [ "x$pool" = "xglance-images" ] ; then
        openstack image create --disk-format raw --container-format bare $flags --file $img_name $properties --progress $name -f value -c id
    else
        rbd --id cinder import $img_name ${BUILTIN_BACKPOOL}/$name
        $OPENSTACK role add --user admin_cli --project $(echo $flags | grep -o "[-][-]project .* " | cut -d" " -f2) admin
        local vol_id=$(cinder $(echo $flags | sed -e "s/--project-domain/--os-project-domain-name/" -e "s/--project/--os-project-name/" -e "s/--public//") manage --bootable --name $name cube@ceph#ceph $name 2>/dev/null | grep " id" | cut -d"|" -f3)
        $OPENSTACK volume set $(echo $properties | sed "s/--property/--image-property/g") ${vol_id:-NOSUCHVOLID}
    fi
    echo "[$(date +"%T")] Finished creating image $name"

    [ -z $img_raw ] || rm -f $img_raw
}

os_extpack_image_mount()
{
    local dir=${1:-$CEPHFS_GLANCE_DIR}

    for ext in $(ls -1 ${dir}/*.ext 2>/dev/null) ; do
        local ext_dir=${ext%.ext}
        mkdir -p $ext_dir
        mount -o ro $ext $ext_dir 2>/dev/null || true
    done
}

os_extpack_image_umount()
{
    local dir=${1:-$CEPHFS_GLANCE_DIR}

    for ext in $(ls  -1 ${dir}/*.ext 2>/dev/null) ; do
        local ext_dir=${ext%.ext}
        umount $ext_dir 2>/dev/null || true
        rmdir $ext_dir 2>/dev/null || true
    done
}

os_extpack_image_import()
{
    local dir=$1
    local ext_folder=${2%%:*}
    declare -A PIDS

    pushd $dir/$ext_folder >/dev/null
    for PREFIX in ipa-kernel- ipa-initramfs- amphora- manila- k8s- appfw- rancher-cluster- ; do
        local img=$(ls -1 ${PREFIX}*.{qcow2,vdi,vhd,vhdx,vmdk,ami,raw,img,kernel,tgz} 2>/dev/null | head -1)
        [ -n "$img" ] || continue
        case $PREFIX in
            amphora-)
                os_octavia_image_import ${dir}/${ext_folder} $img
                ;;
            manila-)
                os_manila_image_import ${dir}/${ext_folder} $img
                ;;
            ipa-kernel-)
                os_ironic_deploy_kernel_import ${dir}/${ext_folder} $img
                ;;
            ipa-initramfs-)
                os_ironic_deploy_initramfs_import ${dir}/${ext_folder} $img
                ;;
            k8s-|rancher-cluster-)
                local olds=$($OPENSTACK image list -f value --property name=${img%.*} -c ID)
                if [ -n "$olds" ] ; then
                    $OPENSTACK image delete $olds 2>/dev/null
                fi
                os_image_import_with_attrs default $dir/${ext_folder} $img ${img%.*} default admin public
                ;;
            appfw-)
                local appfw_dir=/opt/appfw/images/
                cubectl node exec -r control -pn "mkdir -p $appfw_dir"
                ( tar xf $dir/$ext_folder/$img -C $appfw_dir ; cubectl node rsync -r control $appfw_dir )
                ;;
            *) echo "Unknown builtin image prefix: $PREFIX" ;;
        esac
    done
    popd >/dev/null

    $OPENSTACK image list
    os_extpack_image_umount $dir
}

# params:
# $1: file dir (required)
# $2: file name  (required)
# $3: image name (required)
os_ide_image_import()
{
    local dir=$1
    local file=$2
    local name=$3
    local flags=${4:---public}
    local pool=${5:-glance-images}

    os_image_import "$dir" "$file" "$name" "$flags" "$pool" "--property hw_disk_bus=ide"
}

# params:
# $1: file dir (required)
# $2: file name  (required)
# $3: image name (required)
os_efi_image_import()
{
    local dir=$1
    local file=$2
    local name=$3
    local flags=${4:---public}
    local pool=${5:-glance-images}
    local properties="--property hw_disk_bus=sata"
    properties+=" --property hw_firmware_type=uefi"
    properties+=" --property hw_machine_type=q35"
    properties+=" --property os_secure_boot=optional"
    properties+=" --property hw_vif_model=e1000"
    properties+=" --property hw_input_bus=virtio"

    os_image_import "$dir" "$file" "$name" "$flags" "$pool" "$properties"
}

os_image_import_list()
{
    local dir=${1:-$CEPHFS_GLANCE_DIR}
    local prefix=$2

    cd $dir
    ls -la ${prefix}*.{qcow2,vdi,vhd,vhdx,vmdk,ami,raw,img,kernel} 2>/dev/null | awk '{print $9}'
    ls -la */${prefix}*.{qcow2,vdi,vhd,vhdx,vmdk,ami,raw,img,kernel} 2>/dev/null | awk '{print $9}'
}

os_image_import_extpack_list()
{
    local dir=${1:-$CEPHFS_GLANCE_DIR}

    for ext in $(ls -1 ${dir}/*.ext 2>/dev/null) ; do
        local ext_dir=${ext%.ext}
        echo -n "${ext_dir##*/}: "
        pushd $ext_dir >/dev/null
        ls *.{qcow2,vdi,vhd,vhdx,vmdk,ami,raw,img,kernel,tgz} 2>/dev/null | xargs
        popd >/dev/null
    done
}

os_volume_type_create()
{
    local name=$1
    local backend_name=$2

    if $($OPENSTACK volume type list --long --format value -c Name | grep -q $name) ; then
        echo "volume type $name already exists"
    else
        $OPENSTACK volume type create $name
        $OPENSTACK volume type set $name --property volume_backend_name=$backend_name
    fi
}

os_volume_type_clear()
{
    local backend_list=${1:-CubeStorage}

    readarray type_array <<<"$($OPENSTACK volume type list --long -c Name -f value)"
    declare -p type_array > /dev/null
    for type in "${type_array[@]}" ; do
        if $(echo $backend_list __DEFAULT__ | grep -q $type) ; then
            # required type
            :
        else
            echo "delete volume type $type"
            $OPENSTACK volume type delete $type
        fi
    done
}

os_endpoint_snapshot_create()
{
    local timeout=${1:-30}

    local i=0
    while [ $i -lt $timeout ] ; do
        $OPENSTACK endpoint list -f value -c ID -c Region -c "Service Type" -c Interface -c URL > $EP_SNAPSHOT
        if [ $(cat $EP_SNAPSHOT | wc -l) -gt 3 ] ; then
            echo "created endpoint snapshot successfully"
            return 0
        else
            echo "failed to create endpoint snapshot. retry again"
            sleep 1
        fi
        i=$(expr $i + 1)
    done
    rm -f $EP_SNAPSHOT
    return -1
}

os_keystone_endpoint_update()
{
    local pub=$1
    local adm=$2
    local intr=$3

    local pub_id=$(cat $EP_SNAPSHOT | grep " identity " | grep public | awk '{print $1}' | tr -d '\n')
    local admin_id=$(cat $EP_SNAPSHOT | grep " identity " | grep admin | awk '{print $1}' | tr -d '\n')
    local intr_id=$(cat $EP_SNAPSHOT | grep " identity " | grep internal | awk '{print $1}' | tr -d '\n')
    /usr/bin/mysql -u root -D keystone -e "UPDATE endpoint set url='$pub' where id='$pub_id'"
    /usr/bin/mysql -u root -D keystone -e "UPDATE endpoint set url='$adm' where id='$admin_id'"
    /usr/bin/mysql -u root -D keystone -e "UPDATE endpoint set url='$intr' where id='$intr_id'"
}

os_keystone_idp_config()
{
    local shared_id=$1
    local fed_dir=/etc/httpd/federation
    mkdir -p $fed_dir && rm -f $fed_dir/*
    cd $fed_dir && /usr/libexec/mod_auth_mellon/mellon_create_metadata.sh https://$shared_id:5443/v3/mellon/metadata https://$shared_id:5443/v3/mellon/
    mv $fed_dir/https_${shared_id}_5443_v3_mellon_metadata.key $fed_dir/v3.key
    mv $fed_dir/https_${shared_id}_5443_v3_mellon_metadata.cert $fed_dir/v3.cert
    mv $fed_dir/https_${shared_id}_5443_v3_mellon_metadata.xml $fed_dir/v3.xml
    cat $fed_dir/v3.xml | xmllint --format - > /etc/keycloak/keystone_sp_metadata.xml
    cp -f /etc/httpd/conf.d/v3_mellon_keycloak_master.conf.def /etc/httpd/conf.d/v3_mellon_keycloak_master.conf
    $TERRAFORM_CUBE apply -auto-approve -target=module.keycloak_keystone -var cube_controller=$shared_id >/dev/null
}

os_endpoint_url_set()
{
    local srv=$1
    local rgn=$2
    local interface=$3
    local url=$4
    local old_url=$(cat $EP_SNAPSHOT | grep " $srv " | grep $interface | awk '{print $5}' | uniq)
    if [ "$url" != "$old_url" ] ; then
        readarray id_array <<<"$(cat $EP_SNAPSHOT | grep " $srv " | grep $interface | awk '{print $1}')"
        declare -p id_array > /dev/null
        for id in "${id_array[@]}" ; do
            $OPENSTACK endpoint set --region $rgn --service $srv --interface $interface --url $url $id
        done
    fi
}

os_endpoint_update()
{
    local srv=$1
    local rgn=$2
    local pub=$3
    local adm=$4
    local intr=$5

    if [ -f $EP_SNAPSHOT -a $(cat $EP_SNAPSHOT 2>/dev/null | grep $srv | wc -l) -ge 3 ] ; then
        #update
        os_endpoint_url_set $srv $rgn public $pub
        os_endpoint_url_set $srv $rgn admin $adm
        os_endpoint_url_set $srv $rgn internal $intr
    else
        #create
        $OPENSTACK endpoint create --region $rgn $srv public $pub
        $OPENSTACK endpoint create --region $rgn $srv admin $adm
        $OPENSTACK endpoint create --region $rgn $srv internal $intr
    fi
}

os_nova_service_remove()
{
    local host=$1
    local binary=$2
    local srv_ironic_id=$($OPENSTACK compute service list -f value -c ID -c Host -c Binary | grep "$binary.*$host-ironic" | awk '{print $1}')
    if [ -n "$srv_ironic_id" ] ; then
        /usr/bin/mysql -u root -D nova -e "delete from services where id = '$srv_ironic_id'"
    fi
    local srv_id=$($OPENSTACK compute service list -f value -c ID -c Host -c Binary | grep "$binary.*$host" | awk '{print $1}')
    if [ -n "$srv_id" ] ; then
        $OPENSTACK compute service set --disable $host $binary
        $OPENSTACK compute service delete $srv_id
    fi
}

os_nova_cell_update()
{
    local cell0_db=$1
    readarray uuid_array <<<"$(nova-manage cell_v2 list_cells | grep cell | awk '{print $4}')"
    declare -p uuid_array > /dev/null
    for uuid in "${uuid_array[@]}" ; do
        local id=$(echo $uuid | tr -d '\n')
        if [ "$id" == "00000000-0000-0000-0000-000000000000" ] ; then
            nova-manage cell_v2 update_cell --cell_uuid $id --transport-url "none:///" --database_connection "$cell0_db"
        else
            nova-manage cell_v2 update_cell --cell_uuid $id
        fi
    done
}

os_nova_non_active_server_list()
{
    local list=$($OPENSTACK server list --all-project -f value -c Name -c ID -c Status | grep -v -e " ACTIVE" -e " SHUTOFF")

    if [ -n "$list" ] ; then
        if [ "$VERBOSE" == "1" ] ; then
            echo "$list" | awk '{printf "%-60s (ID: %s, Status: %s)\n", $2, $1, $3}'
            echo "all"
        else
            echo "$list" | awk '{print $1}'
            echo "$list" | awk '{print $1}' | tr '\n' ' '
        fi
    fi
}

os_nova_server_list()
{
    local list=$($OPENSTACK server list --all-project -f value -c Name -c ID)

    if [ -n "$list" ] ; then
        if [ "$VERBOSE" == "1" ] ; then
            echo "$list"
        else
            echo "$list" | awk '{print $1}'
        fi
    fi
}

os_nova_instance_reset()
{
    local instance_ids=$@

    nova reset-state --active $instance_ids
}

os_nova_instance_hardreboot()
{
    local instance_ids=$@

    for server_id in $instance_ids ; do
        $OPENSTACK server reboot --hard $server_id
        [ $? -eq 0 ] && echo "Hard rebooted instance: $server_id"
    done
}

os_nova_hci_reserved_mem_mb()
{
    local sysdev=$(df | grep ' /$' | awk '{print $1}' | awk -F'/' '{print $3}' | grep -o '.*[^0-9]' | tr -d '\n')
    local size_in_bytes=$(lsblk -dlbn --sort name -o NAME,SIZE,TYPE,TRAN | /bin/grep disk | /bin/grep -v usb | grep -v $sysdev | awk '{print $2}' | paste -sd+ - | bc)
    local reserved_mem_mb=$(( size_in_bytes / 10000000000 * 17 ))
    echo -n $reserved_mem_mb
}

os_nova_mdev_instance_sync()
{
    local type=$(cat /etc/nova/nova.conf | grep enabled_vgpu_types | awk '{print $3}' | tr -d '\n')

    for i in $(virsh list --all | grep instance- | awk '{print $2}') ; do
        if virsh dumpxml $i | grep -q mdev ; then
            local mdev_loc=$(find /sys/devices/ -name $type -type d | sort -R | head -n 1)
            local uuid=$(virsh dumpxml $i | grep mdev -A 2 | grep uuid | awk -F\' '{print $2}')
            if [ -n "$uuid" -a -n "$mdev_loc" -a ! -d "/sys/bus/mdev/devices/$uuid"  ] ; then
                echo $uuid > $mdev_loc/create
            fi
        fi
    done
}

os_nova_instance_reset_pass()
{
    local srv_id=${1:-NOSUCHSERVERID}
    shift
    local user=${1:-NOUSERNAME}
    shift
    local pass=${*:-NOPASS}
    local srv_info_json=$($OPENSTACK server show $srv_id -f json)
    local node=$(echo $srv_info_json  | jq -r '."OS-EXT-SRV-ATTR:host"')
    local inst=$(echo $srv_info_json  | jq -r '."OS-EXT-SRV-ATTR:instance_name"')

    if remote_run $node virsh list | grep -q $inst ; then
        if [ $(echo $pass | wc -c) -gt 100 ] ; then
            local inst_sshkey=$(mktemp -u /tmp/inst_sshkey_XXXX.pub)
            remote_run $node echo "$pass" >$inst_sshkey
            remote_run $node "virsh set-user-sshkeys --domain $inst --user $user --reset >/dev/null" || echo "Failed to reset sshkey for $user"
            remote_run $node "virsh set-user-sshkeys --domain $inst --user $user --file $inst_sshkey >/dev/null" || echo "Failed to update sshkey for $user"
            remote_run $node rm -f $inst_sshkey
        else
            remote_run $node "virsh set-user-password --domain $inst --user $user $pass >/dev/null" || echo "Failed to reset password for $user"
        fi
    fi
}

os_nova_sshkey_create()
{
    local nova_ssh_dir=$1

    mkdir -p $nova_ssh_dir
    cp /root/.ssh/id_rsa $nova_ssh_dir
    echo 'StrictHostKeyChecking no' >> $nova_ssh_dir/config
    cat /root/.ssh/id_rsa.pub >> $nova_ssh_dir/authorized_keys
    chmod 644 $nova_ssh_dir/config
    chmod 600 $nova_ssh_dir/id_rsa $nova_ssh_dir/authorized_keys
    chown -R nova:nova $nova_ssh_dir
}

os_cinder_volume_list()
{
    local vol_json=$($OPENSTACK volume list --all-project -f json)
    for id in $(echo $vol_json | jq -r .[].ID) ; do
        if [ "$VERBOSE" == "1" ] ; then
            name=$(echo $vol_json | jq -r ".[] | select(.ID == \"$id\").Name")
            status=$(echo $vol_json | jq -r ".[] | select(.ID == \"$id\").Status")
            printf "%s %12s %s\n" "$id" "(${status:-NA})" "${name:-NA}"
        else
            printf "%s\n" "$id"
        fi
    done
}

os_cinder_volume_reset()
{
    local volume_id=$1
    cinder reset-state --state available $volume_id
    cinder reset-state --attach-status detached $volume_id
}

os_cinder_volume_force_detach()
{
    local volume_id=$1

    server_id=$($OPENSTACK volume show $volume_id -f json | jq -r .attachments[].server_id)
    if [ -n "$server_id" ] ; then
        /usr/bin/mysql -u root -D nova -e "UPDATE block_device_mapping SET deleted=id, deleted_at=NOW() WHERE deleted_at is NULL and volume_id ='$volume_id' LIMIT 1;"
        os_cinder_volume_reset $volume_id
        $OPENSTACK server reboot --hard $server_id
    fi
}

os_cinder_virsh_secret_create()
{
    local seed=$1
    local location=${2:-localhost}
    local pass=$3
    local uuid=$(uuidgen --sha1 --namespace @dns --name "$seed.$location")
    if [ -n "$pass" ] ; then
        local secret=$(sshpass -p "$pass" ssh root@$location $CEPH auth get-key client.admin)
    else
        local secret=$($CEPH auth get-key client.admin)
    fi
    local name="$location client.admin secret"
    local old=$(virsh secret-list 2>/dev/null | grep "$name" | awk '{print $1}' | tr -d '\n')

    if [ -n "$secret" ] ; then
        cat > secret.xml <<EOF
<secret ephemeral='no' private='no'>
  <uuid>$uuid</uuid>
  <usage type='ceph'>
    <name>$name</name>
  </usage>
</secret>
EOF
        if [ -n "$old" ] ; then
            virsh secret-undefine $old >/dev/null 2>&1
        fi
        virsh secret-define --file secret.xml >/dev/null 2>&1
        virsh secret-set-value --secret $uuid --base64 $secret >/dev/null 2>&1
        rm -f secret.xml
    fi
    echo -n "$uuid"
}

os_post_failure_host_evacuation()
{
    local host=$1
    nova host-evacuate $host
}

os_evac_upgrade_prepare()
{
    local curr=$(firmware_get_active)
    local next=0
    local grub_dir=/boot/grub2

    if (( "$curr" == 1 )) ; then
        next=2
    else
        next=1
    fi

    if cat $grub_dir/info$next | grep -q "firmware_version.*2\.3\.1" ; then
        MountOtherPartition

        local file1=/usr/local/lib/python3.6/site-packages/oslo_messaging/_drivers/impl_rabbit.py
        if [ -f /mnt/target/$file1 ] ; then
            cp -f $file1 $file1.orig
            cp -f /mnt/target/$file1 $file1
        fi

        umount -l /mnt/target
    fi
}

os_pre_failure_host_evacuation()
{
    local host=$1
    local env=${2:-default}

    if [ "$env" == "upgrade" ] ; then
        # os_evac_upgrade_prepare
        $HEX_CLI -c cluster check_repair MsgQueue >/tmp/upgrade_rabbitmq.log 2>&1

        if $HEX_SDK health_rabbitmq_check ; then
            # clear stale api for nova, neutron, and cinder
            cubectl node exec -r control -p $HEX_SDK stale_api_check_repair openstack-nova-api 8774 nova-api python3 0 >/dev/null 2>&1
            cubectl node exec -r control -p $HEX_SDK stale_api_check_repair neutron-server 9696 neutron-server server 0 >/dev/null 2>&1
            cubectl node exec -r control -p $HEX_SDK stale_api_check_repair openstack-cinder-api 8776 cinder-api python3 0 >/dev/null 2>&1
            #cubectl node exec -r control -p hex_config restart_nova >/dev/null 2>&1
            cubectl node exec -r control -p systemctl restart openstack-nova-scheduler >/dev/null 2>&1
            cubectl node exec -r control -p systemctl restart openstack-nova-conductor >/dev/null 2>&1
            cubectl node exec -r compute -p systemctl restart openstack-nova-compute >/dev/null 2>&1
        else
            Error "rabbitmq is not Ok"
        fi
    fi
    nova host-evacuate-live $host
}

os_pre_failure_host_evacuation_sequential()
{
    local from_host=${1:-$HOSTNAME}
    local server_list_json=$($OPENSTACK server list --host $from_host --all-projects --long -f json)
    local host_array=($(cubectl node -r compute list -j | jq -r .[].hostname | grep -v $from_host))
    local num_host=${#host_array[@]}
    local srv_cnt=$(echo $server_list_json | jq -r .[].ID | wc -l)
    local cnt=0

    for sid in $(echo $server_list_json | jq -r .[].ID) ; do
        to_host=${host_array[$((cnt++ % $num_host))]}
        old_state_json=$($OPENSTACK server show $sid -f json)
        old_host=$(echo $old_state_json | jq -r .hypervisor_hostname)
        old_status=$(echo $old_state_json | jq -r .status)
        old_power=$(echo $old_state_json | jq -r .power_state)
        success=false
        nova live-migration $sid $to_host
        for i in {1..10} ; do
            sleep 5
            new_state_json=$($OPENSTACK server show $sid -f json)
            new_host=$(echo $new_state_json | jq -r .hypervisor_hostname)
            new_status=$(echo $new_state_json | jq -r .status)
            new_name=$(echo $new_state_json | jq -r .name)
            new_power=$(echo $new_state_json | jq -r .power_state)
            if [ "$VERBOSE" == "1" ] ; then
                echo "migrating $sid($old_status) from $from_host to $to_host: $new_name($new_status) on $new_host"
            fi
            if [ "x$new_host" = "x$to_host" -a "x$old_status" = "x$new_status" -a "x$old_power" = "x$new_power" ] ; then
                success=true
                break
            fi
        done
        [ "x$success" = "xtrue" ] || return 1
    done

    return 0
}

os_cinder_volume_service_remove()
{
    if ! is_control_node ; then
        return 0;
    fi

    /usr/local/bin/cinder service-disable $HOSTNAME cinder-volume
    /usr/bin/cinder-manage service remove cinder-volume $HOSTNAME
}

os_segment_name_list()
{
    $OPENSTACK segment list -f value -c name
}

os_segment_list()
{
    $OPENSTACK segment list
}

os_maintenance_name_list()
{
    local segment=$1
    $OPENSTACK segment host list $segment -f value -c name -c on_maintenance | grep True | awk '{print $1}'
}

os_segment_add()
{
    local segment=$1
    local host_group=$2
    $OPENSTACK segment create $segment auto COMPUTE
    IFS=',' read -a host_array <<<"$host_group"
    declare -p host_array > /dev/null
    for host in "${host_array[@]}" ; do
        $OPENSTACK segment host create $host COMPUTE SSH $segment
    done
}

os_segment_delete()
{
    local segment=$1
    $OPENSTACK segment delete $segment
}

os_segment_show()
{
    local segment=$1
    $OPENSTACK segment host list $segment
}

os_compute_node_production_set()
{
    local segment=$1
    local hostname=$2
    local info=$($OPENSTACK segment host list $segment -f value -c uuid -c name -c failover_segment_id | grep $hostname)
    $OPENSTACK segment host update --on_maintenance False $(echo $info | awk '{print $3}') $(echo $info | awk '{print $1}')
    $OPENSTACK compute service set --enable $hostname nova-compute
}

os_masakari_job_list()
{
    $OPENSTACK notification list
}

# params:
# $1: file dir (required)
# $2: file name  (required)
os_octavia_image_import()
{
    local dir=$1
    local file=$2

    local olds=$($OPENSTACK image list -f value --property name=amphora-x64-haproxy -c ID)
    if [ -n "$olds" ] ; then
        $OPENSTACK image delete $olds 2>/dev/null
    fi
    os_image_import $dir $file amphora-x64-haproxy "--private"
    local amphora_id=$($OPENSTACK image list -f value --property name=amphora-x64-haproxy -c ID)
    $OPENSTACK image set --tag amphora $amphora_id
}

os_octavia_init()
{
    if ! is_control_node ; then
        return 0
    fi

    if [ -f "/etc/appliance/state/octavia_init_done" ] ; then
        return 0
    else
        # sanitize dependent resources before re-creating Octavia
        timeout 30 $OPENSTACK network list -f value | grep "lb-mgmt-net \[\]" 2>/dev/null | cut -d' ' -f1 | xargs -i $OPENSTACK network delete {} || true

        # lb-hmgr-sec-grp, lb-mgmt-sec-grp
        if [ $(timeout 30 $OPENSTACK security group list -f value | grep "lb[-]" | wc -l) -gt 2 ] ; then
            timeout 30 $OPENSTACK security group list -f value | grep "lb[-]" | cut -d' ' -f1 | xargs -i $OPENSTACK security group delete {} || true
        fi
    fi

    local net_cidr=$1
    local net_id=$(timeout 30 $OPENSTACK network list | awk '/ lb-mgmt-net / {print $2}')
    local sub_id=$(timeout 30 $OPENSTACK subnet list | awk ' / lb-mgmt-subnet / {print $2}')
    local key=$(timeout 30 $OPENSTACK keypair list -f value -c Name | grep octavia_ssh_key)
    local flavor_id_o=$(timeout 30 $OPENSTACK flavor list --all -f value -c ID | grep 16443)
    local flavor_id_d=$(timeout 30 $OPENSTACK flavor list --all -f value -c ID | grep 16444)
    local flavor_id_s=$(timeout 30 $OPENSTACK flavor list --all -f value -c ID | grep 16445)
    local flavor_id_m=$(timeout 30 $OPENSTACK flavor list --all -f value -c ID | grep 16446)
    local flavor_id_l=$(timeout 30 $OPENSTACK flavor list --all -f value -c ID | grep 16447)
    local secgrp_id=$(timeout 30 $OPENSTACK security group list | awk ' / lb-mgmt-sec-grp / {print $2}')
    local hmgr_secgrp_id=$(timeout 30 $OPENSTACK security group list | awk ' / lb-hmgr-sec-grp / {print $2}')

    # how many tasks has been done
    init_done=0

    if [ -z "$net_id" ] ; then
        init_done=$(( init_done + 1 ))
        timeout 30 $OPENSTACK network create lb-mgmt-net
    fi

    if [ -z "$sub_id" ] ; then
        init_done=$(( init_done + 1 ))
        timeout 30 $OPENSTACK subnet create --subnet-range $net_cidr --network lb-mgmt-net lb-mgmt-subnet
        timeout 30 $OPENSTACK subnet set --gateway none lb-mgmt-subnet
    fi

    if [ -z "$key" ] ; then
        init_done=$(( init_done + 1 ))
        timeout 30 $OPENSTACK keypair create --public-key /etc/octavia/octavia_ssh_key.pub octavia_ssh_key
    fi

    if [ -z "$flavor_id_o" ] ; then
        init_done=$(( init_done + 1 ))
        timeout 30 $OPENSTACK flavor create --id 16443 --ram 1024 --disk 20 --vcpus 1 --private m1.amphora
    fi

    if [ -z "$flavor_id_d" ] ; then
        init_done=$(( init_done + 1 ))
        timeout 30 $OPENSTACK flavor create --id 16444 --ram 1024 --disk 20 --vcpus 1 --private d2.amphora
        timeout 30 $OPENSTACK loadbalancer flavorprofile create --name amphora-default --provider amphora --flavor-data '{"compute_flavor": "16444"}'
        timeout 30 $OPENSTACK loadbalancer flavor create --name DEFAULT --flavorprofile amphora-default --description "pool less then 10 members." --enable
    fi

    if [ -z "$flavor_id_s" ] ; then
        init_done=$(( init_done + 1 ))
        timeout 30 $OPENSTACK flavor create --id 16445 --ram 2048 --disk 20 --vcpus 2 --private s2.amphora
        timeout 30 $OPENSTACK loadbalancer flavorprofile create --name amphora-small --provider amphora --flavor-data '{"compute_flavor": "16445"}'
        timeout 30 $OPENSTACK loadbalancer flavor create --name SMALL --flavorprofile amphora-small --description "pool less then 30 members." --enable
    fi

    if [ -z "$flavor_id_m" ] ; then
        init_done=$(( init_done + 1 ))
        timeout 30 $OPENSTACK flavor create --id 16446 --ram 4096 --disk 20 --vcpus 4 --property hw:cpu_sockets=1 --property hw:cpu_cores=2 --property hw:cpu_threads=2 --private m2.amphora
        timeout 30 $OPENSTACK loadbalancer flavorprofile create --name amphora-medium --provider amphora --flavor-data '{"compute_flavor": "16446"}'
        timeout 30 $OPENSTACK loadbalancer flavor create --name MEDIUM --flavorprofile amphora-medium --description "pool less then 300 members." --enable
    fi

    if [ -z "$flavor_id_l" ] ; then
        init_done=$(( init_done + 1 ))
        timeout 30 $OPENSTACK flavor create --id 16447 --ram 8192 --disk 20 --vcpus 8 --property hw:cpu_sockets=2 --property hw:cpu_cores=2 --property hw:cpu_threads=2 --private l2.amphora
        timeout 30 $OPENSTACK loadbalancer flavorprofile create --name amphora-large --provider amphora --flavor-data '{"compute_flavor": "16447"}'
        timeout 30 $OPENSTACK loadbalancer flavor create --name LARGE --flavorprofile amphora-large --description "pool less then 3000 members." --enable
    fi

    if [ -z "$secgrp_id" ] ; then
        init_done=$(( init_done + 1 ))
        timeout 30 $OPENSTACK security group create lb-mgmt-sec-grp
        timeout 30 $OPENSTACK security group rule create --protocol icmp lb-mgmt-sec-grp
        timeout 30 $OPENSTACK security group rule create --protocol tcp --dst-port 22 lb-mgmt-sec-grp
        timeout 30 $OPENSTACK security group rule create --protocol tcp --dst-port 9443 lb-mgmt-sec-grp
        timeout 30 $OPENSTACK security group rule create --protocol icmpv6 --ethertype IPv6 --remote-ip ::/0 lb-mgmt-sec-grp
        timeout 30 $OPENSTACK security group rule create --protocol tcp --dst-port 22 --ethertype IPv6 --remote-ip ::/0 lb-mgmt-sec-grp
        timeout 30 $OPENSTACK security group rule create --protocol tcp --dst-port 9443 --ethertype IPv6 --remote-ip ::/0 lb-mgmt-sec-grp
    fi

    if [ -z "$hmgr_secgrp_id" ] ; then
        init_done=$(( init_done + 1 ))
        timeout 30 $OPENSTACK security group create lb-hmgr-sec-grp
        timeout 30 $OPENSTACK security group rule create --protocol udp --dst-port 5555 lb-hmgr-sec-grp
        timeout 30 $OPENSTACK security group rule create --protocol udp --dst-port 5555 --ethertype IPv6 --remote-ip ::/0 lb-hmgr-sec-grp
    fi

    if [ $init_done -eq 0 ] ; then
        touch /etc/appliance/state/octavia_init_done
    fi
}

os_octavia_node_init()
{
    if [ ! -f /run/cube_commit_done  ] ; then
        return 0
    fi

    local port_ip=$1
    local cidr=$2
    local port_id=
    local subnet_id=
    local port_name="octavia-hmgr-port-$(hostname)"

    local init=$(timeout 30 $OPENSTACK port list -f value | grep $port_name | grep ACTIVE | wc -l)
    if [ $init -eq 0 ] ; then
        # sanitize dependent resources before re-creating Octavia
        timeout 30 $OPENSTACK port list -f value | grep $port_name | cut -d' ' -f1 | xargs -i $OPENSTACK port delete {} || true
        /usr/bin/ovs-vsctl del-port br-int octavia-hm0 || true

        port_id=$(timeout 30 $OPENSTACK port create --security-group lb-hmgr-sec-grp --device-owner Octavia:health-mgr --host=$(hostname) -c id -f value --network lb-mgmt-net --fixed-ip subnet=lb-mgmt-subnet,ip-address=$port_ip $port_name 2>/dev/null)
    else
        port_id=$(timeout 30 $OPENSTACK port list -f value | grep $port_name | awk '{print $1}')
        # if port exists, honor original settings because it could be an upgraded cluster
        port_ip=$(timeout 30 $OPENSTACK port show $port_name | grep "fixed_ips.*ip_address" | awk -F"'" '{print $2}')
        subnet_id=$(timeout 30 $OPENSTACK port show $port_name | grep "fixed_ips.*ip_address" | awk -F"'" '{print $4}')
        cidr=$(timeout 30 $OPENSTACK subnet show $subnet_id | grep cidr | awk '{print $4}')
    fi

    if [ -z "$port_id" ] ; then
        return 0
    fi

    local port_mac=$(timeout 30 $OPENSTACK port show -c mac_address -f value $port_id)

    if ! /usr/bin/ovs-vsctl port-to-br octavia-hm0 >/dev/null 2>&1 ; then
        /usr/bin/ovs-vsctl -- --may-exist add-port br-int octavia-hm0 -- set Interface octavia-hm0 type=internal -- set Interface octavia-hm0 external-ids:iface-status=active -- set Interface octavia-hm0 external-ids:attached-mac=$port_mac -- set Interface octavia-hm0 external-ids:iface-id=$port_id -- set Interface octavia-hm0 external-ids:skip_cleanup=true
    fi
    if ! /sbin/ip link show octavia-hm0 | grep -q $port_mac ; then
        /sbin/ip link set octavia-hm0 address $port_mac || true
    fi
    if /sbin/ip link show octavia-hm0 | grep -q DOWN ; then
        /sbin/ip link set octavia-hm0 up || true
    fi
    if ! /sbin/ip addr show octavia-hm0 | grep -q $port_ip ; then
        /sbin/ip addr add $port_ip dev octavia-hm0 || true
    fi
    if ! /usr/sbin/route -n | grep -q octavia-hm0 ; then
        /sbin/ip route del $cidr dev octavia-hm0 || true
        /sbin/ip route add $cidr dev octavia-hm0 || true
    fi

    if ! systemctl status octavia-worker >/dev/null 2>&1 ; then
        systemctl start octavia-worker
    fi
    if ! systemctl status octavia-health-manager >/dev/null 2>&1 ; then
        systemctl start octavia-health-manager
    fi
}

os_octavia_nid_get()
{
    $OPENSTACK network list | awk '/ lb-mgmt-net / {print $2}' | tr -d '\n'
}

os_octavia_sgid_get()
{
    $OPENSTACK security group list | awk ' / lb-mgmt-sec-grp / {print $2}' | tr -d '\n'
}

os_octavia_neutron_lbaas_status_sync()
{
    local sync=${1:-yes}
    readarray lbid_array <<<"$(neutron lbaas-loadbalancer-list -c id -f value 2>/dev/null )"
    declare -p lbid_array > /dev/null
    for lbid in "${lbid_array[@]}" ; do
        local lb_id=$(echo $lbid | tr -d '\n')
        if [ -n "$lb_id" ] ; then
            local prov=$(neutron lbaas-loadbalancer-show $lb_id 2>/dev/null | awk '/ provisioning_status /{print $4}')
            local op=$(neutron lbaas-loadbalancer-show $lb_id 2>/dev/null | awk '/ operating_status /{print $4}')
            local o_prov=$(/usr/bin/mysql -u root -D octavia -e "select id,provisioning_status from load_balancer" | grep $lb_id | awk '{print $2}')
            if [ "$o_prov" != "$prov" ] ; then
                if [ "$sync" == "yes" ] ; then
                    /usr/bin/mysql -u root -D octavia -e "UPDATE load_balancer set provisioning_status='$prov', operating_status='$op' where id='$lb_id'"
                else
                    return -1
                fi
            fi
        fi
    done
}

os_octavia_port_remove()
{
    local lb_id=$1

    readarray pid_array <<<"$(/usr/bin/mysql -u root -D octavia -e "select * from amphora where load_balancer_id = '$lb_id'" | grep $lb_id | awk '{print $1}')"
    declare -p pid_array > /dev/null
    for pid in "${pid_array[@]}" ; do
        local port_id=$(echo $pid | tr -d '\n')
        $OPENSTACK port delete octavia-lb-vrrp-$port_id
    done
}

os_octavia_neutron_lbaas_hm_remove()
{
    local pool_id=$1
    local hm_id=$(neutron lbaas-pool-show $pool_id 2>/dev/null | awk '/ healthmonitor_id /{print $4}')

    if [ -n "$hm_id" -a "$hm_id" != "|" ] ; then
        neutron lbaas-healthmonitor-delete $hm_id
        sleep 6
    fi
}

os_octavia_neutron_lbaas_member_remove()
{
    local pool_id=$1

    readarray mid_array <<<"$(neutron lbaas-member-list $pool_id -c id -f value 2>/dev/null)"
    declare -p mid_array > /dev/null
    for mid in "${mid_array[@]}" ; do
        local member_id=$(echo $mid | tr -d '\n')
        neutron lbaas-member-delete $member_id $pool_id
        sleep 6
    done
}

os_octavia_neutron_lbaas_pool_remove()
{
    local lb_id=$1

    readarray pid_array <<<"$(/usr/bin/mysql -u root -D neutron -e "select id,loadbalancer_id from lbaas_pools where loadbalancer_id = '$lb_id'" | grep $lb_id | awk '{print $1}')"
    declare -p pid_array > /dev/null
    for pid in "${pid_array[@]}" ; do
        local pool_id=$(echo $pid | tr -d '\n')
        os_octavia_neutron_lbaas_hm_remove $pool_id
        os_octavia_neutron_lbaas_member_remove $pool_id
        neutron lbaas-pool-delete $pool_id
        sleep 6
    done
}

os_octavia_neutron_lbaas_listener_remove()
{
    local lb_id=$1

    readarray lid_array <<<"$(/usr/bin/mysql -u root -D neutron -e "select id,loadbalancer_id from lbaas_listeners where loadbalancer_id = '$lb_id'" | grep $lb_id | awk '{print $1}')"
    declare -p lid_array > /dev/null
    for lid in "${lid_array[@]}" ; do
        local listener_id=$(echo $lid | tr -d '\n')
        neutron lbaas-listener-delete $listener_id
        sleep 6
    done
}

os_octavia_neutron_lbaas_remove()
{
    local lb_name=$@
    local lb_id=$(neutron lbaas-loadbalancer-list 2>/dev/null | grep " $lb_name " | awk '{print $2}' | tr -d '\n')

    if [ -z "$lb_id" ] ; then
        echo "$lb_name is not found"
        return 0
    fi

    echo "Removing attached vrrp ports..."
    os_octavia_port_remove $lb_id

    echo "Removing pools and its members/monitors..."
    os_octavia_neutron_lbaas_pool_remove $lb_id

    echo "Removing listeners..."
    os_octavia_neutron_lbaas_listener_remove $lb_id

    echo "Removing loadbalancer... $lb_id"
    neutron lbaas-loadbalancer-delete $lb_id
}

os_octavia_neutron_lbaas_db_remove()
{
    local lb_name=$@
    local lb_id=$(neutron lbaas-loadbalancer-list 2>/dev/null | grep " $lb_name " | awk '{print $2}' | tr -d '\n')

    if [ -z "$lb_id" ] ; then
        echo "$lb_name is not found"
        return 0
    fi

    echo "Removing attached vrrp ports..."
    os_octavia_port_remove $lb_id

    echo "Removing listeners..."
    /usr/bin/mysql -u root -D neutron -e "delete from lbaas_listeners where loadbalancer_id = '$lb_id'"

    readarray pid_array <<<"$(/usr/bin/mysql -u root -D neutron -e "select id,loadbalancer_id from lbaas_pools where loadbalancer_id = '$lb_id'" | grep $lb_id | awk '{print $1}')"
    declare -p pid_array > /dev/null
    for pid in "${pid_array[@]}" ; do
        local pool_id=$(echo $pid | tr -d '\n')
        local hm_id=$(neutron lbaas-pool-show $pool_id 2>/dev/null | awk '/ healthmonitor_id /{print $4}')
        echo "Removing pools and its members/monitors... $pool_id"
        /usr/bin/mysql -u root -D neutron -e "delete from lbaas_members where pool_id = '$pool_id'"
        /usr/bin/mysql -u root -D neutron -e "delete from lbaas_pools where id = '$pool_id'"
        /usr/bin/mysql -u root -D neutron -e "delete from lbaas_healthmonitors where id = '$hm_id'"
    done

    echo "Removing loadbalancer... $lb_id"
    /usr/bin/mysql -u root -D neutron -e "delete from lbaas_loadbalancer_statistics where loadbalancer_id = '$lb_id'"
    /usr/bin/mysql -u root -D neutron -e "delete from lbaas_loadbalancers where id = '$lb_id'"
    $OPENSTACK loadbalancer delete $lb_id --cascade
    $OPENSTACK port delete loadbalancer-$lb_id
}

os_octavia_lb_remove()
{
    local lb_name=$@
    local lb_id=$($OPENSTACK loadbalancer list | grep " $lb_name " | awk '{print $2}' | tr -d '\n')

    if [ -z "$lb_id" ] ; then
        echo "$lb_name is not found"
        return 0
    fi

    os_octavia_port_remove $lb_id
    $OPENSTACK loadbalancer delete $lb_id --cascade
}

os_octavia_lb_fix()
{
    local lb_nameid=$1

    lb_id=$($OPENSTACK loadbalancer show $lb_nameid -f json | jq -r .id)
    if [ -n "$lb_id" ] ; then
        /usr/bin/mysql -u root -D octavia -e "update load_balancer set provisioning_status='ERROR' where id='$lb_id'"
        echo "Fixing load balancer... $lb_id"
        $OPENSTACK loadbalancer failover $lb_id --wait
    fi
}

os_octavia_lb_show_instance()
{
    local lb_nameid=$1

    amphora_id=$($OPENSTACK loadbalancer amphora list --loadbalancer $lb_nameid -f json | jq -r .[0].id)
    if [ -n "$amphora_id" ] ; then
        instance_id=$($OPENSTACK loadbalancer amphora show $amphora_id -f json | jq -r .compute_id)
        $OPENSTACK server show $instance_id
    fi
}

os_ec2_credentials_create()
{
    local user=$1
    local project=$2
    [ "x$project" != "x" ] || project=$user
    $OPENSTACK ec2 credentials create --user $user --project $project
}

os_ec2_credentials_delete()
{
    $OPENSTACK ec2 credentials delete --user $1 $2
}

os_access_key_list()
{
    $OPENSTACK ec2 credentials list --user $1 -c Access -f value
}

os_ec2_credentials_list()
{
    $OPENSTACK ec2 credentials list --user $1 -c Access -c Secret
}

os_s3_cmd_by_name()
{
    local user=$1
    shift 1
    local keys=$keys
    [ "x$keys" != "x" ] || keys="$($OPENSTACK ec2 credentials list --user $user -c Access -c Secret -f value | head -n 1)"
    local endpoint=$(cat $EP_SNAPSHOT | grep object-store.*public | awk '{print $5}' | awk -F'/' '{print $3}')
    local host=$(echo $endpoint | awk -F':' '{print $1}')

    if [ -n "$keys" ] ; then
        /usr/bin/s3cmd --no-ssl --host=$endpoint --host-bucket=$host --access_key=$(echo $keys | awk '{print $1}') --secret_key=$(echo $keys | awk '{print $2}') $*
    else
        echo "please create ec2 key for user '$user' first"
    fi
}

os_s3_list_all()
{
    local user=$1
    os_s3_cmd_by_name $user la
}

os_s3_list()
{
    local user=$1
    local path=$2
    os_s3_cmd_by_name $user ls s3://${path#s3://}
}

os_s3_bucket_create()
{
    local user=$1
    local path=$2
    os_s3_cmd_by_name $user mb s3://${path#s3://}
}

os_s3_bucket_remove()
{
    local user=$1
    local path=$2
    os_s3_cmd_by_name $user rb s3://${path#s3://}
}

os_s3_bucket_quota()
{
    local user=$1
    local path=$2
    local size=$3
    local objs=$4
    local params=
    for uid in $(radosgw-admin user list | jq -r .[]) ; do
        if [ "$uid" = "$user" ] ; then
            params="--uid=$user"
            break
        elif [ "$(radosgw-admin user info --uid=$uid | jq -r ".display_name")" = "$user" ] ; then
            params="--uid=$uid"
            break
        fi
    done
    [ "x$path" = "x" ] || params+=" --bucket=$path"
    radosgw-admin quota set $params --max-size=${size:--1} --max-objects=${objs:--1}
    radosgw-admin quota enable --quota-scope=bucket $params
}

os_s3_bucket_stats()
{

    local user=$1
    local path=$2
    local params=
    for uid in $(radosgw-admin user list | jq -r .[]) ; do
        if [ "$uid" = "$user" ] ; then
            params="--uid=$user"
            break
        elif [ "$(radosgw-admin user info --uid=$uid | jq -r ".display_name")" = "$user" ] ; then
            params="--uid=$uid"
            break
        fi
    done
    [ "x$path" = "x" ] || params+=" --bucket=$path"
    radosgw-admin bucket stats $params
}

os_s3_bucket_setpolicy()
{

    local user=$1
    local path=$2
    local effect=$3
    local ip=$4
    local s3_policy=$(mktemp -u /tmp/s3_policy_XXXX.json)
    cat >$s3_policy <<EOF
{
    "Version": "2012-10-17",
    "Id": "IP_Filter_Policy",
    "Statement": [
        {
            "Sid": "Allow/Deny List and GET actions from source IP (range)",
            "Effect": "$effect",
            "Principal": "*",
            "Action": ["s3:ListBucket", "s3:GetObject"],
            "Resource": ["*/*"],
            "Condition": {
                "IpAddress": {
                    "aws:SourceIp": "$ip"
                }
            }
        }
    ]
}
EOF
    os_s3_cmd_by_name $user setpolicy $s3_policy s3://${path#s3://}
    rm -f ${s3_policy:-/tmp/UNSPECIFIED}
}

os_s3_bucket_info()
{
    local user=$1
    local path=$2
    os_s3_cmd_by_name $user info s3://${path#s3://}
}

os_s3_object_put()
{
    local user=$1
    local file=$2
    local path=$3
    os_s3_cmd_by_name $user put $file s3://${path#s3://}
}

os_s3_object_get()
{
    local user=$1
    local path=$2
    local file=$3
    os_s3_cmd_by_name $user get s3://${path#s3://} $file
}

os_s3_object_delete()
{
    local user=$1
    local path=$2
    os_s3_cmd_by_name $user del s3://${path#s3://}
}

os_heat_service_clean()
{
    /usr/bin/heat-manage service clean
}

os_manila_share_remove()
{
    local project=$1
    local share=$2

    local share_id=$($OPENSTACK share list --project $project -f json | jq -r '.[] | select(.Name=='\"$share\"') | .ID')

    $OPENSTACK share set --status available $share_id
    $OPENSTACK share delete --force --wait $share_id
}

os_manila_service_remove()
{
    local host=$1
    local binary=$2
    local srv_id=$(manila service-list | grep "$binary.*$host" | awk '{print $2}')
    if [ -n "$srv_id" ] ; then
        /usr/bin/mysql -u root -D manila -e "delete from services where id = '$srv_id'"
    fi
}

# params:
# $1: file dir (required)
# $2: file name  (required)
os_manila_image_import()
{
    local dir=$1
    local file=$2

    local olds=$($OPENSTACK image list -f value --property name=manila-service-image -c ID)
    if [ -n "$olds" ] ; then
        $OPENSTACK image delete $olds 2>/dev/null
    fi
    os_image_import $dir $file manila-service-image "--private"
    local manila_id=$($OPENSTACK image list -f value --property name=manila-service-image -c ID)
    $OPENSTACK image set --tag manila-service-image $manila_id
}

os_manila_init()
{
    if ! is_control_node ; then
        return 0
    fi

    local flavor_id=$($OPENSTACK flavor list --all -f value -c ID | grep 653443)
    local tenant_type_id=$(manila type-list | awk '/ tenant_share_type /{print $2}')
    #local global_type_id=$(manila type-list | awk '/ global_share_type /{print $2}')

    if [ -z "$flavor_id" ] ; then
        $OPENSTACK flavor create --id 653443 --ram 1024 --disk 0 --vcpus 1 --private m1.manila
    fi

    if [ -z "$tenant_type_id" ] ; then
        manila type-create --snapshot_support true --create_share_from_snapshot_support true tenant_share_type true
    fi

    #if [ -z "$global_type_id" ] ; then
    #    manila type-create --snapshot_support true --create_share_from_snapshot_support true global_share_type false
    #fi
}

os_ironic_deploy_kernel_import()
{
    local kernel=$1/$2

    local okernel=$($OPENSTACK image list -f value --property name=deploy.kernel -c ID)
    if [ -n "$okernel" ] ; then
        $OPENSTACK image delete $okernel 2>/dev/null
    fi

    openstack image create --disk-format raw --file $kernel --public deploy.kernel
    cp -f $kernel /tftpboot/deploy.kernel
}

os_ironic_deploy_initramfs_import()
{
    local initramfs=$1/$2

    local oinitrd=$($OPENSTACK image list -f value --property name=deploy.initrd -c ID)
    if [ -n "$oinitrd" ] ; then
        $OPENSTACK image delete $oinitrd 2>/dev/null
    fi

    openstack image create --disk-format raw --file $initramfs --public deploy.initrd
    cp -f $initramfs /tftpboot/deploy.initrd
}

os_ironic_config_sync()
{
    local ironic=/etc/ironic/ironic.conf
    local dhcp=/etc/ironic-inspector/dnsmasq.conf

    local flat=$($OPENSTACK network list --provider-network-type flat --external -f json)

    if [ -n "$flat" -a "$flat" != "null" ] ; then

        local name=$(echo $flat | jq -r .[0].Name)
        if ! grep -q "cleaning_network = $name" $ironic ; then
            sed -i "/^cleaning_network /s/=.*$/= $name/" $ironic
            systemctl restart openstack-ironic-conductor
        fi

        local subnet=$(echo $flat | jq -r .[0].Subnets[0])
        if [ -n "$subnet" -a "$subnet" != "null" ] ; then
            cp -f $dhcp $dhcp.prev
            $HEX_CFG init_ironic_dhcp_config;
            local range=$($OPENSTACK subnet show $subnet | awk '/ allocation_pools /{print $4}' | tr '-' ',')
            echo "dhcp-range=$range" >> $dhcp
            local info=$($OPENSTACK subnet show $subnet -f json)
            local gateway=$(echo $info | jq -r .gateway_ip)
            echo "dhcp-option=3,$gateway" >> $dhcp
            local nameservers=$(echo $info | jq -r .dns_nameservers[] | tr "\n" "," | head -c -1)
            echo "dhcp-option=6,$nameservers" >> $dhcp
            # list non virtual ports on public network
            local ports=$($OPENSTACK port list --network $name --device-owner compute:nova -f value | grep -v " fa:16:3e:")
            for mac in $(echo "$ports" | awk '{print $2}') ; do
                local ip=$(echo "$ports" | grep $mac | awk -F"'" '{print $8}')
                echo "dhcp-host=$mac,$ip" >> $dhcp
            done
            if ! cmp -s $dhcp $dhcp.prev ; then
                rm -f /var/lib/dnsmasq/dnsmasq.leases
                systemctl restart openstack-ironic-inspector-dnsmasq
            fi
        fi
    fi
}

os_instance_list()
{
    local tenant=$1
    readarray instane_name_array <<<"$($OPENSTACK server list --project $tenant -f value -c Name)"
    declare -p instane_name_array > /dev/null
    local len=${#instane_name_array[@]}
    for (( i=0 ; i<$len ; i++ )) ; do
        echo ${instane_name_array[$i]}
    done
}

os_instance_id_list()
{
    local tenant=$1
    if [ "$VERBOSE" == "1" ] ; then
        readarray instane_id_array <<<"$($OPENSTACK server list --project $tenant -f value -c Name -c ID)"
    else
        readarray instane_id_array <<<"$($OPENSTACK server list --project $tenant -f value -c ID)"
    fi
    declare -p instane_id_array > /dev/null
    local len=${#instane_id_array[@]}
    for (( i=0 ; i<$len ; i++ )) ; do
        echo ${instane_id_array[$i]}
    done
}

os_instance_list_for_project_long_run()
{
    local projects=$(timeout 30 $OPENSTACK project list --domain default -f value | grep -v service)

    local o="{"
    for id in $(echo "$projects" | awk '{print $1}') ; do
        local name=$(echo "$projects" | grep $id | awk '{print $2}')
        local list=$(timeout 30 $OPENSTACK server list --long -f json --project $name)
        o="$o \"$name\": $list,"
    done
    o="$o \"service\": []}"
    echo "$o" | jq -c . > /tmp/instance_for_project.json
}

os_instance_list_for_project()
{
    if [ -f "/tmp/instance_for_project.json" ] ; then
        cat /tmp/instance_for_project.json
        return
    else
        echo "{}"
    fi
}

os_instance_list_for_miq_user()
{
    local miq_user=$1
    /usr/sbin/get_instances_by_user.py $miq_user | jq -c '[ .[] | {name,ems_ref} ]'
}

os_glance_export_sync()
{
    local rp=$1

    timeout 5 mountpoint -q -- $CEPHFS_STORE_DIR || return
    timeout 5 ls $CEPHFS_GLANCE_DIR 2>/dev/null || return
    os_instance_list_for_project_long_run
    os_instance_export_cleanup $CEPHFS_GLANCE_DIR $rp
}

os_instance_export_cleanup()
{
    local dir=$1
    local bak=$2

    for e in $(cd $dir && ls export-*.tar 2>/dev/null | awk -F'-' '{ for (i=1;i<=NF-2;i++){ printf $i"-" } ; printf "\n"}' | sort | uniq) ; do
        cd $dir && ls -tp | egrep -e "$e.*.tar" | tail -n +$((bak+1)) | xargs rm -f
    done
}

os_instance_export_list()
{
    local dir=$1

    local o="["
    for e in $(cd $dir && ls -lh export-*.tar | awk '{print $9","$5}') ; do
        local fname=$(echo $e | awk -F',' '{print $1}')
        local size=$(echo $e | awk -F',' '{print $2}')
        o="$o {\"fname\": \"$fname\", \"size\": \"$size\"},"
    done
    o="$o {}]"
    echo "$o" | jq -c .
}

os_instance_export()
{
    local tenant=$1
    local instance_name=$2
    local dir=$3
    local format=$4
    local ts=$(date +"%Y%m%d-%H%M%S")

    printf "[$(date +"%T")] fetching $instance_name disk information ... "
    local vm_id=$(os_get_instance_id_by_tenant_and_name $tenant $instance_name)
    if [ $(echo -n "$vm_id" | wc -c) -gt 36 ] ; then
        Error "Instance name $instance_name is not unique in project $tenant"
    elif [ "x$instance_name" = "x$vm_id" ] ; then
        instance_name=$($OPENSTACK server show $vm_id -f value -c name)
    fi

    local vid=$(echo $vm_id | cut -c 1-8)
    local ins_pre="export-$instance_name-$vid-$ts"
    readarray disks_array <<<"$($OPENSTACK server show $vm_id -f json -c attached_volumes | jq -r .attached_volumes[].id)"
    printf '%s\n' "done"

    declare -p disks_array > /dev/null
    len=${#disks_array[@]}
    for (( i=0 ; i<$len ; i++ )) ; do
        local vol_id=$(echo ${disks_array[$i]} | tr -d '\n')
        local img_file="$dir/$ins_pre-disk$i"
        printf "[$(date +"%T")] exporting $instance_name disk$i (volume: $vol_id)\n"

        if [ -n "$vol_id" ] ; then
            rbd -p cinder-volumes export "volume-$vol_id" "$img_file.raw"
            if [ $format = "vmdk" ] ; then
                printf "[$(date +"%T")] converting disk$i to vmdk format\n"
                qemu-img convert -p -f raw -O vmdk $img_file.raw $img_file.vmdk
                rm -f $img_file.raw
            fi
        else
            printf " ... disk $i is not a cinder volume. skip\n"
        fi
    done

    printf "[$(date +"%T")] saving to $dir/$ins_pre.tar ... "
    cd $dir && tar -cf $ins_pre.tar $ins_pre*
    printf '%s\n' "done"
    rm -f $dir/$ins_pre-disk*
}

os_instance_convert_image_stat()
{
    local check_status=$1
    local image_id=$2
    local instance_name=$3
    local dir=$4
    local format=$5
    local ts=$6
    local vid=$7

    if [ $check_status = "active" ] ; then
        printf ' %s\n' "done"
        os_instance_export_save $image_id $instance_name $dir $format $ts $vid
    else
        read -p "." -t 10
        check_status=$($OPENSTACK image show $image_id -f value -c status)
        os_instance_convert_image_stat $check_status $image_id $instance_name $dir $format $ts $vid
    fi
}

os_instance_export_save()
{
    local image_id=$1
    local instance_name=$2
    local dir=$3
    local format=$4
    local ts=$5
    local vid=$6

    local ins_pre="export-$instance_name-$vid-$ts"

    printf "[$(date +"%T")] download uploaded image to file $dir/$ins_pre-disk$i.raw ...\n"
    glance image-download --file $dir/$ins_pre-disk$i.raw --progress $image_id
    if [ $format = "vmdk" ] ; then
        printf "[$(date +"%T")] convert to $dir/$ins_pre-disk$i.vmdk ...\n"
        qemu-img convert -p -f raw -O vmdk $dir/$ins_pre-disk$i.raw $dir/$ins_pre-disk$i.vmdk
    fi
    printf "[$(date +"%T")] delete uploaded image ... "
    $OPENSTACK image delete $image_id
    if [ $format = "vmdk" ] ; then
        rm -rf $dir/$ins_pre-disk$i.raw
    fi
    printf '%s\n' "done"
}

os_metric_name_list()
{
    local tid=$(os_get_project_id_by_name service)
    monasca metric-name-list --tenant-id $tid
}

os_mgr_port_name()
{
    local net_id=$1
    local proj_id=$2
    local suffix=$(echo $net_id | cut -c 1-8)
    local pname="$HOSTNAME-$suffix"
    pname=$(echo $pname | cut -c 1-15)
    echo -n $pname
}

os_mgr_port_remove()
{
    local net_id=$1
    local proj_id=$2
    local host=$3
    local dbpass=$4
    local pname=$(os_mgr_port_name $net_id $proj_id)
    local suffix=$(echo $net_id | cut -c 1-8)
    local netns="mgr-$suffix"

    local ip_netns_exec="/sbin/ip netns exec $netns"

    $ip_netns_exec ip link set $pname down 2>/dev/null
    /sbin/ip netns del $netns 2>/dev/null
    /usr/bin/ovs-vsctl del-port br-int $pname 2>/dev/null
    local port_id=$(mysql -B -h $host -u neutron -p$dbpass -D neutron -e "SELECT id FROM ports WHERE name = '$pname'" | tail -n +2)
    if [ -n "$port_id" ] ; then
        $OPENSTACK port delete $port_id
    fi
}

os_mgr_port_clear()
{
    local host=$1
    local dbpass=$2
    local cols="id,ports.network_id,device_id,ip_address,project_id"
    local joined_tables="ports INNER JOIN ipallocations ON ports.id = ipallocations.port_id"
    local stats=$(mysql -B -h $host -u neutron -p$dbpass -D neutron -e "SELECT $cols FROM $joined_tables WHERE device_owner ='compute:nova'" | tail -n +2)
    for n in $(echo "$stats" | awk '{print $2}' | sort | uniq) ; do
        local proj_ids=$(echo "$stats" | grep $n | awk '{print $5}'| sort | uniq)
        for p in $proj_ids ; do
            os_mgr_port_remove $n $p $host $dbpass
        done
    done
}

os_mgr_port_create()
{
    local net_id=$1
    local proj_id=$2
    local cidr=$3
    local host=$4
    local dbpass=$5
    local pname=$(os_mgr_port_name $net_id $proj_id)
    local suffix=$(echo $net_id | cut -c 1-8)
    local netns="mgr-$suffix"

    local port_id=$(mysql -B -h $host -u neutron -p$dbpass -D neutron -e "SELECT id FROM ports WHERE name = '$pname'" | tail -1)
    local status=$(mysql -B -h $host -u neutron -p$dbpass -D neutron -e "SELECT status FROM ports WHERE name = '$pname'" | tail -1)
    if [ -n "$port_id" -a "$status" != "ACTIVE" ] ; then
        $OPENSTACK port delete $port_id
        /usr/bin/ovs-vsctl del-port br-int $pname 2>/dev/null
    fi

    port_id=$(mysql -B -h $host -u neutron -p$dbpass -D neutron -e "SELECT id FROM ports WHERE name = '$pname'" | tail -1)
    if [ -z "$port_id" ] ; then
        port_id=$($OPENSTACK port create --project $proj_id --device-owner cube:mgr --host=$(hostname) -c id -f value --network $net_id $pname 2>/dev/null)
        /usr/bin/ovs-vsctl del-port br-int $pname 2>/dev/null
    fi

    if [ -z "$port_id" ] ; then
        return 0
    fi

    local cols="mac_address,ip_address"
    local joined_tables="ports INNER JOIN ipallocations ON ports.id = ipallocations.port_id"
    local stats=$(mysql -B -h $host -u neutron -p$dbpass -D neutron -e "SELECT $cols FROM $joined_tables WHERE id ='$port_id'" | tail -1)
    local pmac=$(echo $stats | awk '{print $1}')
    local pip=$(echo $stats | awk '{print $2}')

    if ! /usr/bin/ovs-vsctl port-to-br $pname >/dev/null 2>&1 ; then
        /usr/bin/ovs-vsctl -- --may-exist add-port br-int $pname \
                           -- set Interface $pname type=internal \
                           -- set Interface $pname external-ids:iface-status=active \
                           -- set Interface $pname external-ids:attached-mac=$pmac \
                           -- set Interface $pname external-ids:iface-id=$port_id \
                           -- set Interface $pname external-ids:skip_cleanup=true 2>/dev/null
    fi
    if ! /sbin/ip netns list | grep -q "^$netns " ; then
        /sbin/ip netns add $netns 2>/dev/null
    fi

    local ip_netns_exec="/sbin/ip netns exec $netns"

    if ! $ip_netns_exec ip link list | grep -q $pname ; then
        ip link set $pname netns $netns 2>/dev/null
    fi
    if ! $ip_netns_exec ip link show $pname | grep -q $pmac ; then
        $ip_netns_exec ip link set $pname address $pmac 2>/dev/null
    fi
    if $ip_netns_exec ip link show $pname | grep -q DOWN ; then
        $ip_netns_exec ip link set $pname up 2>/dev/null
    fi
    if ! $ip_netns_exec ip addr show $pname | grep -q $pip ; then
        $ip_netns_exec ip addr add $pip dev $pname 2>/dev/null
    fi
    if ! $ip_netns_exec route -n | grep -q $pname ; then
        $ip_netns_exec ip route del $cidr dev $pname 2>/dev/null
        $ip_netns_exec ip route add $cidr dev $pname 2>/dev/null
    fi
}

os_nova_instance_ping()
{
    if ! is_control_node ; then
        return 0;
    fi

    local active_host=$($HEX_CFG status_pacemaker | awk '/IPaddr2/{print $5}')
    if [ -n "$active_host" ] ; then
        # HA
        if [ "$active_host" != "$(hostname)" ] ; then
            return 0;
        fi
    else
        # non-HA
        active_host=$(hostname)
    fi

    for cmp in $(cubectl node -r compute list -j | jq -r .[].hostname) ; do
        local r=$(echo $cmp | tr -d '\n')
        if ping -c 1 -w 1 $r >/dev/null 2>&1 ; then
            break
        fi
    done

    # mysql cols
    #   1: port
    #   2 network_id
    #   3 device_id (instance id)
    #   4 ip_address
    local proto=${1:-arping}
    local dbpass=$(cat /etc/neutron/neutron.conf | grep connection | awk -F':|@' '{print $3}')
    local cols="id,ports.network_id,device_id,ip_address,project_id"
    local joined_tables="ports INNER JOIN ipallocations ON ports.id = ipallocations.port_id"
    local stats=$(mysql -B -u root -D neutron -e "SELECT $cols FROM $joined_tables WHERE device_owner ='compute:nova'" | tail -n +2)
    for n in $(echo "$stats" | awk '{print $2}' | sort | uniq) ; do
        local n_name=$(mysql -B -u root -D neutron -e "SELECT name FROM networks WHERE id ='$n'" | tail -n +2)
        local netns_exec=
        if [ "$n_name" != "manila_service_network" ] ; then
            local netns_exec="/sbin/ip netns exec mgr-$(echo $n | cut -c 1-8)"
            local proj_ids=$(echo "$stats" | grep $n | awk '{print $5}'| sort | uniq)
            local cidrs=$(mysql -B -u root -D neutron -e "SELECT cidr FROM subnets WHERE network_id ='$n'" | tail -n +2)
            for p in $proj_ids ; do
                for c in $cidrs ; do
                    # echo $n $p $c $active_host $dbpass
                    ssh $r $HEX_SDK os_mgr_port_create $n $p $c $active_host $dbpass 2>/dev/null
                done
            done
        fi

        for ip in $(echo "$stats" | grep $n | awk '{print $4}') ; do
            local dev_id=$(echo "$stats" | grep "$n.*$ip\s" | awk '{print $3}')
            local resp_time=
            if [ "$proto" == "icmp" ] ; then
                resp_time=$(ssh $r $netns_exec ping -c 1 -w 1 $ip 2>/dev/null | tail -1 | awk '{print $4}' | cut -d '/' -f 2)
            else
                resp_time=$(ssh $r $netns_exec arping -c 1 -w 1 $ip 2>/dev/null | grep -i "reply from" | awk '{print $6}' | sed 's/[^0-9.]*//g')
            fi
            if [ -z "$resp_time" ] ; then
                resp_time=-1
            fi
            if [ "$format" == "line" ] ; then
                echo "vm.health,host=$HOSTNAME,proto=arping,id=$dev_id,ip=$ip resp=$resp_time"
            fi
        done
    done
}

os_purge_project()
{
    local noconfirm=

    while getopts "y" opt ; do
        case $opt in
            y) noconfirm=1 ;;
            *) exit 1 ;;
        esac
    done
    shift $(($OPTIND - 1))

    local project=$1
    local resources="--resource Backups --resource Snapshots --resource Volumes --resource Zones --resource Images --resource Stacks \
        --resource FloatingIPs --resource RouterInterfaces --resource Routers --resource Ports --resource Networks \
        --resource SecurityGroups --resource Servers --resource LoadBalancers  --resource Objects --resource Containers"
    # --resource Receivers --resource Policies --resource Clusters --resource Profiles

    $OPENSTACK project show "$project" || exit 1

    if [ -z "$noconfirm" ] ; then
        ospurge --dry-run --verbose --purge-project=$project $resources
        read -p "These resouces from project '$project' are going to be deleted. Enter 'Y' to confirm: " ans
        case $ans in
            Y) ;;
            *) echo "Canceled" ; exit 1 ;;
        esac
    fi

    ospurge --verbose --purge-project=$project $resources

    local errors=0

    for server_id in $($OPENSTACK server list --project $project -f json | jq -r .[].ID) ; do
        $OPENSTACK -v server delete $server_id || ((errors++))
    done

    for image_id in $($OPENSTACK image list --project $project -f json | jq -r .[].ID) ; do
        $OPENSTACK -v image delete $image_id || ((errors++))
    done

    for router_id in $($OPENSTACK router list --project $project -f json | jq -r .[].ID) ; do
        for port_id in $($OPENSTACK router show $router_id -f json | jq -r .interfaces_info[].port_id) ; do
            $OPENSTACK -v router remove port $router_id $port_id || ((errors++))
        done

        $OPENSTACK -v router delete $router_id || ((errors++))
    done

    for network_id in $($OPENSTACK network list --project $project -f json | jq -r .[].ID) ; do
        for port_id in $($OPENSTACK port list --network $network_id -f json | jq -r '.[].ID') ; do
            $OPENSTACK -v port delete $port_id || ((errors++))
        done

        $OPENSTACK -v network delete $network_id || ((errors++))
    done

    # Default security group may auto re-generate if project exists
    for sg_id in $($OPENSTACK security group list --project $project -f json | jq -r .[].ID) ; do
        $OPENSTACK -v security group delete $sg_id || ((errors++))
    done

    if (( $errors > 0 )) ; then
        echo "$errors resources are not cleaned. project '$project' is not deleted."
        exit 1
    fi

    $OPENSTACK -v project purge --project=$project
}

# params:
# $1: project_name
# $2: mgmt_network
# $3: pub_network
os_create_project()
{
    export PROJECT_NAME=$1
    export MGMT_NETWORK=${2:-public}
    export PUB_NETWORK=${3:-public}
    export PROJECT_PASSWORD=$(echo -n $PROJECT_NAME | openssl dgst -sha1 -hmac cube2022 | awk '{print $2}')
    export RANCHER_TOKEN=$($TERRAFORM_CUBE state pull | jq -r '.resources[] | select(.type == "rancher2_bootstrap").instances[0].attributes.token')
    local appfw_pth=/opt/appfw

    ansible-playbook $appfw_pth/ansible/openstack.yaml -e project=$PROJECT_NAME -e password=$PROJECT_PASSWORD -e mgmt_net=$MGMT_NETWORK -e pub_net=$PUB_NETWORK
}

os_light_osc()
{
    if [ "x$1" = "xon" ] ; then
        sed 's/export //' /etc/admin-openrc.sh > /tmp/os.rc
        docker rm -f osc >/dev/null 2>&1 || true
        docker run -d -t --name osc --env-file /tmp/os.rc localhost:5080/osc >/dev/null 2>&1
        rm -f /tmp/os.rc
        ln -sf /usr/bin/osc /usr/local/bin/openstack
    elif [ "x$1" = "xoff" ] ; then
        ln -sf /usr/bin/$OPENSTACK /usr/local/bin/openstack
        docker rm -f osc >/dev/null 2>&1 || true
    else
        echo "usage: $0 os_light_osc on|off"
    fi
}

os_calibrate_nova_resources()
{
    local ids=$($OPENSTACK server list --all-project --host $HOSTNAME -f value -c ID)

    # calibrate nova/instances folder states from previous power loss
    for id_dir in $(ls -1 /var/lib/nova/instances/ | grep ".*[-].*[-].*[-].*") ; do
        echo ${ids:-EMPTY} | grep -q $id_dir || rm -rf /var/lib/nova/instances/$id_dir
    done
}

os_resume_hypervisor()
{
    if nova hypervisor-list | grep -q disabled ; then
        for u in $($OPENSTACK segment list -f value -c uuid) ; do
            for n in $($OPENSTACK segment host list $u -f value -c name) ; do
                if [ "x$n" = "x$(hostname)" ] ; then
                    $OPENSTACK segment host update $u $(hostname) --on_maintenance False
                    $OPENSTACK compute service set --enable $(hostname) nova-compute
                fi
            done
        done

        # Let users decide if they want to hard-reboot instances
        # echo YES | hex_cli -c iaas compute reset All
    fi
}

os_maintain_segment_hosts()
{
    for u in $($OPENSTACK segment list -f value -c uuid) ; do
        for n in $($OPENSTACK segment host list $u -f value -c name) ; do
            $OPENSTACK segment host update $u $n --on_maintenance True
        done
    done
}

os_device_profile_create()
{
    local units=${1:-1}

    OLDIFS="$IFS"
    IFS=$'\n'
    for d in $($OPENSTACK accelerator device list -f value -c vendor -c std_board_info | sort | uniq) ; do
        if echo $d | grep -q "^10de " ; then
            pid=$(echo $d | awk '{ s = "" ; for (i = 2 ; i <= NF ; i++) s = s $i " " ; print s }' | jq -r .product_id | tr '[:lower:]' '[:upper:]')
            uuid=$($OPENSTACK accelerator device list -f value -c uuid -c vendor -c std_board_info | grep $d | head -1 | awk '{print $1}')
            model=$($OPENSTACK accelerator device show -f json $uuid | jq -r .model)
            name=$(echo $model | awk -F'[' '{print $2}' | awk -F']' '{print $1}' | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
            if ! $OPENSTACK accelerator device profile list -f value -c name | grep -q "${name}_${units}" ; then
                echo "Creating device profile for $model (resource unit: $units)"
                profile="["
                for i in $(seq $units) ; do
                    if [ "$i" -gt "1" ] ; then
                        profile="${profile},"
                    fi
                    profile="${profile}{\"resources:PGPU\": 1, \"trait:CUSTOM_GPU_PRODUCT_ID_$pid\": \"required\", \"trait:CUSTOM_GPU_NVIDIA\": \"required\"}"
                done
                profile="${profile}]"

                $OPENSTACK accelerator device profile create ${name}_${units} "$profile"
            fi
        fi
    done
    IFS="$OLDIFS"
}

os_device_profile_delete()
{
    $OPENSTACK accelerator device profile delete $1 2>/dev/null
}

os_nova_gpu_server_list()
{
    for fid in $($OPENSTACK flavor list --long --all -f value -c ID -c Properties | grep "accel:device_profile" | awk '{print $1}') ; do
        local list=$($OPENSTACK server list --all-project -f value -c Name -c ID -c Flavor -c Host --flavor $fid)
        if [ -n "$list" ] ; then
            if [ "$VERBOSE" == "1" ] ; then
                echo "$list" | awk '{printf "%-60s (ID: %s, Host: %s, Flavor: %s)\n", $2, $1, $4, $3}'
            else
                echo "$list" | awk '{print $1}'
            fi
        fi
    done
}

os_nova_pgpu_host_list_by_instance_id()
{
    local instance_id=$1

    local arqs_state=$($OPENSTACK accelerator arq list -f value -c uuid -c device_profile_name -c instance_uuid | grep $instance_id)
    if [ -z "$arqs_state" ] ; then
        return 0
    fi

    local orig_host=$($OPENSTACK server show $instance_id -c hypervisor_hostname -f value)
    local arq_state=$(echo "$arqs_state" | head -1)
    local gcount=$(echo "$arqs_state" | wc -l)
    local arq=$(echo $arq_state | awk '{print $1}')
    local device_profile=$(echo $arq_state | awk '{print $2}')

    # e.g. [{'resources:PGPU': '1', 'trait:CUSTOM_GPU_PRODUCT_ID_2531': 'required', 'trait:CUSTOM_GPU_NVIDIA': 'required'}]
    local dp_attrs=$($OPENSTACK accelerator device profile list -f value -c name -c groups | grep $device_profile | awk '{ s = "" ; for (i = 2 ; i <= NF ; i++) s = s $i " " ; print s }')
    # e.g. 1
    local gnum=$(echo $dp_attrs | awk -F"'|:" '{print $6}')
    # e.g. CUSTOM_GPU_PRODUCT_ID_2531
    local gid=$(echo $dp_attrs | awk -F"'|:" '{print $9}')
    # e.g. CUSTOM_GPU_NVIDIA
    local gvendor=$(echo $dp_attrs | awk -F"'|:" '{print $15}')

    declare -A hosts
    declare -A rpids

    for rp in $($OPENSTACK allocation candidate list --resource PGPU=1 -f value -c "resource provider" -c traits | grep "$gvendor.*$gid" | awk '{print $1}' | sort) ; do
        local host=$(/usr/bin/mysql -u root -D placement -e "select uuid,name from resource_providers where uuid='$rp'" | grep $rp | awk '{print $2}' | awk -F"_" '{print $1}')
        (( hosts[$host]++ ))
        if [ "${hosts[${host}]}" -le "$gcount" ] ; then
            rpids[$host]="${rpids[${host}]},$rp"
        fi
    done

    for key in ${!hosts[@]} ; do
        if [ "${hosts[${key}]}" -ge "$gcount" -a "$key" != "$orig_host" ] ; then
            if [ "$VERBOSE" == "1" ] ; then
                echo "${key} (${hosts[${key}]} matched GPUs. Picked RPs=${rpids[${key}]#?})"
            else
                echo "${key}_${rpids[${key}]#?}"
            fi
        fi
    done
}

os_instance_pgpu_migrate()
{
    local instance_id=$1
    local host=$(echo $2 | awk -F"_" '{print $1}')
    local rps=$(echo $2 | awk -F"_" '{print $2}')
    local arqs_state=$($OPENSTACK accelerator arq list -f value -c uuid -c device_profile_name -c instance_uuid | grep $instance_id)
    local device_profile=$(echo "$arqs_state" | head -1 | awk '{print $2}')
    local gnum=$(echo $device_profile | awk -F"_" '{print $NF}')

    echo -n "unbinding accelerator from the original host ... "
    for arq in $(echo "$arqs_state" | awk '{print $1}') ; do
        $OPENSTACK accelerator arq unbind $arq >/dev/null 2>&1
        $OPENSTACK accelerator arq delete $arq >/dev/null 2>&1
    done
    $OPENSTACK resource provider allocation unset --resource-class PGPU $instance_id >/dev/null 2>&1
    echo "done"

    echo -n "migrating to host $host... "
    $OPENSTACK server migrate --os-compute-api-version 2.56 --host $host --wait $instance_id >/dev/null 2>&1
    $OPENSTACK server migration confirm $instance_id >/dev/null 2>&1
    echo "done"

    echo -n "binding accelerator of $host... "
    local ins_state=$($OPENSTACK server show -f value -c project_id -c user_id $instance_id)
    local project_id=$(echo $ins_state | awk '{print $1}')
    local user_id=$(echo $ins_state | awk '{print $2}')

    $OPENSTACK accelerator arq create $device_profile >/dev/null 2>&1
    local arqs=$($OPENSTACK accelerator arq list -f value -c state -c device_profile_name -c uuid | grep "Initial.*$device_profile" | awk '{print $1}')
    local arq_arr=($arqs)
    local alloc_str=
    local idx=0
    for rp in $(echo $rps | tr ',' ' ') ; do
        $OPENSTACK accelerator arq bind ${arq_arr[${idx}]} $host $instance_id $rp $project_id >/dev/null 2>&1
        alloc_str="$alloc_str --allocation rp=$rp,PGPU=1"
        idx=$(( idx + 1 ))
    done
    $OPENSTACK resource provider allocation set --project-id $project_id --user-id $user_id $alloc_str $instance_id >/dev/null 2>&1
    echo "done"

    echo -n "hard rebooting the instance ... "
    $OPENSTACK server reboot --hard --wait $instance_id >/dev/null 2>&1
    echo "done"

    $OPENSTACK server show -c id -c hostname -c hypervisor_hostname -c addresses $instance_id
}
