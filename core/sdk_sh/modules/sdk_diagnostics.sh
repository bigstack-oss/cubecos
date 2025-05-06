# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

_diagProjCreate()
{
    project_id=$($OPENSTACK project list --long -f json | jq -r ".[] | select(.Name==\"$project_name\") | .ID")

    if [ -n "$project_id" ] ; then
        printf "%s: %s (%s)\n" "Reuse project" $project_name $project_id
    else
        project_id=$($OPENSTACK project create $project_name -f value -c id)
        $OPENSTACK role add --user 'admin (IAM)' --project $project_name admin >/dev/null 2>&1 || true
        printf "%s: %s (%s)\n" "Created project" $project_name $project_id
    fi
}

_diagProjDelete()
{
    project_id=$($OPENSTACK project list --long -f json | jq -r ".[] | select(.Name==\"$project_name\") | .ID")
    $OPENSTACK project delete $project_id 2>/dev/null || true
    printf "%s: %s (%s)\n" "Deleted project" $project_name $project_id
}

_diagNetCreate()
{
    network_ext_id=$($OPENSTACK network list --long -f json | jq -r ".[] | select(.Name==\"$network_ext_name\") | .ID")
    if [ "${network_ext_id:-null}" = "null" ] ; then
        network_ext_id=$($OPENSTACK network create --project $project_name --external --enable --share --provider-network-type flat --provider-physical-network provider $network_ext_name -f value -c id)
        if [ -z "$network_ext_id" ] ; then
            echo "Usage: _diagNetCreate EXT_NETWORK" && exit 1
        fi
        cnt=0 ; while ! ( $OPENSTACK network list --project $project_name --long | grep $network_ext_name | grep -q ACTIVE ) ; do [ $((cnt++)) -lt 10 ] || exit 1 ; done
        printf "%s: %s (%s)\n" "Created external network" $network_ext_name $network_ext_id
    else
        printf "%s: %s (%s)\n" "Reuse external network" $network_ext_name $network_ext_id
    fi
    if [ $($OPENSTACK network show $network_ext_id -f json | jq -r ".shared") != "true" ] ; then
        echo "EXTERNAL NETWORK $network_ext_name is not shared" && exit 1
    fi

    subnet_ext_id=$($OPENSTACK network show $network_ext_id -f json | jq -r ".subnets[0]")
    if [ "${subnet_ext_id:-null}" = "null" ] ; then
        subnet_ext_id=$($OPENSTACK subnet create --project $project_name $subnet_ext_name --gateway 10.1.0.254 --network $network_ext_name --subnet-range 10.1.0.0/16 --allocation-pool start=10.1.99.1,end=10.1.99.254 -f value -c id)
        cnt=0 ; while ! ( $OPENSTACK subnet list --project $project_name | grep -q $subnet_ext_name ) ; do [ $((cnt++)) -lt 10 ] || exit 1 ; done
        printf "%s: %s (%s)\n" "Created external subnet" $subnet_ext_name $subnet_ext_id
    else
        subnet_ext_name=$($OPENSTACK subnet show $subnet_ext_id -f json | jq -r ".name")
        printf "%s: %s (%s)\n" "Reuse external subnet" $subnet_ext_name $subnet_ext_id
    fi

    network_int_id=$($OPENSTACK network list --project $project_name --long -f json | jq -r ".[] | select(.Name==\"$network_int_name\") | .ID")
    if [ "${network_int_id:-null}" = "null" ] ; then
        network_int_id=$($OPENSTACK network create --project $project_name --internal --enable --no-share --provider-network-type geneve $network_int_name -f value -c id)
        cnt=0 ; while ! ( $OPENSTACK network list --project $project_name --long | grep $network_int_name | grep -q ACTIVE ) ; do [ $((cnt++)) -lt 10 ] || exit 1 ; done
        printf "%s: %s (%s)\n" "Created internal network" $network_int_name $network_int_id
    else
        printf "%s: %s (%s)\n" "Reuse internal network" $network_int_name $network_int_id
    fi

    subnet_int_id=$($OPENSTACK network show $network_int_id -f json | jq -r ".subnets[0]")
    if [ "${subnet_int_id:-null}" = "null" ] ; then
        subnet_int_id=$($OPENSTACK subnet create --project $project_name $subnet_int_name --gateway auto --network $network_int_id --subnet-range 192.168.0.0/24 -f value -c id)
        cnt=0 ; while ! ( $OPENSTACK subnet list --project $project_name | grep -q $subnet_int_name ) ; do [ $((cnt++)) -lt 10 ] || exit 1 ; done
        printf "%s: %s (%s)\n" "Created internal subnet" $subnet_int_name $subnet_int_id
    else
        subnet_int_name=$($OPENSTACK subnet show $subnet_int_id -f json | jq -r ".name")
        printf "%s: %s (%s)\n" "Reuse internal subnet" $subnet_int_name $subnet_int_id
    fi

    router_e2i_id=$($OPENSTACK router list --project $project_name --long -f json | jq -r ".[] | select(.Name==\"$router_e2i_name\") | .ID")
    if [ "${router_e2i_id:-null}" = "null" ] ; then
        router_e2i_id=$($OPENSTACK router create --project $project_name $router_e2i_name -f value -c id)
        cnt=0 ; while ! ( $OPENSTACK router list --project $project_name --long | grep $router_e2i_name | grep -q ACTIVE ) ; do [ $((cnt++)) -lt 10 ] || exit 1 ; done
        printf "%s: %s (%s)\n" "Created e2i router" $router_e2i_name $router_e2i_id

        $OPENSTACK router set $router_e2i_id --external-gateway $network_ext_name
        printf "%s: %s (%s)\n" "Set router gw" $router_e2i_name $router_e2i_id
        cnt=0 ; while ! ( $OPENSTACK router show -f shell $router_e2i_id | grep -q external_gateway_info ) ; do [ $((cnt++)) -lt 10 ] || exit 1 ; done

        $OPENSTACK router add subnet $router_e2i_id $subnet_int_id
        printf "%s: %s (%s)\n" "Added router subnet" $router_e2i_name $router_e2i_id
        cnt=0 ; while ! ( $OPENSTACK router show -f shell $router_e2i_id | grep subnet | grep -q "192[.]168[.]0[.]1" ) ; do [ $((cnt++)) -lt 10 ] || exit 1 ; done
    else
        printf "%s: %s (%s)\n" "Reuse e2i router" $router_e2i_name $router_e2i_id
    fi
}

_diagNetDelete()
{
    router_e2i_id=$($OPENSTACK router list --project $project_name --long -f json | jq -r ".[] | select(.Name==\"$router_e2i_name\") | .ID")
    subnet_int_id=$($OPENSTACK subnet list --project $project_name --long -f json | jq -r ".[] | select(.Name==\"$subnet_int_name\") | .ID")
    network_int_id=$($OPENSTACK network list --project $project_name --long -f json | jq -r ".[] | select(.Name==\"$network_int_name\") | .ID")
    subnet_ext_id=$($OPENSTACK subnet list --project $project_name --long -f json | jq -r ".[] | select(.Name==\"$subnet_ext_name\") | .ID")
    [ "$network_ext_name" = "_external-network" ] || network_ext_id=$($OPENSTACK network list --project $project_name --long -f json | jq -r ".[] | select(.Name==\"$network_ext_name\") | .ID")

    if [ -n "$router_e2i_id" ] ; then
        $OPENSTACK router remove subnet $router_e2i_id $subnet_int_id || true
        printf "%s: %s (%s)\n" "Removed router subnet" $router_e2i_name $subnet_int_name
        $OPENSTACK router unset --external-gateway $router_e2i_id || true
        printf "%s: %s (%s)\n" "Unset router gw" $router_e2i_name $network_ext_name
        $OPENSTACK router delete $router_e2i_id || true
        printf "%s: %s (%s)\n" "Deleted router" $router_e2i_name $router_e2i_id
    fi

    # delete all ports in this project
    $OPENSTACK port list --project $project_name -f value -c ID 2>/dev/null | xargs -i $OPENSTACK port delete {}

    if [ -n "$subnet_int_id" ] ; then
        $OPENSTACK subnet delete $subnet_int_id || true
        printf "%s: %s (%s)\n" "Deleted subnet" $subnet_int_name $subnet_int_id
    fi

    if [ -n "$network_int_id" ] ; then
        $OPENSTACK network delete $network_int_id || true
        printf "%s: %s (%s)\n" "Deleted network" $network_int_name $network_int_id
    fi

    if [ -n "$subnet_ext_id" ] ; then
        $OPENSTACK subnet delete $subnet_ext_id || true
        printf "%s: %s (%s)\n" "Deleted subnet" $subnet_ext_name $subnet_ext_id
    fi

    if [ -n "$network_ext_id" ] ; then
        $OPENSTACK network delete $network_ext_id || true
        printf "%s: %s (%s)\n" "Deleted network" $network_ext_name $network_ext_id
    fi
}

_diagSrvCreate()
{
    local project_name="_diagnostics"
    local image_name=${1:-Cirros}
    local network_name=${2:-public}
    local backpool=${3:-$BUILTIN_BACKPOOL}
    if [ "$backpool" = "$BUILTIN_BACKPOOL" ] ; then
        local flag="--boot-from-volume 160"
    else
        local flag=
    fi
    local num_per_compute=${4:-1}

    local image_id=$($OPENSTACK image list --long -f json | jq -r ".[] | select(.Name==\"$image_name\") | .ID")
    local network_id=$($OPENSTACK network list --project $project_name --long -f json | jq -r ".[] | select(.Name==\"$network_name\") | .ID")
    [ -n "$network_id" ] || network_id=$($OPENSTACK network list --long -f json | jq -r ".[] | select(.Name==\"$network_name\") | .ID")
    if [ -z "$image_id" -o -z "$network_id" ] ; then
        echo "Usage $0 IMAGE_NAME NETWORK_NAME" && exit 1
    fi

    admin_dft_sg=$($OPENSTACK security group list --project admin --format value -c ID -c Name | grep default | cut -d" " -f1)
    $OPENSTACK security group rule create $admin_dft_sg --protocol icmp --remote-ip 0.0.0.0/0 >/dev/null 2>&1 || true
    $OPENSTACK security group rule create $admin_dft_sg --protocol tcp --dst-port 22:22 --remote-ip 0.0.0.0/0 >/dev/null 2>&1 || true
    $OPENSTACK role add --user admin_cli --project $project_name admin

    compute_num=${#CUBE_NODE_COMPUTE_HOSTNAMES[@]}
    local compute_cnt=0
    local server_list_json=$($OPENSTACK server list --project $project_name -f json -c Name -c ID)
    local server_id_array=()
    local index=0
    for node in "${CUBE_NODE_COMPUTE_HOSTNAMES[@]}" ; do
        ((compute_cnt++))
        cnt_per_compute=0
        for n in $(seq $num_per_compute) ; do
            ((cnt_per_compute++))
            if [ $compute_cnt -ge $compute_num -a $cnt_per_compute -ge $num_per_compute ] ; then
                flag+=" --wait"
            fi
            local server_name="${backpool}_${node}-${n}"
            if echo $server_list_json | jq -r .[].Name 2>/dev/null | grep -q $server_name ; then
                printf "%s: %s (%s)\n" "Reuse server" $server_name "$(echo $server_list_json | jq -r ".[] | select(.Name==\"$server_name\").ID")"
            else
                server_id_array[$((index++))]=$(OS_PROJECT_NAME=$project_name $OPENSTACK --os-compute-api-version 2.74 server create --hypervisor-hostname ${node} --nic net-id=${network_id} --flavor t2.diagnostics --image $image_id $flag $server_name -f value -c id)
            fi
        done
    done
    server_list_json=$($OPENSTACK server list --project $project_name -f json -c Name -c ID)
    for sid in ${server_id_array[@]} ; do
        sn=$(echo $server_list_json | jq -r ".[] | select(.ID==\"$sid\").Name")
        echo -n "Creating ${sn:-unknown} "
        cubectl node exec -r compute -pn -- "grep -a $sid /var/log/nova/nova-compute.log | grep -o '\[instance: .* Took .* to build instance'" | grep Took || echo "[instance: $sid] Failed to build instance"
    done
}

_diagSrvDelete()
{
    local project_name="_diagnostics"
    $OPENSTACK server list --project $project_name -f value -c ID 2>/dev/null | xargs -i $OPENSTACK server delete {}
    $OPENSTACK volume list --project $project_name -f value -c ID 2>/dev/null | xargs -i $OPENSTACK volume delete {}
}

_diagSrvShiftHost()
{
    local project_name="_diagnostics"

    local server_list_json=$($OPENSTACK server list --project $project_name --long -f json)
    local host_array=($(cubectl node -r compute list -j | jq -r .[].hostname))
    local num_host=${#host_array[@]}
    for I in $(seq 0 $((num_host - 1))) ; do
        local from_host="${host_array[$I]}"
        local to_host="${host_array[$(( (I + 1) % $num_host ))]}"
        for server_id in $(echo $server_list_json | jq -r ".[] | select(.Host==\"$from_host\") | .ID") ; do
            server_name=$(echo $server_list_json | jq -r ".[] | select(.ID==\"$server_id\") | .Name")
            printf "%s: %s (%s)\n" "Migrating VM from $from_host to $to_host" $server_name $server_id
            nova live-migration $server_id $to_host
        done
    done
    for I in $(seq 0 $((num_host - 1))) ; do
        local from_host="${host_array[$I]}"
        local to_host="${host_array[$(( (I + 1) % $num_host ))]}"
        for server_id in $(echo $server_list_json | jq -r ".[] | select(.Host==\"$from_host\") | .ID") ; do
            server_name=$(echo $server_list_json | jq -r ".[] | select(.ID==\"$server_id\") | .Name")
            for i in {1..10} ; do
                new_host=$($OPENSTACK server list --project $project_name --long -f json | jq -r ".[] | select(.ID==\"$server_id\") | .Host")
                if [ "$new_host" = "$from_host" ] ; then
                    continue
                else
                    break
                fi
            done
            new_host=$($OPENSTACK server list --project $project_name --long -f json | jq -r ".[] | select(.ID==\"$server_id\") | .Host")
            if [ "$new_host" = "$to_host" ] ; then
                printf "%s: %s (%s)\n" "Migrated VM from $from_host to $to_host" $server_name $server_id
            else
                printf "%s: %s (%s)\n" "Failed to migrate VM from $from_host to $to_host" $server_name $server_id && break
            fi
        done
    done
    sleep 10 # allow instances to finish booting after migration
}

_diagFlvrCreate()
{
    local flavor=${1:-t2.diagnostics}
    $OPENSTACK flavor show $flavor >/dev/null 2>&1 || $OPENSTACK flavor create --vcpus 2 --ram 4096 --disk 80 --public $flavor >/dev/null
}

_diagFlvrDelete()
{
    local flavor=${1:-t2.diagnostics}
    $OPENSTACK flavor delete $flavor
}

_diagQuotaUnlimit()
{
    local project_name="_diagnostics"
    $OPENSTACK quota set --force --volumes -1 $project_name
    $OPENSTACK quota set --force --gigabytes -1 $project_name
    $OPENSTACK quota set --force --instances -1 $project_name
    $OPENSTACK quota set --force --cores -1 $project_name
    $OPENSTACK quota set --force --ram -1 $project_name
}
diagnostics_network()
{
    local project_name="_diagnostics"
    local network_ext_name=${1:-"_external-network"}
    local domain_name=${2:-www.google.com}
    local name_server=${3:-8.8.8.8}
    local subnet_ext_name="_external-subnet"
    local network_int_name="_internal-network"
    local subnet_int_name="_internal-subnet"
    local router_e2i_name="_router-e2i"

    _diagProjCreate
    _diagNetCreate
    _diagFlvrCreate
    _diagQuotaUnlimit

    _diagSrvCreate Cirros $network_ext_name ephemeral-vms
    _diagnostics_instance_dns $domain_name $name_server
    if [ $(cubectl node list -r compute | wc -l) -gt 1 ] ; then
        _diagSrvShiftHost
        _diagnostics_instance_dns $domain_name $name_server
    fi
    _diagSrvDelete

    _diagSrvCreate Cirros $network_int_name
    _diagnostics_instance_dns $domain_name $name_server
    if [ $(cubectl node list -r compute | wc -l) -gt 1 ] ; then
        _diagSrvShiftHost
        _diagnostics_instance_dns $domain_name $name_server
    fi
}

diagnostics_teardown()
{
    local project_name="_diagnostics"
    local subnet_ext_name="_external-subnet"
    local network_int_name="_internal-network"
    local subnet_int_name="_internal-subnet"
    local router_e2i_name="_router-e2i"
    local network_ext_name="_external-network"

    project_id=$($OPENSTACK project list --long -f json | jq -r ".[] | select(.Name==\"$project_name\") | .ID")
    [ -n "$project_id" ] || exit 0

    _diagSrvDelete
    _diagNetDelete
    _diagProjDelete
    _diagFlvrDelete
}

diagnostics_rbd()
{
    local pool=${1:-$BUILTIN_BACKPOOL}
    local type=${2:-write}
    local szgb=${3:-1}
    local rimg=$(mktemp -u rbd-bench-img.XXXX)
    local rdev=/dev/rbd/$pool/$rimg
    local rmnt=/tmp/$rimg

    rbd create $rimg --size $((szgb * 1024 + 1024)) --pool $pool
    rbd map $rimg --pool $pool >/dev/null
    mkfs.ext4 /dev/rbd/$pool/$rimg >/dev/null 2>&1
    mkdir $rmnt
    mount $rdev $rmnt
    rbd bench --io-type $type --io-total ${szgb}G $rimg --pool=$pool
    umount $rmnt
    rbd unmap $rimg --pool $pool
    rmdir $rmnt
}

diagnostics_osd_hdparm()
{
    local osdid=${1#osd.}
    if [ -s $CEPH_OSD_MAP ] ; then
        while read -r line ; do
            dev=$(echo $line | cut -d" " -f1)
            oid=$(echo $line | cut -d" " -f2)
            if [ "x$osdid" = "x$oid" ] ; then
                hdparm -tT $dev | grep -v '/dev/'
                break
            fi
        done < $CEPH_OSD_MAP
    fi
}

_diagnostics_instance_dns()
{
    local project_name="_diagnostics"
    local domain_name=${1:-www.google.com}
    local name_server=${2:-8.8.8.8}

    cubectl node exec -r compute -p "$HEX_SDK diagnostics_cirros_host_exec \"nslookup $domain_name $name_server ; ping $name_server -c 3\""
}

_diagnostics_instance_dd()
{
    local szgb=${1:-1}

    [ $szgb -lt 150 ] || Error "Test data size $szgb GB can not be bigger 150"
    local bs=1M
    local count=$((szgb * 1024))
    cubectl node exec -r compute -p "$HEX_SDK diagnostics_cirros_host_exec \"rm -f ./test.file ; time dd if=/dev/zero of=./test.file bs=$bs count=$count ; ls -lt\""
}

_diagnostics_server_list()
{
    local project_name="_diagnostics"
    $OPENSTACK server list --project _diagnostics -c Host -c Name -c Networks -c Flavor -c Image
}

diagnostics_cirros_host_exec()
{
    local project_name="_diagnostics"
    local server_list_json=$($OPENSTACK server list --project $project_name --host $HOSTNAME --long -f json)
    local index=0

    for server_id in $(echo $server_list_json | jq -r .[].ID) ; do
        server_show_json=$($OPENSTACK server show $server_id -f json)
        svr_names[$index]="$(echo $server_show_json | jq -r .hostname)"
        ins_names[$((index++))]="$(echo $server_show_json | jq -r .instance_name)"
    done

    local log="/tmp/_${FUNCNAME[0]}"
    for ins_name in ${ins_names[@]} ; do
        $HEX_SDK diagnostics_cirros_exec $ins_name $@ >${log}.${ins_name} 2>&1 &
        proc_ids+="$! "
    done
    wait $proc_ids

    for ins_name in ${ins_names[@]} ; do
        echo "---- Outputs from $svr_names (${ins_name}) on $HOSTNAME----"
        cat ${log}.${ins_name}
        echo
        rm -f ${log}.${ins_name}
    done
}

diagnostics_cirros_exec()
{
    local ins=${1:-NOSUCHINSTANCE}
    shift 1
    local cmd="$*"
    local user="cirros"
    local pass="gocubsgo"
    virsh list | grep -q $ins || return 0

    expect -c "
set timeout 10
log_user 0
spawn virsh console $ins
expect_before timeout { exit 1 }
match_max 100000

expect \"*Connected to domain\"
send -- \"
\"
log_user 1
expect {
    -re \".*login: $\" {
        send -- \"$user\n\"
        expect {
            -timeout 3
            -re \".*login: $\" { send -- \"$user\n\" ; expect -re \".*assword: $\" }
            -re \".*assword: $\" { send -- \"$pass\n\" }
        }

    }
    \"*$ \" { send -- \"\n\" }
    timeout { puts \"failed to run cirros exec in instance $ins\" ; exit 1 }
}
expect \"*$ \"
set timeout 600
send -- \"$cmd
\"
expect \"*$ \"
"
}

diagnostics_arpscan_report()
{
    for log in /run/arpscan.* ; do
        [ -e $log ] || continue

        declare -A ips_macs
        echo && echo "[NODE: $HOSTNAME] [INTERFACE: ${log##*.}]"
        while read -r line ; do
            ip=$(echo $line | awk '{print $1}')
            mac=$(echo $line | awk '{print $2}')
            if [ "x${ips_macs[$ip]}" != "x" -a "x${ips_macs[$ip]}" != "x$mac" ] ; then
                echo "$ip ${ips_macs[$ip]} conflicts $mac"
            else
                if [ "$VERBOSE" == "1" ] ; then
                    echo "$ip $mac"
                fi
            fi
            ips_macs[$ip]=$mac
        done < $log
    done
}

diagnostics_arpscan()
{
    for node_ip in ${CUBE_NODE_LIST_IPS[@]} ; do
        ifcs+="$(ip r sh match $node_ip | grep -o 'dev .*' | cut -d ' ' -f 2 | sort -u | tr '\n' ' ') "
    done
    for ifc in $(echo "$ifcs" | tr ' ' '\n' | sort | uniq) ; do
        ( arp-scan -I $ifc -l -x -q | sort | uniq >/run/arpscan.${ifc} ) &
        ifcs_pids[$ifc]=$!
    done
    for ifc in ${!ifcs_pids[@]} ; do
        wait ${ifcs_pids[$ifc]}
    done
}
