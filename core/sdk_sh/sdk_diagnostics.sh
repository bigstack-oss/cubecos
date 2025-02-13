# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ]; then
    echo "Error: PROG not set" >&2
    exit 1
fi

_diagProjCreate()
{
    PROJECT_ID=$(openstack project list --long -f json | jq -r ".[] | select(.Name==\"$PROJECT_NAME\") | .ID")

    if [ -n "$PROJECT_ID" ]; then
        printf "%s: %s (%s)\n" "Reuse project" $PROJECT_NAME $PROJECT_ID
    else
        PROJECT_ID=$(openstack project create $PROJECT_NAME -f value -c id)
        openstack role add --user 'admin (IAM)' --project $PROJECT_NAME _member_ >/dev/null 2>&1 || true
        printf "%s: %s (%s)\n" "Created project" $PROJECT_NAME $PROJECT_ID
    fi
}

_diagProjDelete()
{
    PROJECT_ID=$(openstack project list --long -f json | jq -r ".[] | select(.Name==\"$PROJECT_NAME\") | .ID")
    openstack project delete $PROJECT_ID 2>/dev/null || true
    printf "%s: %s (%s)\n" "Deleted project" $PROJECT_NAME $PROJECT_ID
}

_diagNetCreate()
{
    NETWORK_EXT_ID=$(openstack network list --long -f json | jq -r ".[] | select(.Name==\"$NETWORK_EXT_NAME\") | .ID")
    if [ "${NETWORK_EXT_ID:-null}" = "null" ]; then
        NETWORK_EXT_ID=$(openstack network create --project $PROJECT_NAME --external --enable --share --provider-network-type flat --provider-physical-network provider $NETWORK_EXT_NAME -f value -c id)
        if [ -z "$NETWORK_EXT_ID" ]; then
            echo "Usage: _diagNetCreate EXT_NETWORK" && exit 1
        fi
        CNT=0; while ! ( openstack network list --project $PROJECT_NAME --long | grep $NETWORK_EXT_NAME | grep -q ACTIVE ); do [ $((CNT++)) -lt 10 ] || exit 1 ; done
        printf "%s: %s (%s)\n" "Created external network" $NETWORK_EXT_NAME $NETWORK_EXT_ID
    else
        printf "%s: %s (%s)\n" "Reuse external network" $NETWORK_EXT_NAME $NETWORK_EXT_ID
    fi
    if [ $(openstack network show $NETWORK_EXT_ID -f json | jq -r ".shared") != "true" ]; then
        echo "EXTERNAL NETWORK $NETWORK_EXT_NAME is not shared" && exit 1
    fi

    SUBNET_EXT_ID=$(openstack network show $NETWORK_EXT_ID -f json | jq -r ".subnets[0]")
    if [ "${SUBNET_EXT_ID:-null}" = "null" ]; then
        SUBNET_EXT_ID=$(openstack subnet create --project $PROJECT_NAME $SUBNET_EXT_NAME --gateway 10.1.0.254 --network $NETWORK_EXT_NAME --subnet-range 10.1.0.0/16 --allocation-pool start=10.1.99.1,end=10.1.99.254 -f value -c id)
        CNT=0; while ! ( openstack subnet list --project $PROJECT_NAME | grep -q $SUBNET_EXT_NAME ); do [ $((CNT++)) -lt 10 ] || exit 1 ; done
        printf "%s: %s (%s)\n" "Created external subnet" $SUBNET_EXT_NAME $SUBNET_EXT_ID
    else
        SUBNET_EXT_NAME=$(openstack subnet show $SUBNET_EXT_ID -f json | jq -r ".name")
        printf "%s: %s (%s)\n" "Reuse external subnet" $SUBNET_EXT_NAME $SUBNET_EXT_ID
    fi

    NETWORK_INT_ID=$(openstack network list --project $PROJECT_NAME --long -f json | jq -r ".[] | select(.Name==\"$NETWORK_INT_NAME\") | .ID")
    if [ "${NETWORK_INT_ID:-null}" = "null" ]; then
        NETWORK_INT_ID=$(openstack network create --project $PROJECT_NAME --internal --enable --no-share --provider-network-type geneve $NETWORK_INT_NAME -f value -c id)
        CNT=0; while ! ( openstack network list --project $PROJECT_NAME --long | grep $NETWORK_INT_NAME | grep -q ACTIVE ); do [ $((CNT++)) -lt 10 ] || exit 1 ; done
        printf "%s: %s (%s)\n" "Created internal network" $NETWORK_INT_NAME $NETWORK_INT_ID
    else
        printf "%s: %s (%s)\n" "Reuse internal network" $NETWORK_INT_NAME $NETWORK_INT_ID
    fi

    SUBNET_INT_ID=$(openstack network show $NETWORK_INT_ID -f json | jq -r ".subnets[0]")
    if [ "${SUBNET_INT_ID:-null}" = "null" ]; then
        SUBNET_INT_ID=$(openstack subnet create --project $PROJECT_NAME $SUBNET_INT_NAME --gateway auto --network $NETWORK_INT_ID --subnet-range 192.168.0.0/24 -f value -c id)
        CNT=0; while ! ( openstack subnet list --project $PROJECT_NAME | grep -q $SUBNET_INT_NAME ); do [ $((CNT++)) -lt 10 ] || exit 1 ; done
        printf "%s: %s (%s)\n" "Created internal subnet" $SUBNET_INT_NAME $SUBNET_INT_ID
    else
        SUBNET_INT_NAME=$(openstack subnet show $SUBNET_INT_ID -f json | jq -r ".name")
        printf "%s: %s (%s)\n" "Reuse internal subnet" $SUBNET_INT_NAME $SUBNET_INT_ID
    fi

    ROUTER_E2I_ID=$(openstack router list --project $PROJECT_NAME --long -f json | jq -r ".[] | select(.Name==\"$ROUTER_E2I_NAME\") | .ID")
    if [ "${ROUTER_E2I_ID:-null}" = "null" ]; then
        ROUTER_E2I_ID=$(openstack router create --project $PROJECT_NAME $ROUTER_E2I_NAME -f value -c id)
        CNT=0; while ! ( openstack router list --project $PROJECT_NAME --long | grep $ROUTER_E2I_NAME | grep -q ACTIVE ); do [ $((CNT++)) -lt 10 ] || exit 1 ; done
        printf "%s: %s (%s)\n" "Created e2i router" $ROUTER_E2I_NAME $ROUTER_E2I_ID

        openstack router set $ROUTER_E2I_ID --external-gateway $NETWORK_EXT_NAME
        printf "%s: %s (%s)\n" "Set router gw" $ROUTER_E2I_NAME $ROUTER_E2I_ID
        CNT=0; while ! ( openstack router show -f shell $ROUTER_E2I_ID | grep -q external_gateway_info ); do [ $((CNT++)) -lt 10 ] || exit 1 ; done

        openstack router add subnet $ROUTER_E2I_ID $SUBNET_INT_ID
        printf "%s: %s (%s)\n" "Added router subnet" $ROUTER_E2I_NAME $ROUTER_E2I_ID
        CNT=0; while ! ( openstack router show -f shell $ROUTER_E2I_ID | grep subnet | grep -q "192[.]168[.]0[.]1" ); do [ $((CNT++)) -lt 10 ] || exit 1 ; done
    else
        printf "%s: %s (%s)\n" "Reuse e2i router" $ROUTER_E2I_NAME $ROUTER_E2I_ID
    fi
}

_diagNetDelete()
{
    ROUTER_E2I_ID=$(openstack router list --project $PROJECT_NAME --long -f json | jq -r ".[] | select(.Name==\"$ROUTER_E2I_NAME\") | .ID")
    SUBNET_INT_ID=$(openstack subnet list --project $PROJECT_NAME --long -f json | jq -r ".[] | select(.Name==\"$SUBNET_INT_NAME\") | .ID")
    NETWORK_INT_ID=$(openstack network list --project $PROJECT_NAME --long -f json | jq -r ".[] | select(.Name==\"$NETWORK_INT_NAME\") | .ID")
    SUBNET_EXT_ID=$(openstack subnet list --project $PROJECT_NAME --long -f json | jq -r ".[] | select(.Name==\"$SUBNET_EXT_NAME\") | .ID")
    [ "$NETWORK_EXT_NAME" = "_external-network" ] || NETWORK_EXT_ID=$(openstack network list --project $PROJECT_NAME --long -f json | jq -r ".[] | select(.Name==\"$NETWORK_EXT_NAME\") | .ID")

    if [ -n "$ROUTER_E2I_ID" ]; then
        openstack router remove subnet $ROUTER_E2I_ID $SUBNET_INT_ID || true
        printf "%s: %s (%s)\n" "Removed router subnet" $ROUTER_E2I_NAME $SUBNET_INT_NAME
        openstack router unset --external-gateway $ROUTER_E2I_ID || true
        printf "%s: %s (%s)\n" "Unset router gw" $ROUTER_E2I_NAME $NETWORK_EXT_NAME
        openstack router delete $ROUTER_E2I_ID || true
        printf "%s: %s (%s)\n" "Deleted router" $ROUTER_E2I_NAME $ROUTER_E2I_ID
    fi

    # delete all ports in this project
    openstack port list --project $PROJECT_NAME -f value -c ID 2>/dev/null | xargs -i openstack port delete {}

    if [ -n "$SUBNET_INT_ID" ]; then
        openstack subnet delete $SUBNET_INT_ID || true
        printf "%s: %s (%s)\n" "Deleted subnet" $SUBNET_INT_NAME $SUBNET_INT_ID
    fi

    if [ -n "$NETWORK_INT_ID" ]; then
        openstack network delete $NETWORK_INT_ID || true
        printf "%s: %s (%s)\n" "Deleted network" $NETWORK_INT_NAME $NETWORK_INT_ID
    fi

    if [ -n "$SUBNET_EXT_ID" ]; then
        openstack subnet delete $SUBNET_EXT_ID || true
        printf "%s: %s (%s)\n" "Deleted subnet" $SUBNET_EXT_NAME $SUBNET_EXT_ID
    fi

    if [ -n "$NETWORK_EXT_ID" ]; then
        openstack network delete $NETWORK_EXT_ID || true
        printf "%s: %s (%s)\n" "Deleted network" $NETWORK_EXT_NAME $NETWORK_EXT_ID
    fi
}

_diagSrvCreate()
{
    local PROJECT_NAME="_diagnostics"
    local IMAGE_NAME=${1:-Cirros}
    local NETWORK_NAME=${2:-public}
    local BACKPOOL=${3:-$BUILTIN_BACKPOOL}
    if [ "$BACKPOOL" = "$BUILTIN_BACKPOOL" ]; then
        local FLAG="--boot-from-volume 160"
    else
        local FLAG=
    fi
    local NUM_PER_COMPUTE=${4:-1}

    local IMAGE_ID=$(openstack image list --long -f json | jq -r ".[] | select(.Name==\"$IMAGE_NAME\") | .ID")
    local NETWORK_ID=$(openstack network list --project $PROJECT_NAME --long -f json | jq -r ".[] | select(.Name==\"$NETWORK_NAME\") | .ID")
    [ -n "$NETWORK_ID" ] || NETWORK_ID=$(openstack network list --long -f json | jq -r ".[] | select(.Name==\"$NETWORK_NAME\") | .ID")
    if [ -z "$IMAGE_ID" -o -z "$NETWORK_ID" ]; then
        echo "Usage $0 IMAGE_NAME NETWORK_NAME" && exit 1
    fi

    ADMIN_DFT_SG=$(openstack security group list --project admin --format value -c ID -c Name | grep default | cut -d" " -f1)
    openstack security group rule create $ADMIN_DFT_SG --protocol icmp --remote-ip 0.0.0.0/0 >/dev/null 2>&1 || true
    openstack security group rule create $ADMIN_DFT_SG --protocol tcp --dst-port 22:22 --remote-ip 0.0.0.0/0 >/dev/null 2>&1 || true
    openstack role add --user admin_cli --project $PROJECT_NAME admin

    COMPUTE_NUM=$(cubectl node list -r compute -j | jq -r .[].hostname | wc -l)
    local COMPUTE_CNT=0
    local SERVER_LIST_JSON=$(openstack server list --project $PROJECT_NAME -f json -c Name -c ID)
    local SERVER_ID_ARRAY=()
    local INDEX=0
    for C in $(cubectl node list -r compute -j | jq -r .[].hostname); do
        ((COMPUTE_CNT++))
        CNT_PER_COMPUTE=0
        for N in $(seq $NUM_PER_COMPUTE); do
            ((CNT_PER_COMPUTE++))
            if [ $COMPUTE_CNT -ge $COMPUTE_NUM -a $CNT_PER_COMPUTE -ge $NUM_PER_COMPUTE ]; then
                FLAG+=" --wait"
            fi
            local SERVER_NAME="${BACKPOOL}_${C}-${N}"
            if echo $SERVER_LIST_JSON | jq -r .[].Name 2>/dev/null | grep -q $SERVER_NAME ; then
                printf "%s: %s (%s)\n" "Reuse server" $SERVER_NAME "$(echo $SERVER_LIST_JSON | jq -r ".[] | select(.Name==\"$SERVER_NAME\").ID")"
            else
                SERVER_ID_ARRAY[$((INDEX++))]=$(OS_PROJECT_NAME=$PROJECT_NAME openstack --os-compute-api-version 2.74 server create --hypervisor-hostname ${C} --nic net-id=${NETWORK_ID} --flavor t2.diagnostics --image $IMAGE_ID $FLAG $SERVER_NAME -f value -c id)
            fi
        done
    done
    SERVER_LIST_JSON=$(openstack server list --project $PROJECT_NAME -f json -c Name -c ID)
    for SID in ${SERVER_ID_ARRAY[@]} ; do
        SN=$(echo $SERVER_LIST_JSON | jq -r ".[] | select(.ID==\"$SID\").Name")
        echo -n "Creating ${SN:-unknown} "
        cubectl node exec -r compute -pn -- "grep -a $SID /var/log/nova/nova-compute.log | grep -o '\[instance: .* Took .* to build instance'" | grep Took || echo "[instance: $SID] Failed to build instance"
    done
}

_diagSrvDelete()
{
    local PROJECT_NAME="_diagnostics"
    openstack server list --project $PROJECT_NAME -f value -c ID 2>/dev/null | xargs -i openstack server delete {}
    openstack volume list --project $PROJECT_NAME -f value -c ID 2>/dev/null | xargs -i openstack volume delete {}
}

_diagSrvShiftHost()
{
    local PROJECT_NAME="_diagnostics"

    local SERVER_LIST_JSON=$(openstack server list --project $PROJECT_NAME --long -f json)
    local HOST_ARRAY=($(cubectl node -r compute list -j | jq -r .[].hostname))
    local NUM_HOST=${#HOST_ARRAY[@]}
    for I in $(seq 0 $((NUM_HOST - 1))); do
        local FROM_HOST="${HOST_ARRAY[$I]}"
        local TO_HOST="${HOST_ARRAY[$(( (I + 1) % $NUM_HOST ))]}"
        for SERVER_ID in $(echo $SERVER_LIST_JSON | jq -r ".[] | select(.Host==\"$FROM_HOST\") | .ID") ; do
            SERVER_NAME=$(echo $SERVER_LIST_JSON | jq -r ".[] | select(.ID==\"$SERVER_ID\") | .Name")
            printf "%s: %s (%s)\n" "Migrating VM from $FROM_HOST to $TO_HOST" $SERVER_NAME $SERVER_ID
            nova live-migration $SERVER_ID $TO_HOST
        done
    done
    for I in $(seq 0 $((NUM_HOST - 1))); do
        local FROM_HOST="${HOST_ARRAY[$I]}"
        local TO_HOST="${HOST_ARRAY[$(( (I + 1) % $NUM_HOST ))]}"
        for SERVER_ID in $(echo $SERVER_LIST_JSON | jq -r ".[] | select(.Host==\"$FROM_HOST\") | .ID") ; do
            SERVER_NAME=$(echo $SERVER_LIST_JSON | jq -r ".[] | select(.ID==\"$SERVER_ID\") | .Name")
            for i in {1..10}; do
                NEW_HOST=$(openstack server list --project $PROJECT_NAME --long -f json | jq -r ".[] | select(.ID==\"$SERVER_ID\") | .Host")
                if [ "$NEW_HOST" = "$FROM_HOST" ] ; then
                    continue
                else
                    break
                fi
            done
            NEW_HOST=$(openstack server list --project $PROJECT_NAME --long -f json | jq -r ".[] | select(.ID==\"$SERVER_ID\") | .Host")
            if [ "$NEW_HOST" = "$TO_HOST" ]; then
                printf "%s: %s (%s)\n" "Migrated VM from $FROM_HOST to $TO_HOST" $SERVER_NAME $SERVER_ID
            else
                printf "%s: %s (%s)\n" "Failed to migrate VM from $FROM_HOST to $TO_HOST" $SERVER_NAME $SERVER_ID && break
            fi
        done
    done
    sleep 10 # allow instances to finish booting after migration
}

_diagFlvrCreate()
{
    local FLAVOR=${1:-t2.diagnostics}
    openstack flavor show $FLAVOR >/dev/null 2>&1 || openstack flavor create --vcpus 2 --ram 4096 --disk 80 --public $FLAVOR >/dev/null
}

_diagFlvrDelete()
{
    local FLAVOR=${1:-t2.diagnostics}
    openstack flavor delete $FLAVOR
}

_diagQuotaUnlimit()
{
    local PROJECT_NAME="_diagnostics"
    openstack quota set --force --volumes -1 $PROJECT_NAME
    openstack quota set --force --gigabytes -1 $PROJECT_NAME
    openstack quota set --force --instances -1 $PROJECT_NAME
    openstack quota set --force --cores -1 $PROJECT_NAME
    openstack quota set --force --ram -1 $PROJECT_NAME
}
diagnostics_network()
{
    local PROJECT_NAME="_diagnostics"
    local NETWORK_EXT_NAME=${1:-"_external-network"}
    local DOMAIN_NAME=${2:-www.google.com}
    local NAME_SERVER=${3:-8.8.8.8}
    local SUBNET_EXT_NAME="_external-subnet"
    local NETWORK_INT_NAME="_internal-network"
    local SUBNET_INT_NAME="_internal-subnet"
    local ROUTER_E2I_NAME="_router-e2i"

    _diagProjCreate
    _diagNetCreate
    _diagFlvrCreate
    _diagQuotaUnlimit

    _diagSrvCreate Cirros $NETWORK_EXT_NAME ephemeral-vms
    _diagnostics_instance_dns $DOMAIN_NAME $NAME_SERVER
    if [ $(cubectl node list -r compute | wc -l) -gt 1 ]; then
        _diagSrvShiftHost
        _diagnostics_instance_dns $DOMAIN_NAME $NAME_SERVER
    fi
    _diagSrvDelete

    _diagSrvCreate Cirros $NETWORK_INT_NAME
    _diagnostics_instance_dns $DOMAIN_NAME $NAME_SERVER
    if [ $(cubectl node list -r compute | wc -l) -gt 1 ]; then
        _diagSrvShiftHost
        _diagnostics_instance_dns $DOMAIN_NAME $NAME_SERVER
    fi
}

diagnostics_teardown()
{
    local PROJECT_NAME="_diagnostics"
    local SUBNET_EXT_NAME="_external-subnet"
    local NETWORK_INT_NAME="_internal-network"
    local SUBNET_INT_NAME="_internal-subnet"
    local ROUTER_E2I_NAME="_router-e2i"
    local NETWORK_EXT_NAME="_external-network"

    PROJECT_ID=$(openstack project list --long -f json | jq -r ".[] | select(.Name==\"$PROJECT_NAME\") | .ID")
    [ -n "$PROJECT_ID" ] || exit 0

    _diagSrvDelete
    _diagNetDelete
    _diagProjDelete
    _diagFlvrDelete
}

diagnostics_rbd()
{
    local POOL=${1:-$BUILTIN_BACKPOOL}
    local TYPE=${2:-write}
    local SZGB=${3:-1}
    local RIMG=$(mktemp -u rbd-bench-img.XXXX)
    local RDEV=/dev/rbd/$POOL/$RIMG
    local RMNT=/tmp/$RIMG

    rbd create $RIMG --size $((SZGB * 1024 + 1024)) --pool $POOL
    rbd map $RIMG --pool $POOL >/dev/null
    mkfs.ext4 /dev/rbd/$POOL/$RIMG >/dev/null 2>&1
    mkdir $RMNT
    mount $RDEV $RMNT
    rbd bench --io-type $TYPE --io-total ${SZGB}G $RIMG --pool=$POOL
    umount $RMNT
    rbd unmap $RIMG --pool $POOL
    rmdir $RMNT
}

diagnostics_osd_hdparm()
{
    local OSDID=${1#osd.}
    if [ -s $CEPH_OSD_MAP ]; then
        while read -r line; do
            DEV=$(echo $line | cut -d" " -f1)
            OID=$(echo $line | cut -d" " -f2)
            if [ "x$OSDID" = "x$OID" ]; then
                hdparm -tT $DEV | grep -v '/dev/'
                break
            fi
        done < $CEPH_OSD_MAP
    fi
}

_diagnostics_instance_dns()
{
    local PROJECT_NAME="_diagnostics"
    local DOMAIN_NAME=${1:-www.google.com}
    local NAME_SERVER=${2:-8.8.8.8}

    cubectl node exec -r compute -p "hex_sdk diagnostics_cirros_host_exec \"nslookup $DOMAIN_NAME $NAME_SERVER ; ping $NAME_SERVER -c 3\""
}

_diagnostics_instance_dd()
{
    local SZGB=${1:-1}

    [ $SZGB -lt 150 ] || Error "Test data size $SZGB GB can not be bigger 150"
    local BS=1M
    local COUNT=$((SZGB * 1024))
    cubectl node exec -r compute -p "hex_sdk diagnostics_cirros_host_exec \"rm -f ./test.file ; time dd if=/dev/zero of=./test.file bs=$BS count=$COUNT ; ls -lt\""
}

_diagnostics_server_list()
{
    local PROJECT_NAME="_diagnostics"
    openstack server list --project _diagnostics -c Host -c Name -c Networks -c Flavor -c Image
}

diagnostics_cirros_host_exec()
{
    local PROJECT_NAME="_diagnostics"
    local SERVER_LIST_JSON=$(openstack server list --project $PROJECT_NAME --host $HOSTNAME --long -f json)
    local INDEX=0

    for SERVER_ID in $(echo $SERVER_LIST_JSON | jq -r .[].ID); do
        SERVER_SHOW_JSON=$(openstack server show $SERVER_ID -f json)
        SVR_NAMES[$INDEX]="$(echo $SERVER_SHOW_JSON | jq -r .hostname)"
        INS_NAMES[$((INDEX++))]="$(echo $SERVER_SHOW_JSON | jq -r .instance_name)"
    done

    local LOG="/tmp/_${FUNCNAME[0]}"
    for INS_NAME in ${INS_NAMES[@]} ; do
        hex_sdk diagnostics_cirros_exec $INS_NAME $@ >${LOG}.${INS_NAME} 2>&1 &
        PROC_IDS+="$! "
    done
    wait $PROC_IDS


    for INS_NAME in ${INS_NAMES[@]} ; do
        echo "---- Outputs from $SVR_NAMES (${INS_NAME}) on $HOSTNAME----"
        cat ${LOG}.${INS_NAME}
        echo
        rm -f ${LOG}.${INS_NAME}
    done
}

diagnostics_cirros_exec()
{
    local INS=${1:-NOSUCHINSTANCE}
    shift 1
    local CMD="$*"
    local USER="cirros"
    local PASS="gocubsgo"
    virsh list | grep -q $INS || return 0

    expect -c "
set timeout 10
log_user 0
spawn virsh console $INS
expect_before timeout { exit 1 }
match_max 100000

expect \"*Connected to domain\"
send -- \"
\"
log_user 1
expect {
    -re \".*login: $\" {
        send -- \"$USER\n\"
        expect {
            -timeout 3
            -re \".*login: $\" { send -- \"$USER\n\" ; expect -re \".*assword: $\" }
            -re \".*assword: $\" { send -- \"$PASS\n\" }
        }

    }
    \"*$ \" { send -- \"\n\" }
    timeout { puts \"failed to run cirros exec in instance $INS\" ; exit 1 }
}
expect \"*$ \"
set timeout 600
send -- \"$CMD
\"
expect \"*$ \"
"
}

diagnostics_arpscan_report()
{
    for LOG in /run/arpscan.* ; do
        [ -e $LOG ] || continue

        declare -A IPS_MACS
        echo && echo "[NODE: $HOSTNAME] [INTERFACE: ${LOG##*.}]"
        while read -r line; do
            IP=$(echo $line | awk '{print $1}')
            MAC=$(echo $line | awk '{print $2}')
            if [ "x${IPS_MACS[$IP]}" != "x" -a "x${IPS_MACS[$IP]}" != "x$MAC" ]; then
                echo "$IP ${IPS_MACS[$IP]} conflicts $MAC"
            else
                if [ "$VERBOSE" == "1" ]; then
                    echo "$IP $MAC"
                fi
            fi
            IPS_MACS[$IP]=$MAC
        done < $LOG
    done
}

diagnostics_arpscan()
{
    local node_list=$(cubectl node list -j | jq .[].ip)
    local management=$(echo $node_list | jq -r .management | xargs)
    local provider=$(echo $node_list | jq -r .provider | xargs)
    local overlay=$(echo $node_list | jq -r .overlay | xargs)
    local storage=$(echo $node_list | jq -r .storage | xargs)
    local cluster=$(echo $node_list | jq -r '.["storage-cluster"]' | xargs)
    local ifcs=
    declare -A ifcs_pids
    readarray ip_array <<<"$(echo "$management $provider $overlay $storage $cluster" | tr ' ' '\n' | grep -v null | sort | uniq | xargs)"
    declare -p ip_array > /dev/null

    for ip_entry in ${ip_array[@]}; do
        ifcs+="$(ip r sh match $ip_entry | grep -o 'dev .*' | cut -d ' ' -f 2 | sort -u | tr '\n' ' ') "
    done
    for ifc in $(echo "$ifcs" | tr ' ' '\n' | sort | uniq); do
        ( arp-scan -I $ifc -l -x -q | sort | uniq >/run/arpscan.${ifc} ) &
        ifcs_pids[$ifc]=$!
    done
    for ifc in ${!ifcs_pids[@]}; do
        wait ${ifcs_pids[$ifc]}
    done
}
