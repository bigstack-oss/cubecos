# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ]; then
    echo "Error: PROG not set" >&2
    exit 1
fi

ceph_status()
{
    local TYPE=${1:-na}

    $CEPH -s
    $CEPH osd status

    case $TYPE in
        details)
            printf "\nDETAIL:\n"
            $CEPH health detail
            printf "\nLATENCY:\n"
            $CEPH osd perf
            printf "\nPOOL USAGE:\n"
            $CEPH df
            printf "\nOSD USAGE:\n"
            $CEPH osd df
            printf "\nPOOL STATS:\n"
            $CEPH osd pool autoscale-status
            ;;
    esac
}

ceph_get_host_by_id()
{
    local OSD_ID=${1#osd.}
    $CEPH osd ls | grep -q "${OSD_ID:-BADOSDID}" || return 1
    local HOST=$($CEPH osd find $OSD_ID -f json 2>/dev/null | jq -r .host)

    # make another attempt to find host
    if [ -z "$HOST" ]; then
        HOST=$($CEPH device ls-by-daemon osd.$OSD_ID --format json 2>/dev/null | jq -r ".[].location[].host")
    fi
    if [ -z "$HOST" ]; then
        HOST=$($CEPH osd tree -f json 2>/dev/null | jq -r --arg OSDID $OSD_ID '.nodes[] | select(.type == "host") | select(.children[] | select(. == ($OSDID | tonumber))).name')
    fi
    if [ -z "$HOST" ]; then
        cubectl node exec -pn "ceph-volume lvm list --format json 2>/dev/null | jq -r '.[][] | select(.tags.\"ceph.osd_id\" == \"$OSD_ID\")' | grep -q osd-block && hostname"
    fi

    echo -n $HOST
}

ceph_get_ids_by_dev()
{
    local DEV=$1
    # cehp device ls doesn't always sho correct osds associated with devices
    # local IDS=$($CEPH device ls-by-host $HOSTNAME --format json | jq -r ".[] | select(.location[].dev == \"${DEV#/dev/}\").daemons[]" | sed "s/osd.//g" | sort -u)
    local IDS=$(ceph-volume raw list --format json | jq -r ".[] | select(.device | startswith(\"$DEV\")).osd_id")
    IDS+=$(ceph-volume lvm list --format json | jq -r ".[][] | select(.devices[] == \"$DEV\").tags.\"ceph.osd_id\"")

    echo -n $IDS
}

ceph_get_dev_by_id()
{
    local OSD_ID=${1#.osd}
    local DEV=$(ceph-volume raw list --format json | jq -r ".[] | select(.osd_id == $OSD_ID).device")
    if echo $DEV | grep -q '/dev/mapper' ; then
        DEV=$(ceph-volume lvm list --format json | jq -r ".[][] | select(.tags.\"ceph.osd_id\" == \"$OSD_ID\").devices[]")
    fi
    echo -n $DEV
}

ceph_get_sn_by_dev()
{
    local DEV=$1
    local BLKDEVS=$(lsblk -J | jq -r .blockdevices[])
    while read BLKDEV; do
        PARENT_DEV=$(echo $BLKDEV | jq -r ". | select(.children[].name == \"${DEV#/dev/}\").name" 2>/dev/null)
        if [ "x$PARENT_DEV" != "x" ]; then
            DEV="/dev/$PARENT_DEV"
            break
        fi
    done < <(echo $BLKDEVS | jq -c)
    local SMART_FLG="-i"
    local SMART_LOG=$(smartctl $SMART_FLG $DEV)

    if smartctl $SMARTFLAG $DEV | grep -q -i 'megaraid,N' ; then
        SELECTED_DEV=$(lshw -class disk -json 2>/dev/null | jq -r ".[] | select(.logicalname == \"${DEV}\")")
        SELECTED_DEV_ID=$(echo $SELECTED_DEV | jq -r .id | cut -d":" -f2)
        SMART_FLG+=" -d megaraid,${SELECTED_DEV_ID}"
    fi
    local SN=$(smartctl $SMART_FLG $DEV 2>/dev/null | grep -i "Serial number" | cut -d":" -f2 | xargs)
    [ "x$SN" != "x" ] || SN=$($CEPH device ls | grep "${HOSTNAME}:${DEV#/dev/}" | awk '{print $1}')
    echo -n $SN
}

ceph_get_cache_by_backpool()
{
    local BACKPOOL=${1:-$BUILTIN_BACKPOOL}
    if [ "$BACKPOOL" = "$BUILTIN_BACKPOOL" ]; then
        local CACHEPOOL=$BUILTIN_CACHEPOOL
    else
        local CACHEPOOL=${BACKPOOL%-pool}-cache
    fi

    echo -n $($CEPH osd pool ls | grep "^${CACHEPOOL}$")
}

ceph_get_pool_in_cacheable_backpool()
{
    local POOL=${1:-NOSUCHPOOL}
    for P in $(ceph_cacheable_backpool_list); do
        if [ "$POOL" = "$P" ]; then
            echo $POOL
            break
        fi
    done
}

ceph_cacheable_backpool_list()
{
    local CACHEABLE_POOLS="$($CEPH osd pool ls | egrep -v "^${BUILTIN_CACHEPOOL}$|[.]rgw[.]|^cephfs_metadata$|^[.]mgr$|[-]cache$|^k8s-volumes$|^cephfs_data$|^rbd$|^glance-images$|^volume-backups$|^cinder-volumes-ssd$")"
    if [ "$VERBOSE" == "1" ]; then
        for BACKPOOL in $CACHEABLE_POOLS; do
            if [ "$BACKPOOL" = "$BUILTIN_BACKPOOL" ]; then
                CACHEPOOL=$BUILTIN_CACHEPOOL
            else
                CACHEPOOL=$($CEPH osd pool ls | grep "${BACKPOOL%-pool}-cache$")
            fi
            printf "%s%s\n" $BACKPOOL ${CACHEPOOL:+"/$CACHEPOOL"}
        done
    else
        for BACKPOOL in $CACHEABLE_POOLS; do
            printf "%s\n" $BACKPOOL
        done
    fi
}

ceph_backpool_cache_list()
{
    local POOLS=$($CEPH osd pool ls)
    local CACHEPOOLS="$($CEPH osd pool ls | egrep "$BUILTIN_CACHEPOOL|[-]cache$")"
    local BACKPOOL=${1:-$BUILTIN_BACKPOOL}

    for CACHEPOOL in $CACHEPOOLS; do
        if [ "$CACHEPOOL" = "$BUILTIN_CACHEPOOL" ]; then
            BACKPOOL=$BUILTIN_BACKPOOL
        else
            BACKPOOL=$($CEPH osd pool ls | grep "${CACHEPOOL%-cache}-pool$")
            [ "x$BACKPOOL" != "x" ] || BACKPOOL=$($CEPH osd pool ls | grep "${CACHEPOOL%-cache}$")
        fi
        if [ "$VERBOSE" == "1" ]; then
            [ "x$(ceph_osd_test_cache $BACKPOOL)" = "xoff" ] || printf "%s%s\n" $BACKPOOL ${CACHEPOOL:+"/$CACHEPOOL"}
        else
            [ "x$(ceph_osd_test_cache $BACKPOOL)" = "xoff" ] || printf "%s\n" $BACKPOOL
        fi
    done
}

ceph_mon_map_create()
{
    local CONF=${1:-/etc/ceph/ceph.conf}
    if ! sudo -u ceph $CEPH -c $CONF mon getmap -o $MAPFILE >/dev/null 2>&1; then
        if systemctl status ceph-mon@$HOSTNAME >/dev/null 2>&1; then
            systemctl stop ceph-mon@$HOSTNAME >/dev/null 2>&1
            sudo -u ceph ceph-mon -i $HOSTNAME --extract-monmap $MAPFILE >/dev/null 2>&1
            systemctl start ceph-mon@$HOSTNAME >/dev/null 2>&1
        else
            sudo -u ceph ceph-mon -i $HOSTNAME --extract-monmap $MAPFILE >/dev/null 2>&1
        fi
    fi
}

ceph_mon_map_inject()
{
    sudo -u ceph ceph-mon -i $HOSTNAME --inject-monmap $MAPFILE 2>/dev/null
}

ceph_mon_map_show()
{
    ceph_mon_map_create $1
    monmaptool --print $MAPFILE
}

ceph_crush_map_show()
{
    $CEPH osd getcrushmap -o $CRUSHMAPFILE
    crushtool -d $CRUSHMAPFILE -o $CRUSHMAPFILE.print
    cat $CRUSHMAPFILE.print
}

ceph_mon_store_renew()
{
    local MON_PTH=/var/lib/ceph/mon/ceph-$HOSTNAME
    local STORE_PTH=${MON_PTH}/store.db
    MountOtherPartition
    if [ -e /mnt/target${STORE_PTH}/CURRENT -a -e ${STORE_PTH}/CURRENT ]; then
        if [ /mnt/target${STORE_PTH}/CURRENT -nt ${STORE_PTH}/CURRENT ]; then
            rm -rf ${STORE_PTH}.bak
            mv ${STORE_PTH} ${STORE_PTH}.bak
            rsync -ar /mnt/target${STORE_PTH} ${MON_PTH}/
        elif [ /mnt/target${STORE_PTH}/CURRENT -ot ${STORE_PTH}/CURRENT ]; then
            rm -rf /mnt/target${STORE_PTH}.bak
            mv /mnt/target${STORE_PTH} /mnt/target${STORE_PTH}.bak
            rsync -ar ${STORE_PTH} /mnt/target${MON_PTH}/
        fi
    fi
    sync
    umount /mnt/target
}

ceph_mon_map_renew()
{
    local IP=$1
    local OLD_HOSTNAME=$2
    ceph_mon_map_create $3
    monmaptool --print $MAPFILE | egrep -q "$IP.*$HOSTNAME"
    if [ $? -eq 0 ]; then
        echo "mon node exists"
    else
        if [ -n "$OLD_HOSTNAME" -a "$OLD_HOSTNAME" != "$HOSTNAME" ]; then
            # hostname change
            sudo -u ceph monmaptool --rm $OLD_HOSTNAME $MAPFILE | grep monmaptool
        else
            # ip change
            sudo -u ceph monmaptool --rm $HOSTNAME $MAPFILE | grep monmaptool
        fi
        sudo -u ceph monmaptool --add $HOSTNAME $IP:6789 $MAPFILE | grep monmaptool
        ceph_mon_map_inject
    fi
}

ceph_mon_map_remove()
{
    local conf=$1
    local peers=$2

    ceph_mon_map_create $conf
    IFS=',' read -a peer_array <<<"$peers"
    declare -p peer_array > /dev/null
    for peer_entry in "${peer_array[@]}"
    do
        if [ -n "$peer_entry" ]; then
            sudo -u ceph monmaptool --rm $peer_entry $MAPFILE | grep monmaptool
        fi
    done
    ceph_mon_map_inject
}

ceph_bootstrap_mon_ip()
{
    ceph_mon_map_create
    local IP=$(monmaptool --print $MAPFILE | grep $HOSTNAME | awk -F' ' '{print $2}' | awk -F':' '{print $1}' | tr -d '\n')
    if [ "$IP" == "[v2" -o "$IP" == "v1" ]; then
        IP=$(monmaptool --print $MAPFILE | grep "6789.*$HOSTNAME" | awk -F':' '{print $3}' | tr -d '\n')
    fi
    echo -n $IP
}

ceph_mon_map_iplist()
{
    ceph_mon_map_create $1
    local IPLIST=$(monmaptool --print $MAPFILE | grep 6789 | awk -F' ' '{print $2}' | awk -F':' '{print $1}' | tr '\n' ',')
    if echo $IPLIST | grep -q '\[v2,' ; then
        IPLIST=$(monmaptool --print $MAPFILE | grep 6789 | awk '{print $2}' | tr '\n' ',')
    elif echo $IPLIST | grep -q 'v1' ; then
        IPLIST=$(monmaptool --print $MAPFILE | grep 6789 | awk -F' ' '{print $2}' | awk -F':' '{print $2}' | tr '\n' ',')
    fi
    echo -n ${IPLIST:-1}
}

ceph_mon_map_hosts()
{
    ceph_mon_map_create $1
    local HOSTS=$(monmaptool --print $MAPFILE | grep 6789 | awk -F' ' '{print $3}' | cut -c 5- | tr '\n' ',')
    echo -n ${HOSTS:-1}
}

ceph_mds_map_iplist()
{
    ceph_mon_map_create $1
    local IPLIST=$(monmaptool --print $MAPFILE | grep -v $HOSTNAME | grep 6789 | awk -F' ' '{print $2}' | awk -F':' '{print $1}' | tr '\n' ',')
    if echo $IPLIST | grep -q '\[v2,' ; then
        IPLIST=$(monmaptool --print $MAPFILE | grep -v $HOSTNAME | grep 6789 | awk '{print $2}' | tr '\n' ',')
    elif echo $IPLIST | grep -q 'v1' ; then
        IPLIST=$(monmaptool --print $MAPFILE | grep -v $HOSTNAME | grep 6789 | awk -F' ' '{print $2}' | awk -F':' '{print $2}' | tr '\n' ',')
    fi
    echo -n $IPLIST
}

ceph_mds_map_hosts()
{
    local NEXTHOST=0
    local MONHOSTS=($(ceph_mon_map_hosts | tr ',' ' '))
    local MDSHOSTS=
    for (( i=0 ; i<${#MONHOSTS[@]}; i++ )); do
        if [ "x$HOSTNAME" = "x${MONHOSTS[$i]}" ] ; then
            continue
        else
            MDSHOSTS+="${MONHOSTS[$i]},"
        fi
    done
    echo -n ${MDSHOSTS%,}
}

ceph_enter_maintenance()
{
    Quiet $CEPH osd set noout
    Quiet $CEPH osd set norecover
    Quiet $CEPH osd set norebalance
    Quiet $CEPH osd set nobackfill
    Quiet $CEPH osd set nodown
    Quiet $CEPH osd set pause
}

ceph_leave_maintenance()
{
    Quiet $CEPH osd unset pause
    Quiet $CEPH osd unset nodown
    Quiet $CEPH osd unset nobackfill
    Quiet $CEPH osd unset norebalance
    Quiet $CEPH osd unset norecover
    Quiet $CEPH osd unset noout
}

ceph_maintenance_status()
{
    if $($CEPH osd stat | grep -q noout); then
        echo "in maintenance mode"
    else
        echo "in production mode"
    fi
}

ceph_create_cachepool()
{
    local BACKPOOL=${1:-$BUILTIN_BACKPOOL}

    if [ "$BACKPOOL" = "$BUILTIN_BACKPOOL" ]; then
        local CACHEPOOL=$BUILTIN_CACHEPOOL
    else
        local CACHEPOOL=${BACKPOOL%-pool}-cache
    fi
    local SIZE=$($CEPH osd pool get $BACKPOOL size -f json | jq .size)
    local OSDN=$($CEPH osd df $BACKPOOL | grep up | wc -l)
    local APP=$($CEPH osd pool ls detail | grep $BACKPOOL | grep -o "application .*" | cut -d" " -f2)
    if [ $OSDN -gt 100 -a $SIZE -gt 2 ]; then
        ((SIZE --))
    fi

    ceph_create_pool $CACHEPOOL $APP $SIZE
    local PGS=$($CEPH osd pool get $BACKPOOL pg_num -f json | jq -r .pg_num)
    $CEPH osd pool set $CACHEPOOL pg_num $PGS  --yes-i-really-mean-it >/dev/null 2>&1
    $CEPH osd pool set $CACHEPOOL pgp_num $PGS >/dev/null 2>&1
}

ceph_create_pool()
{
    local VOLUME=${1:-$BUILTIN_BACKPOOL}
    local APP=${2:-rbd}
    local SIZE=${3:-3}

    # pg number will update with cron job
    $CEPH osd pool create $VOLUME 1 >/dev/null 2>&1 || true
    for i in {1..15}; do
        if $CEPH osd pool ls | grep -q $VOLUME; then
            break
        else
            sleep 1
        fi
    done
    $CEPH osd pool set $VOLUME size $SIZE >/dev/null 2>&1 || true
    for i in {1..15}; do
        if [ $($CEPH -s | grep creating -c) -gt 0 ]; then
            sleep 1
        else
            break
        fi
    done
    $CEPH osd pool application enable $VOLUME $APP >/dev/null 2>&1 || true
}

ceph_create_ec_pool()
{
    local POOL=$1
    local PROFILE=$2

    $CEPH osd pool create $POOL 1 1 erasure $PROFILE >/dev/null 2>&1 || true
    $CEPH osd pool application enable $POOL rgw >/dev/null 2>&1 || true
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        if [ $($CEPH -s | grep creating -c) -gt 0 ]; then
            sleep 1
        else
            break
        fi
    done
}

ceph_convert_to_ec_pool()
{
    local POOL=$1
    local CHUNKS=$2
    local PARITY=$3
    local EC_PROFILE=$($CEPH osd pool get $POOL erasure_code_profile 2>/dev/null | awk '{print $2}')
    local OLD_CHUNKS=$(echo $EC_PROFILE | awk -F'-' '{print $3}')
    local OLD_PARITY=$(echo $EC_PROFILE | awk -F'-' '{print $4}')

    if [ "$OLD_CHUNKS" != "$CHUNKS" ] || [ "$OLD_PARITY" != "$PARITY" ]; then
        local PROFILE=ec-$(/usr/bin/uuid | fold -w 8 | head -n 1)-$CHUNKS-$PARITY

        $CEPH osd erasure-code-profile set $PROFILE k=$CHUNKS m=$PARITY
        ceph_create_ec_pool $POOL.new $PROFILE
        rados cppool $POOL $POOL.new 2>/dev/null
        $CEPH osd pool rename $POOL $POOL.$PROFILE.orig
        $CEPH osd pool rename $POOL.new $POOL
    fi
}

ceph_adjust_pool_size()
{
    local POOL_NAME=$1
    local SIZE=${2:-3}
    local MIN_SIZE=$(expr $SIZE - 1)
    local TYPE=${3:-rf}

    if [[ "$POOL_NAME" =~ "-pool" || "$POOL_NAME" =~ "-cache" ]]; then
        local BUCKET=$(echo $POOL_NAME | sed -e 's/-pool$//' -e 's/-cache$//')
    else
        local BUCKET="default"
    fi

    local HOST_NUM=$($CEPH osd crush ls $BUCKET | sort | uniq | wc -l)

    if [ "$TYPE" == "ec" ]; then
        if [ "$(expr $SIZE + $MIN_SIZE)" -gt "$HOST_NUM" ] || [ "$SIZE" -eq 1 ]; then
            echo "can't set EC when there are no enough hosts, rollback to RF pool"
            TYPE=rf
        fi
    fi

    if [ $MIN_SIZE -eq 0 ]; then
        MIN_SIZE=1
    fi

    $CEPH config set global mon_allow_pool_size_one true
    case $TYPE in
        rf)
            echo "set ceph pool $POOL_NAME (size, min_size) to ($SIZE, $MIN_SIZE)"
            $CEPH osd pool set $POOL_NAME size $SIZE --yes-i-really-mean-it 2>/dev/null || true
            $CEPH osd pool set $POOL_NAME min_size $MIN_SIZE 2>/dev/null || true
            ;;
        ec)
            echo "set ceph ec pool $POOL_NAME (chunks, parity) to ($SIZE, $MIN_SIZE)"
            ceph_convert_to_ec_pool $POOL_NAME $SIZE $MIN_SIZE
            ;;
    esac
    $CEPH config set global mon_allow_pool_size_one false
    $CEPH config rm global mon_allow_pool_size_one
}

ceph_pool_replicate_init()
{
    local HOSTS=$($CEPH osd tree -f json | jq '[ .nodes[] | select(.type=="host") ] | length' 2>/dev/null)
    local SIZE=1

    if [ -n "$HOSTS" ]; then
        if [ $HOSTS -ge 3 ]; then
            SIZE=3
        else
            SIZE=$HOSTS
        fi
    fi

    ceph_pool_replicate_set $SIZE
}

ceph_pool_replicate_set()
{
    local SIZE=${1:-3}
    local CACHESIZE=
    [ $SIZE -gt 1 ] && CACHESIZE=2 || CACHESIZE=1
    [ $SIZE -gt 1 ] || $CEPH config set global mon_allow_pool_size_one true
    for P in $($CEPH osd pool ls) ; do
        case $P in
            default.rgw.buckets.data)
                ceph_adjust_pool_size $P $SIZE ec
                ;;
            $BUILTIN_CACHEPOOL|$BUILTIN_EPHEMERAL|*-cache)
                ceph_adjust_pool_size $P $CACHESIZE
                ;;
            *)
                ceph_adjust_pool_size $P $SIZE
                ;;
        esac
    done
    [ $SIZE -gt 1 ] || $CEPH config set global mon_allow_pool_size_one false
}

ceph_pool_autoscale_set()
{
    local state=$1

    for p in $($CEPH osd pool ls)
    do
        local mode=$($CEPH osd pool get $p pg_autoscale_mode | awk '{print $2}' | tr -d '\n')
        if [ "$mode" != "$state" ]; then
            echo "set pool '$p' autoscale $state"
            $CEPH osd pool set $p pg_autoscale_mode $state >/dev/null 2>&1
        fi
    done
}

ceph_adjust_pool_pg()
{
    local POOL_NAME=$1
    local DATA_PCT=$2
    local PG_OSD=200
    local MODE=$($CEPH osd pool get $POOL_NAME pg_autoscale_mode | awk '{print $2}' | tr -d '\n')

    if [ "$MODE" != "on" ]; then
        local OSD_NUM=$($CEPH osd stat | awk '{print $3}')
        local SIZE=$($CEPH osd pool get $POOL_NAME size -f json | jq .size)

        let PG=$(( ($PG_OSD * $OSD_NUM * $DATA_PCT) / ($SIZE * 1000) ))
        if [ $PG -eq 0 ]; then
            PG=$OSD_NUM
        fi

        local PG_P2=$(echo "x=l($PG)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l)

        echo "set pool '$POOL_NAME' pg number to $PG_P2"
        $CEPH osd pool set $POOL_NAME pg_num $PG_P2 --yes-i-really-mean-it >/dev/null 2>&1
        $CEPH osd pool set $POOL_NAME pgp_num $PG_P2 >/dev/null 2>&1
    fi
}

ceph_adjust_cache_flush_bytes()
{
    [ "x$(ceph_osd_test_cache)" = "xon" ] || return 0

    for CP in $BUILTIN_CACHEPOOL $($CEPH osd pool ls | grep "[-]cache"); do
        if $CEPH osd pool get $CP target_max_bytes >/dev/null 2>&1; then
            local CACHE_SZ=$(ceph_osd_get_cache_size $CP)
            [ -n "$CACHE_SZ" ] && $CEPH osd pool set $CP target_max_bytes $CACHE_SZ >/dev/null 2>&1 || true
        fi
    done
    $CEPH health mute CACHE_POOL_NEAR_FULL >/dev/null 2>&1 || true
}

ceph_adjust_pgs()
{
    # reference: https://ceph.com/pgcalc/
    for P in $($CEPH osd pool ls) ; do
        case $P in
            # $BUILTIN_CACHEPOOL/userdef-cache 50%: 500
            # FIXME: what to do with variable no. of user-defined pools?
            $BUILTIN_CACHEPOOL|*-cache)
                ceph_adjust_pool_pg $P 100
                ;;
            $BUILTIN_BACKPOOL|*-pool)
                ceph_adjust_pool_pg $P 400
                ;;
            # others 35%: 350
            k8s-volumes|volume-backups|ephemeral-vms|glance-images)
                ceph_adjust_pool_pg $P 80
                ;;
            rbd)
                ceph_adjust_pool_pg $P 30
                ;;
            # others 5%: 50
            # adjust pg of data and metadata pools for ceph filesystem. Ratio should be 80:20
            # https://ceph.com/planet/cephfs-ideal-pg-ratio-between-metadata-and-data-pools/
            cephfs_data)
                ceph_adjust_pool_pg $P 40
                ;;
            cephfs_metadata)
                ceph_adjust_pool_pg $P 10
                ;;
            # rgw 10%: 100
            default.rgw.buckets.extra)
                ceph_adjust_pool_pg $P 8
                ;;
            default.rgw.buckets.index)
                ceph_adjust_pool_pg $P 16
                ;;
            default.rgw.buckets.data)
                ceph_adjust_pool_pg $P 64
                ;;
            *)
                ceph_adjust_pool_pg $P 1
                ;;
        esac
    done
    ceph_adjust_cache_flush_bytes
}

# params:
# $1: device name(e.g.: /dev/sdd)
ceph_osd_zap_disk()
{
    local DEV=$1
    local LVM=$(ceph-volume lvm list --format json | jq -r ".[][] | select(.devices[] == \"$DEV\").lv_path")
    if [ -e ${LVM:-NOSUCHLVM} ]; then
        Quiet ceph-volume lvm zap $LVM --destroy
        Quiet dmsetup remove $LVM 2>/dev/null
    else
        Quiet timeout $SRVTO wipefs -a $DEV 2>/dev/null
        Quiet timeout $SRVTO sgdisk -Z $DEV 2>/dev/null
        Quiet ceph-volume lvm zap $DEV --destroy
    fi
}

# list osd-typed disks (mounted)
ceph_osd_list_disk()
{
    local ALL_DEVS=
    local BLKDEVS=$(lsblk -J | jq -r .blockdevices[])
    # local RAW_DEVS=$($CEPH device ls-by-host $HOSTNAME --format json | jq -r ".[] | select(.daemons[] | startswith(\"osd\")).location[].dev" | sort -u | xargs -i echo /dev/{})
    local RAW_DEVS=$(ceph-volume raw list --format json | jq -r ".[] | select(.device | startswith(\"/dev/\")).device" | grep -v "/dev/mapper" | sort -u)
    for DEV in $RAW_DEVS; do
        PARENT_DEV=/dev/$(echo $BLKDEVS | jq -r ". | select(.children[].name == \"${DEV#/dev/}\").name" 2>/dev/null)
        ALL_DEVS+="\n${PARENT_DEV}"
    done
    local LVM_DEVS=$(ceph-volume lvm list --format json | jq -r ".[][].devices[]")
    [ -z "$LVM_DEVS" ] || ALL_DEVS+="\n$LVM_DEVS"
    ALL_DEVS=$(echo -e "$ALL_DEVS" | sort -u)
    echo "$ALL_DEVS" | tr "\n" " " | sed -e "s/^ //" -e "s/ $//"
}

# list osd meta partitions (umount)
ceph_osd_list_meta_partitions()
{
    local METAPARTS=$(blkid | grep -e 'PARTLABEL=\"cube_meta' | sort | cut -d":" -f1)

    echo -n $METAPARTS
}

# list osd-typed partitions
# (i.e.: typecode: 4fbd7e29-9d25-41b8-afd0-062c0ceff05d)
ceph_osd_list_partitions()
{
    local NVME_DEVS=$(blkid | grep -e 'PARTLABEL=\"cube_meta' | grep -oe '^/dev/nvme[0-9]\+n[0-9]\+p[0-9]\+' | sort | uniq)
    [ -z "$NVME_DEVS" ] || NVME_DEVS=$(readlink -e $NVME_DEVS)
    echo -n $NVME_DEVS
    if [ -n "$NVME_DEVS" ]; then
        echo -n " "
    fi
    local SCSI_DEVS=$(blkid | grep -e 'PARTLABEL=\"cube_meta' | grep -oe '^/dev/sd[a-z]\+[0-9]\+' | sort | uniq)
    [ -z "$SCSI_DEVS" ] || SCSI_DEVS=$(readlink -e $SCSI_DEVS)
    echo -n $SCSI_DEVS
}

# params:
# $1: device name(e.g.: /dev/sdd)
# $2: nums of meta partitions
# $3: size of meta partition (unit: sectors)
ceph_osd_prepare_bluestore()
{
    local TYPECODE_DATA="4fbd7e29-9d25-41b8-afd0-062c0ceff05d"
    local TYPECODE_BLOCK="cafecafe-9b03-4f30-b4c6-b4b80ceff106"
    local DEV=$1
    local PART_NUM=$2
    local PART_SIZE=$3
    local TYPE=$4
    local PART_SYMBOL=
    local PART_DEV=

    # a. error handling
    [ -n "$DEV" ] || return 1
    [[ "$PART_NUM" =~ ^[0-9]+$ ]] || PART_NUM=1
    [[ "$PART_SIZE" =~ ^[0-9]+$ ]] || PART_SIZE=409600

    # b. zap and partition osd data device
    Quiet ceph_osd_zap_disk $DEV
    i=1
    PART_SIZE=$(( $PART_SIZE / 2048))

    if [ "$TYPE" == "scsi" ]; then
        PART_SYMBOL=${DEV/\/dev\/sd/}
        PART_DEV="$DEV"
    elif [ "$TYPE" == "nvme" ]; then
        PART_SYMBOL=${DEV/\/dev\/nvme/}
        PART_DEV="${DEV}p"
    fi

    for (( ; i<=$PART_NUM; i++ ))
    do
        Quiet sgdisk -n $i:0:+${PART_SIZE}M -c $i:"cube_meta_"$PART_SYMBOL"_"$i -u 1:$(uuidgen) --mbrtogpt -- $DEV
        partprobe $PART_DEV$i 2>/dev/null || true
        # zero-out 100mb for each partition
        dd if=/dev/zero of=${PART_DEV}${i} bs=1M count=100 oflag=sync
        Quiet mkfs.xfs -f ${PART_DEV}${i}
    done
    # c. partition osd block device
    FREE_SIZE=$(GetFreeSectorsByDisk $DEV)
    LOG_SEC=$(lsblk -t -J $DEV | jq -r .blockdevices[].\"log-sec\")
    MULTIPLIER=$(( $LOG_SEC / 512 ))
    PART_SIZE=$(( $FREE_SIZE / $PART_NUM / 2048 * ${MULTIPLIER:-1} ))
    PART_NUM=$(( $PART_NUM * 2 ))
    for (( ; i<=$PART_NUM; i++ ))
    do
        Quiet sgdisk -n $i:0:+${PART_SIZE}M -c $i:"cube_data_"$PART_SYMBOL"_"$i -u 1:$(uuidgen) --mbrtogpt -- $DEV
        partprobe $PART_DEV$i 2>/dev/null || true
        # zero-out 100mb for each partition
        dd if=/dev/zero of=${PART_DEV}${i} bs=1M count=100 oflag=sync
    done
}

ceph_osd_down_list()
{
    if [ "$VERBOSE" == "1" ]; then
        $CEPH osd tree | awk '/ down /{printf "%5s (%s)\n", $4, $2}' | grep osd || /bin/true
        $CEPH osd tree | awk '/ down /{printf "%5s\n", $3}' | grep osd || /bin/true
    else
        $CEPH osd tree | awk '/ down /{print $1}'
    fi
}

# prepare free disks and make them lvm OSDs
# !!!USE WITH CAUTIONS!!!
ceph_osd_add_disk_lvm()
{
    local DEVS="$*"
    for DEV in $DEVS ; do
        [ -n "$(readlink -e $DEV)" ] || continue
        Quiet timeout $SRVTO wipefs -a $DEV 2>/dev/null
        if ceph-volume inventory $DEV | grep -q -i "available.*true" ; then
            ceph-volume lvm create --bluestore --data $DEV >/dev/null 2>&1
        else
            ceph-volume inventory $DEV
        fi
    done
    Quiet ceph-volume lvm activate --bluestore --all
    Quiet ceph_adjust_cache_flush_bytes
}

# prepare free disks and make them lvm LUKS encrypted OSDs
# !!!USE WITH CAUTIONS!!!
ceph_osd_add_disk_encrypt()
{
    local DEVS="$*"
    for DEV in $DEVS ; do
        [ -n "$(readlink -e $DEV)" ] || continue
        Quiet timeout $SRVTO wipefs -a $DEV 2>/dev/null
        if ceph-volume inventory $DEV | grep -q -i "available.*true" ; then
            ceph-volume lvm create --dmcrypt --bluestore --data $DEV >/dev/null 2>&1
        else
            ceph-volume inventory $DEV
        fi
    done
    Quiet ceph-volume lvm activate --bluestore --all
    Quiet ceph_adjust_cache_flush_bytes
}

# prepare free disks and make them raw OSDs
# !!!USE WITH CAUTIONS!!!
ceph_osd_add_disk_raw()
{
    local DEVS="$*"
    for DEV in $DEVS ; do
        [ -n "$(readlink -e $DEV)" ] || continue
        PrepareDataDisk $DEV
    done
    /usr/sbin/hex_config refresh_ceph_osd
    ceph_adjust_cache_flush_bytes
}

# remove an existing OSD
# !!!USE WITH CAUTIONS!!!
ceph_osd_remove_disk()
{
    local DEV=$1
    local MODE=${2:-safe}
    [ -n "$(readlink -e $DEV)" ] || Error "no such device $DEV"
    ceph_osd_list_disk | grep -q $DEV || Error "no such OSD disk $DEV"
    [[ "$($CEPH -s -f json | jq -r .health.status)" == "HEALTH_OK" || "$MODE" == "force" ]] || Error "ceph health has to be OK to proceed disk removals"

    local PART_NUM=$(( $(ListNumOfPartitions $DEV) / 2 ))
    if [ $PART_NUM -gt 0 ]; then
        local PART_ENUM="$(seq 1 $PART_NUM)"
    else
        local PART_ENUM=$PART_NUM
    fi
    local DISK_REMOVABLE=true
    for i in $PART_ENUM ; do
        OSD_ID=
        if [ $i -eq 0 ]; then
            OSD_ID=$(ceph_osd_get_id ${DEV})
        else
            if [[ "$DEV" =~ nvme.n. ]]; then
                OSD_ID=$(ceph_osd_get_id ${DEV}p${i})
            elif [[ "$DEV" =~ nvme ]]; then
                OSD_ID=$(ceph_osd_get_id ${DEV}n1p${i})
            else
                OSD_ID=$(ceph_osd_get_id ${DEV}${i})
            fi
        fi
        ceph_osd_remove $OSD_ID $MODE || DISK_REMOVABLE=false
        # For raw osd disk, modify PARTLABEL to exclude disk in next hex_config refresh_ceph_osd
        # Quiet parted $DEV name $i removed
    done
    if [ "$DISK_REMOVABLE" = "true" ]; then
        Quiet ceph_osd_zap_disk $DEV
        Quiet ceph_osd_create_map
        Quiet ceph_adjust_cache_flush_bytes
    fi
}

ceph_osd_remove()
{
    local OSD_ID=${1#osd.}
    local MODE=${2:-safe}
    local HOST=$(ceph_get_host_by_id $OSD_ID)

    $CEPH osd df osd.$OSD_ID
    timeout 600 ceph tell osd.$OSD_ID compact >/dev/null 2>&1 || true
    CRUSH_WEIGHT=$($CEPH osd tree -f json | jq -r ".[][] | select(.name == \"osd.${OSD_ID}\").crush_weight")
    Quiet $CEPH osd crush reweight osd.$OSD_ID 0
    Quiet $CEPH osd out $OSD_ID
    if [ "x$MODE" = "xsafe" ]; then
        sleep 10
        local CNT=0
        local MAX=30
        local PGS_LOG=$(mktemp -u /tmp/remove_osd.1.XXX)
        local WHY_QUITTING=
        while ! $CEPH osd safe-to-destroy osd.$OSD_ID >$PGS_LOG 2>&1 ; do
            tail -1 $PGS_LOG | sed "s/Error EBUSY: //"
            ((CNT++))
            sleep 60
            if [ $CNT -gt $MAX ]; then
                WHY_QUITTING="timed out moving data from disk"
            elif [ "x$($CEPH -s -f json | jq -r .health.status)" = "xHEALTH_ERR" ]; then
                [ $CNT -lt 3 ] || WHY_QUITTING="ceph would be in error state without this disk"
            elif [ "x$($CEPH osd safe-to-destroy osd.$OSD_ID 2>&1 | egrep -o '[0-9]+ pgs')" == "x$(egrep -o '[0-9]+ pgs' $PGS_LOG)" ]; then
                [ $CNT -lt 3 ] || WHY_QUITTING="pgs could not be moved likely due to too few disks or little space in the failure domain"
            fi
            if [ "x$WHY_QUITTING" != "x" ]; then
                systemctl restart ceph-osd@$OSD_ID
                Quiet $CEPH osd crush reweight osd.$OSD_ID $CRUSH_WEIGHT
                Quiet $CEPH osd in $OSD_ID
                echo "Restored ${DEV}: osd.$OSD_ID as $WHY_QUITTING." && exit 1
            fi
        done
        rm -f $PGS_LOG
        $CEPH osd down $OSD_ID
    fi

    remote_run $HOST "systemctl stop ceph-osd@$OSD_ID || true 2>/dev/null 2>&1"
    $CEPH osd purge $OSD_ID --force >/dev/null 2>&1
    remote_run $HOST ceph-volume lvm deactivate $OSD_ID || true
    remote_run $HOST umount -l /var/lib/ceph/osd/ceph-$OSD_ID || true
    remote_run $HOST rmdir /var/lib/ceph/osd/ceph-$OSD_ID
    hex_sdk remote_run $HOST "[ ! -e /var/lib/ceph/osd/ceph-$OSD_ID ]" || return 1
}

ceph_osd_host_remove()
{
    local host=$1

    for osd in $($CEPH osd tree -f json | jq -r '.nodes[] | select(.name == "$host").children[]')
    do
        ceph_osd_remove $osd
    done
    $CEPH osd crush rm $host
}

ceph_osd_get_cache_size()
{
    local CACHEPOOL=${1:-$BUILTIN_CACHEPOOL}
    local RF=$($CEPH osd pool get $CACHEPOOL size | awk '{print $2}')
    local RESULT=0
    # add each size into RESULT (e.g.: 8.31,TiB 865,GiB)
    for SZ in $($CEPH osd df $CACHEPOOL | grep " ssd " | awk '{print $5","$6}')
    do
        local N=$(echo $SZ | awk -F',' '{print $1}')
        local U=$(echo $SZ | awk -F',' '{print $2}')
        case "$U" in
            "PiB") RESULT=$(bc <<< "$RESULT+$N*1024*1024*1024*1024*1024") ;;
            "TiB") RESULT=$(bc <<< "$RESULT+$N*1024*1024*1024*1024") ;;
            "GiB") RESULT=$(bc <<< "$RESULT+$N*1024*1024*1024") ;;
            "MiB") RESULT=$(bc <<< "$RESULT+$N*1024*1024") ;;
            "KiB") RESULT=$(bc <<< "$RESULT+$N*1024") ;;
            ?) return 2
        esac
    done
    # cut-off 10% just in case ceph over-report the size
    RESULT=$(bc <<< "$RESULT/$RF*0.9")
    RESULT=$(echo $RESULT | grep -oe '^[0-9]\+')
    # returned result has to be prorated by configured burst rate
    local CACHE_FULL_RATIO=$($CEPH osd pool get $CACHEPOOL cache_target_full_ratio -f json 2>/dev/null | jq -r .cache_target_full_ratio)
    RESULT=$(bc <<< "$RESULT * ${CACHE_FULL_RATIO:-1} / 1")

    echo -n $RESULT
}

# check if cache of backPool is on or off
# $1 - backPool name (e.g.: $BUILTIN_BACKPOOL)
ceph_osd_test_cache()
{
    local CACHEPOOL=$(ceph_get_cache_by_backpool $1)

    if [ -z "$CACHEPOOL" ]; then
        echo "No cache associated with backpool: $1" && return 1
    else
        $CEPH osd pool get $CACHEPOOL hit_set_type &>/dev/null && echo -n "on" || echo -n "off"
    fi
}

# params:
# $1 - disk name (e.g.: /dev/sdb)
# $2 - rule name (e.g.: ssd)
# $3 - cache pool name (e.g.: $BUILTIN_CACHEPOOL or userdef-cache)
ceph_osd_promote_disk()
{
    local DEV=$1
    local RULE=${2:-ssd}
    local CACHEPOOL=${3:-$BUILTIN_CACHEPOOL}
    # check
    [ -n "$DEV" ] || return 1
    [ "x$(ceph_osd_get_class $DEV)" != "x$RULE" ] || return 0
    [ "$($CEPH -s -f json | jq -r .health.status)" = "HEALTH_OK" ] || Error "ceph health has to be OK to proceed disk promotion"
    [ "x$($CEPH -s -f json | jq -r .pgmap.recovering_objects_per_sec)" = "xnull" ] || Error "cannot promote disk while ceph is recovering"
    local OSD_LIST=$(for i in $(hex_sdk ceph_get_ids_by_dev $DEV); do echo osd.$i; done)
    $CEPH osd out $OSD_LIST
    # move osd to $RULE
    $CEPH osd crush rm-device-class $OSD_LIST
    $CEPH osd crush set-device-class $RULE $OSD_LIST

    for i in {1..60}; do
        sleep 10
        RECOVERING=$($CEPH -s -f json | jq -r .pgmap.recovering_objects_per_sec)
        if [ "x$RECOVERING" = "xnull" ]; then
            sleep 5
            RECOVERING_CONFIRM=$($CEPH -s -f json | jq -r .pgmap.recovering_objects_per_sec)
            if [ "x$RECOVERING_CONFIRM" = "xnull" ]; then
                $CEPH osd in $OSD_LIST
                ceph_adjust_cache_flush_bytes
                break
            fi
        else
            echo "recovering $RECOVERING obj/sec"
        fi
    done
}

# params:
# $1 - disk name (e.g.: /dev/sdb)
# $2 - rule name (e.g.: hdd)
ceph_osd_demote_disk()
{
    local DEV=$1
    local RULE=${2:-hdd}
    # check
    [ -n "$DEV" ] || return 1
    [ "x$(ceph_osd_get_class $DEV)" != "x$RULE" ] || return 0
    [ "$($CEPH -s -f json | jq -r .health.status)" = "HEALTH_OK" ] || Error "ceph health has to be OK to proceed disk demotion"
    [ "x$($CEPH -s -f json | jq -r .pgmap.recovering_objects_per_sec)" = "xnull" ] || Error "cannot demote disk while ceph is recovering"
    local OSD_LIST=$(for i in $(hex_sdk ceph_get_ids_by_dev $DEV); do echo osd.$i; done)
    local OLD_RULE=$(ceph_osd_get_class $DEV)
    local NUMS=$($CEPH osd crush class ls-osd $OLD_RULE | wc -l)
    # MUST leave at least 1 disk in cache
    if [ "$(ceph_osd_test_cache)" == "on" ]; then
        [ $NUMS -gt 2 ] || return 1
    fi
    $CEPH osd out $OSD_LIST
    # move osd to new $RULE
    $CEPH osd crush rm-device-class $OSD_LIST
    $CEPH osd crush set-device-class $RULE $OSD_LIST

    for i in {1..60}; do
        sleep 10
        RECOVERING=$($CEPH -s -f json | jq -r .pgmap.recovering_objects_per_sec)
        if [ "x$RECOVERING" = "xnull" ]; then
            sleep 5
            RECOVERING_CONFIRM=$($CEPH -s -f json | jq -r .pgmap.recovering_objects_per_sec)
            if [ "x$RECOVERING_CONFIRM" = "xnull" ]; then
                $CEPH osd in $OSD_LIST
                ceph_adjust_cache_flush_bytes
                break
            fi
        else
            echo "recovering $RECOVERING obj/sec"
        fi
    done
}

# params:
# $1 - backPool
# $2 - mode
ceph_osd_set_cache_mode()
{
    local CACHEPOOL=$(ceph_get_cache_by_backpool $1)
    if [ -z "$CACHEPOOL" ]; then
        echo "Error: no cache associated with backpool: $1"
        ceph_backpool_cache_list
        return 1
    fi
    local MODE=$2

    if [ $# -lt 2 ]; then
        echo "Usage: $0 backPool Mode" && return 1
    fi

    if [ "$CACHEPOOL" = "$BUILTIN_CACHEPOOL" ] || ($CEPH osd pool ls | grep "[-]cache" | grep -q $CACHEPOOL); then
        $CEPH osd tier cache-mode $CACHEPOOL $MODE --yes-i-really-mean-it 2>/dev/null
    else
        echo "$CACHEPOOL is not a recognized cache pool" && return 1
    fi
}

# $1 - backPool name (e.g.: $BUILTIN_BACKPOOL)
ceph_osd_cache_flush()
{
    local CACHEPOOL=$(ceph_get_cache_by_backpool $1)
    if [ -z "$CACHEPOOL" ]; then
        echo "Error: no cache associated with backpool: $1"
        ceph_backpool_cache_list
        return 1
    fi

    rados -p $CACHEPOOL cache-try-flush-evict-all
}

# $1 - backPool name (e.g.: $BUILTIN_BACKPOOL)
ceph_osd_cache_profile_get()
{
    local CACHEPOOL=$(ceph_get_cache_by_backpool $1)
    if [ -z "$CACHEPOOL" ]; then
        echo "Error: no cache associated with backpool: $1"
        ceph_backpool_cache_list
        return 1
    fi

    local ratio=$($CEPH osd pool get $CACHEPOOL cache_target_full_ratio -f json 2>/dev/null | jq .cache_target_full_ratio_micro)
    if [ "$ratio" = "300000" ]; then
        echo 'high-burst'
    elif [ "$ratio" = "600000" ]; then
        echo 'default'
    elif [ "$ratio" = "800000" ]; then
        echo 'low-burst'
    else
        echo "disabled"
    fi
}

# $1 - backPool name (e.g.: $BUILTIN_BACKPOOL)
# $2 - [<1|2|3>]
#      1: high-burst (70% burst, 30% cache)
#      2: default (40% burst, 60% cache)
#      3: low-burst (20% burst, 80% cache)
ceph_osd_cache_profile_set()
{
    local CACHEPOOL=$(ceph_get_cache_by_backpool $1)
    if [ -z "$CACHEPOOL" ]; then
        echo "Error: no cache associated with backpool: $1"
        ceph_backpool_cache_list
        return 1
    fi
    local profile=$2

    if [ "$profile" = "high-burst" ]; then
        $CEPH osd pool set $CACHEPOOL cache_target_dirty_ratio .1                            >/dev/null 2>&1
        $CEPH osd pool set $CACHEPOOL cache_target_dirty_high_ratio .2                       >/dev/null 2>&1
        $CEPH osd pool set $CACHEPOOL cache_target_full_ratio .3                             >/dev/null 2>&1
    elif [ "$profile" = "default" ]; then
        $CEPH osd pool set $CACHEPOOL cache_target_dirty_ratio .2                            >/dev/null 2>&1
        $CEPH osd pool set $CACHEPOOL cache_target_dirty_high_ratio .4                       >/dev/null 2>&1
        $CEPH osd pool set $CACHEPOOL cache_target_full_ratio .6                             >/dev/null 2>&1
    elif [ "$profile" = "low-burst" ]; then
        $CEPH osd pool set $CACHEPOOL cache_target_dirty_ratio .4                            >/dev/null 2>&1
        $CEPH osd pool set $CACHEPOOL cache_target_dirty_high_ratio .6                       >/dev/null 2>&1
        $CEPH osd pool set $CACHEPOOL cache_target_full_ratio .8                             >/dev/null 2>&1
    else
        echo "Error: $profile is not one of the valid settings, high-burst, default or low-burst"
    fi
    ceph_adjust_cache_flush_bytes
}

# $1 - pool name (e.g.: $BUILTIN_BACKPOOL)
ceph_osd_enable_cache()
{
    local BACKPOOL=${1:-$BUILTIN_BACKPOOL}
    local CACHEPOOL=$(ceph_get_cache_by_backpool $BACKPOOL)
    if [ -z "$CACHEPOOL" ]; then
        echo "Error: no cache associated with backpool: $1"
        ceph_backpool_cache_list
        return 1
    fi

    # associate backdev, ceph osd tier add {cold} {hot}
    if ! $CEPH osd tier add $BACKPOOL $CACHEPOOL; then
        # failed to add tier pool, recreate it
        ceph_recreate_cache_pool $BACKPOOL
        $CEPH osd tier add $BACKPOOL $CACHEPOOL
    fi
    $CEPH osd tier set-overlay $BACKPOOL $CACHEPOOL
    # set cache mode, ceph osd tier cache-mode ${hot} ${mode}
    $CEPH osd tier cache-mode $CACHEPOOL readproxy
    $CEPH osd pool set $CACHEPOOL hit_set_type bloom
    $CEPH osd pool set $CACHEPOOL hit_set_period 28800
    # set cache size

    $CEPH osd pool set $CACHEPOOL cache_min_flush_age 600
    $CEPH osd pool set $CACHEPOOL cache_min_evict_age 43200
    ceph_osd_cache_profile_set $BACKPOOL default
    ceph_adjust_cache_flush_bytes
}

ceph_osd_disable_cache()
{
    local BACKPOOL=${1:-$BUILTIN_BACKPOOL}
    local CACHEPOOL=$(ceph_get_cache_by_backpool $BACKPOOL)
    if [ -z "$CACHEPOOL" ]; then
        echo "Error: no cache associated with backpool: $1"
        ceph_backpool_cache_list
        return 1
    fi

    if echo "$BACKPOOL" | grep -q "[-]pool$"; then
        local BUCKET=${BACKPOOL%-pool}
        local RULE=$BUCKET
        local RULE_SSD=${BUCKET}-ssd
        local RULE_HDD=${BUCKET}-hdd
    else
        if [ "$CACHEPOOL" = "$BUILTIN_CACHEPOOL" ]; then
            local FSMETAPOOL="cephfs_metadata"
        fi
        local BUCKET=default
        local RULE=replicated_rule
        local RULE_SSD=rule-ssd
        local RULE_HDD=rule-hdd
    fi

    $CEPH osd pool ls | grep -q "^${BACKPOOL}$" || exit 1
    $CEPH osd pool ls | grep -q "^${CACHEPOOL}$" || exit 1
    [ "x$(ceph_osd_test_cache $BACKPOOL)" = "xon" ] || exit 1

    # set to forward so no more dirty objects
    rados -p $CACHEPOOL cache-flush-evict-all &>/dev/null || true
    $CEPH osd tier cache-mode $CACHEPOOL none --yes-i-really-mean-it || true
    # flush cache
    # It's ok to have dirty objects when cache-mode is readproxy, which
    # makes possible no downtime while switching on/off cache
    rados -p $CACHEPOOL cache-flush-evict-all &>/dev/null || true
    # de-couple hot/cold devices
    $CEPH osd tier remove-overlay $BACKPOOL
    $CEPH osd tier remove $BACKPOOL $CACHEPOOL

    if [ "$BACKPOOL" = "$BUILTIN_BACKPOOL" ]; then
        for p in $($CEPH osd pool ls); do
            case $p in
                *-pool|*-cache|*-ssd)
                    continue
                    ;;
                *)
                    if ! $CEPH osd pool get $p erasure_code_profile >/dev/null 2>&1; then
                        if [ "x$(ceph_osd_test_cache $p)" != "xon" ]; then
                            $CEPH osd pool get $p crush_rule | grep -q replicated_rule || $CEPH osd pool set $p crush_rule $RULE
                        fi
                    fi
                    ;;
            esac
        done
    elif echo "$BACKPOOL" | grep -q "[-]pool$"; then
        $CEPH osd pool set $BACKPOOL crush_rule $RULE
        $CEPH osd pool set $CACHEPOOL crush_rule $RULE
    else
        if [ "x$(ceph_osd_test_cache $BUILTIN_BACKPOOL)" = "xon" ]; then
            $CEPH osd pool set $BACKPOOL crush_rule $RULE_HDD
        else
            $CEPH osd pool set $BACKPOOL crush_rule $RULE
        fi
        $CEPH osd pool set $CACHEPOOL crush_rule $RULE
    fi
    # Don't remove rule-ssd because it could be used by cinder-volumes-ssd pool
    # Don't remove rule-hdd because it could be used by other cache pools
}

# $1 - pool name (e.g.: $BUILTIN_BACKPOOL)
ceph_osd_create_cache()
{
    local BACKPOOL=${1:-$BUILTIN_BACKPOOL}
    local CACHEPOOL=$(ceph_get_cache_by_backpool $1)
    if [ -z "$CACHEPOOL" ]; then
        echo "Error: no cache associated with backpool: $1"
        ceph_backpool_cache_list
        return 1
    fi

    if echo "$BACKPOOL" | grep -q "[-]pool$"; then
        local BUCKET=${BACKPOOL%-pool}
        local RULE=$BUCKET
        local RULE_SSD=${BUCKET}-ssd
        local RULE_HDD=${BUCKET}-hdd
    else
        if [ "$CACHEPOOL" = "$BUILTIN_CACHEPOOL" ]; then
            local FSMETAPOOL="cephfs_metadata"
        fi
        local BUCKET=default
        local RULE=replicated_rule
        local RULE_SSD=rule-ssd
        local RULE_HDD=rule-hdd
    fi

    ceph_osd_enable_cache $BACKPOOL

    if ! ($CEPH osd crush rule list | grep -q $RULE_SSD); then
        # create $RULE
        $CEPH osd crush rule create-replicated $RULE_SSD $BUCKET host ssd
    fi
    if ! ($CEPH osd crush rule list | grep -q $RULE_HDD); then
        # create $RULE
        $CEPH osd crush rule create-replicated $RULE_HDD $BUCKET host hdd
    fi
    if ! ($CEPH osd pool get $CACHEPOOL crush_rule | grep -q $RULE_SSD); then
        # set ${hot} rule for cache tier
        $CEPH osd pool set $CACHEPOOL crush_rule $RULE_SSD
    fi
    if [ "$BACKPOOL" = "$BUILTIN_BACKPOOL" ]; then
        if ! ($CEPH osd pool get $FSMETAPOOL crush_rule | grep -q $RULE_SSD); then
            # set ${hot} rule for cache tier
            $CEPH osd pool set $FSMETAPOOL crush_rule $RULE_SSD
        fi
        for p in $($CEPH osd pool ls); do
            case $p in
                $BUILTIN_CACHEPOOL|cephfs_metadata)
                    continue
                    ;;
                *-pool|*-cache|*-ssd)
                    continue
                    ;;
                *)
                    if ! $CEPH osd pool get $p erasure_code_profile >/dev/null 2>&1; then
                        if ! ($CEPH osd pool get $p crush_rule | grep -q $RULE_HDD); then
                            $CEPH osd pool set $p crush_rule $RULE_HDD
                        fi
                    fi
                    ;;
            esac
        done
    else
        $CEPH osd pool set $BACKPOOL crush_rule $RULE_HDD
    fi
}

# $1 - backpool name (e.g.: $BUILTIN_BACKPOOL)
ceph_recreate_cache_pool()
{
    local BACKPOOL=${1:-$BUILTIN_BACKPOOL}
    local CACHEPOOL=$(ceph_get_cache_by_backpool $BACKPOOL)
    if [ -z "$CACHEPOOL" ]; then
        echo "Error: no cache associated with backpool: $BACKPOOL"
        ceph_backpool_cache_list
        return 1
    fi
    local SIZE=$($CEPH osd pool get $CACHEPOOL size | awk '{print $2}' | tr -d '\n')

    $CEPH osd pool delete $CACHEPOOL $CACHEPOOL --yes-i-really-really-mean-it
    ceph_create_pool $CACHEPOOL rbd
    ceph_adjust_pool_size "$CACHEPOOL" $SIZE
    local PGS=$($CEPH osd pool get $BACKPOOL pg_num -f json | jq -r .pg_num)
    $CEPH osd pool set $CACHEPOOL pg_num $PGS  --yes-i-really-mean-it >/dev/null 2>&1
    $CEPH osd pool set $CACHEPOOL pgp_num $PGS >/dev/null 2>&1
}

# $1: pool name
# $2: peer name
ceph_mirror_pool_peer_set()
{
    local pool=$1
    local peer=$2

    if ! rbd mirror pool info $pool --format json | jq -r .peers[].site_name 2>/dev/null | grep -q $peer; then
        rbd mirror pool peer add $pool $peer >/dev/null 2>&1
    fi
}

# params:
# $1: mirror mode
# $2: image id(s)
ceph_mirror_image_enable()
{
    local mode=journal
    local interval=15m
    if [ "$1" = "snapshot" -o "$1" = "journal" ]; then
        mode=$1
        shift
        if [ "$mode" = "snapshot" ]; then
            interval=$1
            shift
        fi
    fi

    local vols=$(openstack volume list --all-projects -f json)
    for i in $* ; do
        local img_id=${i#volume-}
        local img_name=volume-${img_id}
        if rbd info $BUILTIN_BACKPOOL/$img_name >/dev/null 2>&1 ; then
            local img_info=$(rbd info $BUILTIN_BACKPOOL/${img_name} --format json 2>/dev/null)
            local enabled=$(echo $img_info | jq -r '.mirroring.state')
            local sshcmd="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
            local peer_vip=$(find /etc/ceph/ -type f -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//" | cut -d"-" -f2)


            if [ "$enabled" != "enabled" ]; then
                local parent_pool=$(echo $img_info | jq -r '.parent.pool')
                local parent_img=$(echo $img_info | jq -r '.parent.image')
                if [ "$parent_img" != "null" ]; then
                    local p_info=$(rbd info $parent_pool/$parent_img --format json 2>/dev/null)
                    local p_enabled=$(echo $p_info | jq -r '.mirroring.state')
                    if [ "$p_enabled" != "enabled" ]; then
                        Quiet rbd mirror image enable $parent_pool/$parent_img $mode
                    fi
                fi
                Quiet $sshcmd root@$peer_vip "rbd remove $BUILTIN_BACKPOOL/${img_name} >/dev/null 2>&1"
                if rbd mirror image enable $BUILTIN_BACKPOOL/${img_name} $mode >/dev/null 2>&1 ; then
                    printf "%60s enabled in $mode mode\n" $BUILTIN_BACKPOOL/${img_name}
                    os_volume_meta_sync $peer_vip NEEDNOPASS $img_id
                    if [ "$mode" = "snapshot" ]; then
                        Quiet -n rbd mirror snapshot schedule remove --pool $BUILTIN_BACKPOOL --image $img_name
                        Quiet -n rbd mirror snapshot schedule add --pool $BUILTIN_BACKPOOL --image $img_name $interval
                        Quiet -n $sshcmd root@$peer_vip "rbd mirror snapshot schedule remove --pool $BUILTIN_BACKPOOL --image $img_name"
                        Quiet -n $sshcmd root@$peer_vip "rbd mirror snapshot schedule add --pool $BUILTIN_BACKPOOL --image $img_name $interval"
                    fi

                    local server_id=$(echo $vols | jq -r ".[] | select(.ID == \"${img_id}\").\"Attached to\"[].server_id")
                    if [ "x${server_id}" != "x" ]; then
                        local server_info=$(openstack server show ${server_id:-EMPTYSERVERID} --format json)
                        local proj_id=$(echo "$server_info" | jq -r .project_id)
                        local proj=$(openstack project list -f value | grep "$proj_id " | awk '{print $2}')
                        server_info=$(echo "$server_info" | jq -r | sed "s/\"project_id\": .*/\"project_name\": \"$proj\",/")
                        local mirror_dir=/var/lib/ceph/rbd-mirror
                        local server_file=$mirror_dir/$(echo $server_info | jq -r .name)
                        mkdir -p $mirror_dir ; echo "$server_info" > $server_file
                        Quiet cubectl node rsync -r control $server_file
                        echo "$server_info" | $sshcmd root@$peer_vip "mkdir -p $mirror_dir ; cat - > $server_file" 2>/dev/null
                        Quiet $sshcmd root@$peer_vip "cubectl node rsync -r control $server_file"
                    fi
                else
                    printf "%60s failed to enable in $mode mode\n" $BUILTIN_BACKPOOL/${img_name}
                fi
            else
                printf "%60s is already enabled\n" $BUILTIN_BACKPOOL/${img_name}
            fi
        else
            printf "%60s does not exist\n" $BUILTIN_BACKPOOL/${img_name} && continue
        fi
    done
}

# params:
# $1: image id
ceph_mirror_image_disable()
{
    local mirror_dir=/var/lib/ceph/rbd-mirror
    for i in $* ; do
        local img_id=${i#volume-}
        local img_name=volume-${img_id}
        local sshcmd="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

        if rbd info $BUILTIN_BACKPOOL/$img_name >/dev/null 2>&1 ; then
            if [ "$(rbd info $BUILTIN_BACKPOOL/$img_name --format json | jq -r .mirroring.primary)" = "true" ]; then
                echo "$BUILTIN_BACKPOOL/${img_name}"
                rbd mirror image disable $BUILTIN_BACKPOOL/$img_name --force
                local peer_vip=$(find /etc/ceph/ -type f -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//" | cut -d"-" -f2)
                Quiet $sshcmd root@$peer_vip "hex_sdk ceph_mirror_image_meta_remove $img_id"
            else
                printf "%60s is not primary\n" $BUILTIN_BACKPOOL/${img_name} && continue
            fi
        else
            printf "%60s does not exist\n" $BUILTIN_BACKPOOL/${img_name} && continue
        fi
    done
}

# $1: image id
ceph_mirror_image_meta_remove()
{
    local img_id=$1
    local vol=$(openstack volume show $img_id -f json)

    rbd mirror image disable $BUILTIN_BACKPOOL/volume-$img_id --force 2>/dev/null
    echo $vol | jq -r ".attachments[].server_id" | xargs -i openstack server stop {} 2>/dev/null || true
    echo $vol | jq -r ".attachments[].server_id" | xargs -i openstack server delete {} 2>/dev/null || true
    openstack volume delete $img_id
}

ceph_mirror_avail_volume_list()
{
    if [ "$VERBOSE" == "1" ]; then
        local FLAG="-v"
    fi

    local vols=$(hex_sdk $FLAG os_list_volume_by_tenant_basic)
    for img_name in $(rbd mirror pool status $BUILTIN_BACKPOOL --verbose --format json | jq -r .images[].name 2>/dev/null) ; do
        vols=$(echo "$vols" | grep -v ${img_name#volume-})
    done
    [ -z "$vols" ] || echo "$vols"
}

ceph_mirror_added_volume_list()
{
    if [ "$VERBOSE" == "1" ]; then
        local FLAG="-v"
    fi

    local vols=$(hex_sdk $FLAG os_list_volume_by_tenant_basic)
    for img_name in $(rbd mirror pool status $BUILTIN_BACKPOOL --verbose --format json | jq -r .images[].name 2>/dev/null) ; do
        echo "$vols" | grep "${img_name#volume-}" 2>/dev/null
    done
}

# params:
# $1: pool name
# $2: [promoted|demoted]
ceph_mirror_image_list()
{
    local pool=${1:-$BUILTIN_BACKPOOL}
    local images=
    if [ "$2" = "promoted" ]; then
        images=$(rbd mirror pool status $pool --verbose --format json | jq -r ".images[] | select(.description == \"local image is primary\").name" 2>/dev/null)
    elif [ "$2" = "demoted" ]; then
        images=$(rbd mirror pool status $pool --verbose --format json | jq -r ".images[] | select(.description != \"local image is primary\").name" 2>/dev/null)
    else
        images=$(rbd mirror pool status $pool --verbose --format json | jq -r .images[].name 2>/dev/null)
    fi

    for img_name in $images
    do
        if [ "$VERBOSE" == "1" ]; then
            echo "$img_name"
        else
            echo "${img_name/volume-/}"
        fi
    done
}

ceph_mirror_image_state_sync()
{
    local enabled=$1
    for img_name in $(rbd mirror pool status $BUILTIN_BACKPOOL --verbose --format json | jq -r .images[].name 2>/dev/null)
    do
        local img_id=${img_name/volume-/}
        if ! echo "$enabled" | grep -q $img_id; then
            echo "disable mirrored image $img_name from $BUILTIN_BACKPOOL"
            rbd mirror image disable $BUILTIN_BACKPOOL/${img_name} --force 2>/dev/null
        fi
    done
}

ceph_mirror_parent_image_remove()
{
    local id=$1
    local pool=${2:-glance-images}

    rbd snap unprotect $pool/${id}@snap
    rbd snap purge $pool/$id
    rbd remove $pool/$id
}

ceph_mirror_disable()
{
    # sequence matters: glance is the parent of cinder
    # disable children pool/images first
    for pool in $BUILTIN_BACKPOOL glance-images
    do
        # remove peers
        for peer_id in $(timeout 5 rbd mirror pool info $pool --format json 2>/dev/null | jq -r .peers[].uuid 2>/dev/null)
        do
            echo "remove peer $peer_id from pool $pool"
            rbd mirror pool peer remove $pool $peer_id
        done

        for img_name in $(timeout 5 rbd mirror pool status $pool --verbose --format json 2>/dev/null | jq -r .images[].name 2>/dev/null)
        do
            echo "disable mirroring $img_name from pool $pool"
            if [ "$pool" = "$BUILTIN_BACKPOOL" ]; then
                ceph_mirror_image_disable $img_name
            else
                rbd mirror image disable glance-images/$img_name --force
            fi
        done

        timeout 5 rbd mirror pool disable $pool 2>/dev/null
    done
}

# params:
# $1: site name
ceph_mirror_status()
{
    local self_site=$(find /etc/ceph/ -type l -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//")
    local self_status=$(rbd mirror pool status $BUILTIN_BACKPOOL --verbose --cluster $self_site --format json 2>/dev/null)
    local self_health=$(echo $self_status | jq -r .summary.daemon_health)
    self_status=$(echo $self_status | jq -c '.images | sort_by(.name) | unique_by(.name)')
    local border="+----------------------------------------------+----------------------------------------------+"
    local peer_site=$(find /etc/ceph/ -type f -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//")
    local peer_status=$(rbd mirror pool status $BUILTIN_BACKPOOL --verbose --cluster $peer_site --format json 2>/dev/null)
    local peer_health=$(echo $peer_status | jq -r .summary.daemon_health)
    peer_status=$(echo $peer_status | jq -c '.images | sort_by(.name) | unique_by(.name)')
    echo "Local time: $(date +'%Y-%m-%d %H:%M:%S')"
    printf "%s\n" $border
    printf "| %44s | %44s |\n" "(local) $self_site $self_health" "(remote) $peer_site $peer_health"

    if [ -z "$self_site" -o -z "$peer_site" ]; then
        printf "%s\n" $border && return 0
    fi

    local vols=$(openstack volume list --all-projects -f json)
    local ins=$(openstack server list --all-projects -f value -c ID -c Name)
    :> /tmp/${self_site}.status
    local img_idx=0
    local img_num=$(echo $self_status | jq 'length')
    img_num=${img_num:-0}
    while [ $img_idx -lt $img_num ] ; do
        local img_name=$(echo $self_status | jq -r --arg idx $img_idx '.[$idx | tonumber].name')
        local vol_id=${img_name#volume-}
        local vol_info=$(rbd info $BUILTIN_BACKPOOL/$img_name --format json)
        local vol_mode=$(echo "$vol_info" | jq -r ".mirroring.mode")
        local img_state=$(echo $self_status | jq -r --arg idx $img_idx '.[$idx | tonumber].state')
        local peer_img_state=$(echo $peer_status | jq -r ".[] | select(.name == \"${img_name}\").state" | sort -u)
        local self_desc=$(echo $self_status | jq -r ".[] | select(.name == \"${img_name}\").description" 2>/dev/null)
        local peer_desc=$(echo $peer_status | jq -r ".[] | select(.name == \"${img_name}\").description" 2>/dev/null)
        local self_sync=$self_desc
        local peer_sync=${peer_desc/local /remote }
        if [ "$(echo $vol_info | jq -r .mirroring.mode)" = "snapshot" ]; then
            if [  "$self_desc" != "local image is primary" ]; then
                local next_schedule="$(rbd mirror snapshot schedule status --pool $BUILTIN_BACKPOOL --image $img_name --cluster $self_site --format json 2>/dev/null | jq -r .[].schedule_time)"
                [ -n "$next_schedule" ] || next_schedule="$(rbd mirror snapshot schedule status --pool $BUILTIN_BACKPOOL --image $img_name --cluster $peer_site --format json 2>/dev/null | jq -r .[].schedule_time)"
                local snapshot_interval="$(rbd mirror snapshot schedule ls --pool $BUILTIN_BACKPOOL --image $img_name --cluster $self_site 2>/dev/null)"
                [ -n "$snapshot_interval" ] || snapshot_interval="$(rbd mirror snapshot schedule ls --pool $BUILTIN_BACKPOOL --image $img_name --cluster $peer_site 2>/dev/null)"
                local self_sync="next sync ${next_schedule#20*-}(${snapshot_interval#every })"
            fi
        else
            local self_behind=$(echo $self_status | jq -r ".[] | select(.name == \"${img_name}\").description" | awk -F', ' '{print $2}' | jq -r .entries_behind_primary 2>/dev/null)
            if [ -n "$self_behind" ]; then
                if [ "$self_behind" = "0" ]; then
                    self_sync="synced"
                else
                    self_sync="${self_behind:-unknown} entries behind"
                fi
            fi
        fi

        if [ "$(echo $vol_info | jq -r .mirroring.mode)" = "snapshot" ]; then
            if [  "$peer_desc" != "local image is primary" ]; then
                local next_schedule="$(rbd mirror snapshot schedule status --pool $BUILTIN_BACKPOOL --image $img_name --cluster $self_site --format json 2>/dev/null | jq -r .[].schedule_time)"
                [ -n "$next_schedule" ] || next_schedule="$(rbd mirror snapshot schedule status --pool $BUILTIN_BACKPOOL --image $img_name --cluster $peer_site --format json 2>/dev/null | jq -r .[].schedule_time)"
                local snapshot_interval="$(rbd mirror snapshot schedule ls --pool $BUILTIN_BACKPOOL --image $img_name --cluster $self_site 2>/dev/null)"
                [ -n "$snapshot_interval" ] || snapshot_interval="$(rbd mirror snapshot schedule ls --pool $BUILTIN_BACKPOOL --image $img_name --cluster $peer_site 2>/dev/null)"
                local peer_sync="next sync ${next_schedule#20*-}(${snapshot_interval#every })"
            fi
        else
            local peer_behind=$(echo $peer_status | jq -r ".[] | select(.name == \"${img_name}\").description" | awk -F', ' '{print $2}' | jq -r .entries_behind_primary 2>/dev/null)
            if [ -n "$peer_behind" ]; then
                if [ "$peer_behind" = "0" ]; then
                    peer_sync="synced"
                else
                    peer_sync="${peer_behind:-unknown} entries behind"
                fi
            fi
        fi
        local vol_name=$(echo $vols | jq -r ".[] | select(.ID == \"${vol_id}\").Name")
        local vol_status=$(echo $vols | jq -r ".[] | select(.ID == \"${vol_id}\").Status")
        local vol_size=$(echo $vols |  jq -r ".[] | select(.ID == \"${vol_id}\").Size")G
        [ "$vol_size" != "G" ] || vol_size=$(rbd info $BUILTIN_BACKPOOL/$img_name --format json | jq -r .size)B
        local device=$(echo $vols | jq -r ".[] | select(.ID == \"${vol_id}\").\"Attached to\"[0].device")
        local srv_id=$(echo $vols | jq -r ".[] | select(.ID == \"${vol_id}\").\"Attached to\"[0].server_id")
        local host=$(echo "$ins;" | grep ${srv_id:-NOSRVID} | awk '{print $2}')
        [ "$device" = "null" -o -z "$host" ] || vol_attach="$device on $host"

        if [ "$vol_status" == "in-use" ]; then
            device=$(echo $vols | jq -r ".[] | select(.ID == \"${vol_id}\").\"Attached to\"[0].device")
            srv_id=$(echo $vols | jq -r ".[] | select(.ID == \"${vol_id}\").\"Attached to\"[0].server_id")
            host=$(echo "$ins" | grep ${srv_id:-NOSRVID} | awk '{print $2}')
        fi
        echo "${vol_id},${vol_mode},${vol_name},${vol_size},${device},${host},${self_sync},${img_state},${peer_sync},${peer_img_state}" >> /tmp/${self_site}.status
        img_idx=$(( img_idx + 1 ))
    done

    cat /tmp/${self_site}.status | sort -t"," -k6 |  while read -r line; do
        local vol_id=$(echo $line | cut -d"," -f 1)
        local vol_mode=$(echo $line | cut -d"," -f 2)
        local vol_name=$(echo $line | cut -d"," -f 3)
        local vol_size=$(echo $line | cut -d"," -f 4)
        local device=$(echo $line | cut -d"," -f 5)
        local host=$(echo $line | cut -d"," -f 6)
        local self_sync=$(echo $line | cut -d"," -f 7)
        local img_state=$(echo $line | cut -d"," -f 8)
        local peer_sync=$(echo $line | cut -d"," -f 9)
        local peer_img_state=$(echo $line | cut -d"," -f 10)

        local vol_attach=
        if [ "x$host" = "x" -o "x$host" = "xnull" -o "x$host" != "x$prev_host" ]; then
            printf "%s\n" $border
        fi

        if [ -n "$device" -a -n "$host" ]; then
            vol_attach="$device on $host"
        fi
        printf "| %36s%10s %44s |\n" "${vol_id}" "(${vol_mode})" "${vol_name}(${vol_size}) ${vol_attach}"
        printf "| %29s %14s | %29s %14s |\n" "$self_sync" "$img_state" "$peer_sync" "$peer_img_state"
        prev_host=$host
    done
    printf "%s\n" $border
}

ceph_mirror_promoted_instance_list()
{
    local mirror_dir=/var/lib/ceph/rbd-mirror
    local servers=$(ls -1 ${mirror_dir}/* 2>/dev/null)

    for srv in $servers ; do
        local server_info=$(cat $srv)
        local name=$(echo $server_info | jq -r .name)
        local project=$(echo $server_info | jq -r .project_name)
        local flavor=$(echo $server_info | jq -r .flavor | cut -d" " -f1)
        local network=$(echo $server_info | jq -r | grep addresses -A1 | tail -1 | cut -d":" -f1 | xargs)
        local volume_ids=$(echo $server_info | jq -r ".attached_volumes[].id")
        local vols_promoted=true

        for vid in $volume_ids ; do
            img_name="volume-$vid"
            if Quiet rbd info $BUILTIN_BACKPOOL/$img_name 2>/dev/null; then
                if [ "$(rbd info $BUILTIN_BACKPOOL/$img_name --format json | jq -r .mirroring.primary)" = "true" ]; then
                    continue
                else
                    vols_promoted=false
                fi
            else
                vols_promoted=false
            fi

        done

        if [ "$vols_promoted" = "true" ]; then
            if [ "$VERBOSE" == "1" ]; then
                echo "$name,$project,$flavor,$network,$(echo $volume_ids)"
            else
                echo "$name"
            fi
        fi
    done
}

ceph_mirror_create_server()
{
    local mirror_dir=/var/lib/ceph/rbd-mirror

    for srv in $*; do
        local server_info=$(cat $mirror_dir/$srv)
        local name=$(echo $server_info | jq -r .name)
        local project=$(echo $server_info | jq -r .project_name)
        local flavor=$(echo $server_info | jq -r .flavor | cut -d" " -f1)
        local network=$(echo $server_info | jq -r | grep addresses -A1 | tail -1 | cut -d":" -f1 | xargs)
        local volume_ids=$(echo $server_info | jq -r ".attached_volumes[].id")
        local bootable_vid=
        local vol_status=

        openstack flavor list --format value -c Name | grep -q "$flavor" || echo "Mirror site has no flavor: $flavor"

        for vid in $volume_ids; do
            local vol_info=$(openstack volume show $vid --format json)
            if [ "$(echo $vol_info | jq -r .bootable)" = "true" ]; then
                bootable_vid=$vid
                vol_status=$(echo $vol_info | jq -r .status)
                break
            fi
        done

        local server_id=$(openstack server list --project $project --format value -c Name -c ID | grep "$name" | cut -d" " -f1)
        if [ -n "$bootable_vid" -a "$vol_status" != "in-use" ]; then
            if [ "x$server_id" = "x" ]; then
                server_id=$(OS_PROJECT_NAME=$project openstack server create --network $network --flavor $flavor --volume $bootable_vid --wait --format value -c id $name)
                if [ "x$server_id" = "x" ]; then
                    echo "failed to create service instance" && continue
                else
                    echo "created server: $name ${server_id:-EMPTYSERVERID}"
                fi
            else
                if openstack server show $server_id --format json | jq -r .attached_volumes[].id | grep -q "$bootable_vid" ; then
                    echo "server existed: $name ${server_id:-EMPTYSERVERID}"
                else
                    echo "please manually fix duplicated server name: $server" && continue
                fi
            fi
        else
            if [ -n "$server_id" ]; then
                openstack server start ${server_id:-EMPTYSERVERID} 2>/dev/null
            else
                echo "bootable volume image of server ($name ${server_id:-EMPTYSERVERID}) is not yet mirrored" && continue
            fi
        fi

        local server_status=$(openstack server show ${server_id:-EMPTYSERVERID} --format value -c status)
        if [ -z "$server_status" ]; then
            echo "unable to create server: $name"
        elif [ "$server_status" = "SHUTOFF" ]; then
            echo "unable to start server ($name ${server_id:-EMPTYSERVERID}) as not all of its volumes were promoted"
        elif [ "$server_status" = "ERROR" ]; then
            openstack server delete ${server_id:-EMPTYSERVERID} 2>/dev/null
            echo "deleted server ($name ${server_id:-EMPTYSERVERID}) in ERROR state"
            echo "make sure all volumes belonging to this server were promoted to primary"
        else
            for vid in $volume_ids; do
                local vol_info=$(openstack volume show $vid --format json)
                if [ "$vid" != "$bootable_vid" -a "$(openstack volume show $vid --format json | jq -r .status)" = "available" ]; then
                    if openstack server add volume ${server_id:-EMPTYSERVERID} $vid ; then
                        echo "attached server $name with volume: $vid"
                    else
                        echo "unable to attach server: $name with volume: $vid"
                    fi
                fi
            done
        fi
    done
}

# params:
# $1: volume id
# $2: normal|force
ceph_mirror_promote_image()
{
    local id=${1#volume-}
    local name=volume-${id}
    local mode=${2:-normal}
    local status=$(rbd mirror pool status $BUILTIN_BACKPOOL --verbose --format json 2>/dev/null)
    local img_idx=0
    local img_num=$(echo $status | jq '.images | length')
    img_num=${img_num:-0}
    local sshcmd="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
    local peer_vip=$(find /etc/ceph/ -type f -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//" | cut -d"-" -f2)

    if [ "$mode" = "force" ]; then
        local RBDFLG="--force"
        while [ $img_idx -lt $img_num ]
        do
            local img_name=$(echo $status | jq -r --arg idx $img_idx '.images[$idx | tonumber].name')
            if [ "$img_name" = "$name" -a "$(rbd info $BUILTIN_BACKPOOL/$img_name --format json | jq -r .mirroring.primary)" = "false" ]; then
                echo "$mode promote $BUILTIN_BACKPOOL/$img_name on local site"
                for i in {1..10}; do
                    sleep 10
                    Quiet rbd mirror image promote $RBDFLG $BUILTIN_BACKPOOL/$img_name 2>/dev/null && break
                done

                if timeout 3 $sshcmd root@${peer_vip:-emptyIp} "exit 0" 2>/dev/null; then
                    Quiet $sshcmd root@${peer_vip:-emptyIp} "hex_sdk ceph_mirror_demote_image $id $mode"
                else
                    echo "remote site $peer_vip unreachable"
                fi
                break
            fi
            img_idx=$(( img_idx + 1 ))
        done
    else
        local RBDFLG=
        while [ $img_idx -lt $img_num ]
        do
            local img_name=$(echo $status | jq -r --arg idx $img_idx '.images[$idx | tonumber].name')
            if [ "$img_name" = "$name" -a "$(rbd info $BUILTIN_BACKPOOL/$img_name --format json | jq -r .mirroring.primary)" = "false" ]; then
                if timeout 3 $sshcmd root@${peer_vip:-emptyIp} "exit 0" 2>/dev/null; then
                    Quiet $sshcmd root@${peer_vip:-emptyIp} "hex_sdk ceph_mirror_demote_image $id $mode"
                else
                    RBDFLG="--force"
                fi
                echo "$mode promote $BUILTIN_BACKPOOL/$img_name on local site"
                for i in {1..10}; do
                    sleep 10
                    Quiet rbd mirror image promote $RBDFLG $BUILTIN_BACKPOOL/$img_name 2>/dev/null && break
                done
            fi
            img_idx=$(( img_idx + 1 ))
        done
    fi
}

# params:
# $1: normal/force
ceph_mirror_demote_image()
{
    local id=${1#volume-}
    local name=volume-${id}
    local mode=${2:-normal}
    local status=$(rbd mirror pool status $BUILTIN_BACKPOOL --verbose --format json 2>/dev/null)
    local img_idx=0
    local img_num=$(echo $status | jq '.images | length')
    img_num=${img_num:-0}

    while [ $img_idx -lt $img_num ]
    do
        local img_name=$(echo $status | jq -r --arg idx $img_idx '.images[$idx | tonumber].name')
        if [ "$img_name" = "$name" ]; then
            local vol=$(openstack volume show $id -f json)
            echo $vol | jq -r ".attachments[].server_id" | xargs -i openstack server stop {} 2>/dev/null || true
            if [ "$mode" = "force" ]; then
                sleep 10
                rbd mirror image demote $BUILTIN_BACKPOOL/$img_name >/dev/null 2>&1
                rbd mirror image resync $BUILTIN_BACKPOOL/$img_name >/dev/null 2>&1
            else
                ( sleep 10 ; rbd config image set $BUILTIN_BACKPOOL/$img_name rbd_cache_block_writes_upfront true ; rbd config image set $BUILTIN_BACKPOOL/$img_name rbd_cache_block_writes_upfront false ; rbd mirror image demote $BUILTIN_BACKPOOL/$img_name) >/dev/null 2>&1 &
                PIDS[${img_idx}]=$!
            fi
            break
        fi
        img_idx=$(( img_idx + 1 ))
    done
    if [ "$mode" != "force" ]; then
        for P in ${PIDS[*]}; do
            wait $P && echo "RBD journal upfronted ($P)"
        done
    fi

    local self_site=$(find /etc/ceph/ -type l -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//")
    cubectl node exec -r control "systemctl restart ceph-rbd-mirror@${self_site}.service >/dev/null 2>&1"
}

# params:
# $1: normal/force
ceph_mirror_promote_site()
{
    local mode=${1:-normal}
    local status=$(rbd mirror pool status $BUILTIN_BACKPOOL --verbose --format json 2>/dev/null)
    local img_idx=0
    local img_num=$(echo $status | jq '.images | length')
    img_num=${img_num:-0}
    local sshcmd="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
    local peer_vip=$(find /etc/ceph/ -type f -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//" | cut -d"-" -f2)

    if [ "$mode" = "force" ]; then
        local RBDFLG="--force"
        while [ $img_idx -lt $img_num ]
        do
            local img_name=$(echo $status | jq -r --arg idx $img_idx '.images[$idx | tonumber].name')
            if [ "$(rbd info $BUILTIN_BACKPOOL/$img_name --format json | jq -r .mirroring.primary)" = "false" ]; then
                echo "$mode promote $BUILTIN_BACKPOOL/$img_name on local site"
                for i in {1..10}; do
                    sleep 10
                    Quiet rbd mirror image promote $RBDFLG $BUILTIN_BACKPOOL/$img_name 2>/dev/null && break
                done
            fi
            img_idx=$(( img_idx + 1 ))
        done
        if timeout 3 $sshcmd root@${peer_vip:-emptyIp} "exit 0" 2>/dev/null ; then
            Quiet $sshcmd root@${peer_vip:-emptyIp} "hex_sdk ceph_mirror_demote_site $mode"
        else
            echo "remote site $peer_vip unreachable"
        fi
    else
        local RBDFLG=
        if timeout 3 $sshcmd root@${peer_vip:-emptyIp} "exit 0" 2>/dev/null ; then
            Quiet $sshcmd root@${peer_vip:-emptyIp} "hex_sdk ceph_mirror_demote_site $mode"
        else
            echo "remote site $peer_vip unreachable"
            RBDFLG="--force"
        fi
        while [ $img_idx -lt $img_num ]
        do
            local img_name=$(echo $status | jq -r --arg idx $img_idx '.images[$idx | tonumber].name')
            if [ "$(rbd info $BUILTIN_BACKPOOL/$img_name --format json | jq -r .mirroring.primary)" = "false" ]; then
                echo "$mode promote $BUILTIN_BACKPOOL/$img_name on local site"
                for i in {1..10}; do
                    sleep 10
                    Quiet rbd mirror image promote $RBDFLG $BUILTIN_BACKPOOL/$img_name 2>/dev/null && break
                done
            fi
            img_idx=$(( img_idx + 1 ))
        done
    fi
}

# params:
# $1: normal/force
ceph_mirror_demote_site()
{
    local mode=${1:-normal}
    local status=$(rbd mirror pool status $BUILTIN_BACKPOOL --verbose --format json 2>/dev/null)
    local img_idx=0
    local img_num=$(echo $status | jq '.images | length')
    img_num=${img_num:-0}

    while [ $img_idx -lt $img_num ]
    do
        local img_name=$(echo $status | jq -r --arg idx $img_idx '.images[$idx | tonumber].name')
        local vol=$(openstack volume show ${img_name#volume-} -f json)
        echo $vol | jq -r ".attachments[].server_id" | xargs -i openstack server stop {} 2>/dev/null || true
        echo "$mode demote $BUILTIN_BACKPOOL/$img_name pool on peer site"
        if [ "$mode" = "force" ]; then
            sleep 10
            rbd mirror image demote $BUILTIN_BACKPOOL/$img_name >/dev/null 2>&1
            rbd mirror image resync $BUILTIN_BACKPOOL/$img_name >/dev/null 2>&1
        else
            ( sleep 10 ; rbd config image set $BUILTIN_BACKPOOL/$img_name rbd_cache_block_writes_upfront true ; rbd config image set $BUILTIN_BACKPOOL/$img_name rbd_cache_block_writes_upfront false ; rbd mirror image demote $BUILTIN_BACKPOOL/$img_name) >/dev/null 2>&1 &
            PIDS[${img_idx}]=$!
        fi

        img_idx=$(( img_idx + 1 ))
    done
    if [ "$mode" != "force" ]; then
        for P in ${PIDS[*]}; do
            wait $P && echo "RBD journal upfronted ($P)"
        done
    fi

    local self_site=$(find /etc/ceph/ -type l -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//")
    cubectl node exec -r control "systemctl restart ceph-rbd-mirror@${self_site}.service >/dev/null 2>&1"
}

# return crush class by SCSI disk
# params: $1 - partition name (e.g.: /dev/sdb)
ceph_osd_get_class()
{
    local DEV=$1
    if ceph-volume lvm list --format json | jq -r ".[][] | select(.devices[] == \"$DEV\").devices[]" | grep -q "^${DEV}$"; then
        :
    elif echo $DEV | grep -q 'sd'; then
        DEV=$(echo $DEV | sed -e 's/[0-9]*$/1/g')
    elif echo $DEV | grep -q 'nvme'; then
        DEV="$(echo $DEV | grep -oe '/dev/nvme[0-9]\+n[0-9]\+')p1"
    fi

    local OSD_ID=$(ceph_osd_get_id $DEV)
    [ -n "$OSD_ID" ] || return 1
    local CLASS_TYPE=$($CEPH osd tree -f json | jq -r --arg OSDID $OSD_ID '.nodes[] | select((.id == ($OSDID | tonumber))).device_class')
    echo -n $CLASS_TYPE
}

# list osd id by partition
# params: $1 - partition name (e.g.: /dev/sdd1)
# return: int (e.g.: 1)
ceph_osd_get_id()
{
    local DEV=$1
    # check if device exists
    [ -n "$(readlink -e $DEV)" ] || Error "no such device $DEV"

    local UUID=$(GetBlkUuid $DEV)
    [ "x$UUID" != "x" ] || Error "$DEV uuid not found"

    # get osd_id from device osd map
    if [ -f $CEPH_OSD_MAP ]; then
        local ID0=$(cat $CEPH_OSD_MAP | grep $DEV | awk '{print $2}')
        if [ -n "$ID0" ]; then
            if grep "$DEV" $CEPH_OSD_MAP | grep -q "$UUID" ; then
                echo -n $ID0
                return 0
            fi
        fi
    fi

    # get osd_id from mount point map
    local ID1=$(lsblk $DEV -d -n -o MOUNTPOINT | grep -m 1 -oe '[0-9]\+$')
    if [ -n "$ID1" ]; then
        echo -n $ID1
        return 0
    fi

    # get osd_id from ceph osd dump
    local ID2=$($CEPH osd dump | grep "$UUID" 2>/dev/null | grep -oe '^osd\.[0-9]\+' | grep -m 1 -oe '[0-9]\+')
    if [ -n "$ID2" ]; then
        echo -n $ID2
        return 0
    fi

    # get osd_id from ceph-volume lvm
    local ID3=$(ceph-volume lvm list --format json | jq -r ".[][] | select(.devices[] == \"$DEV\").tags.\"ceph.osd_id\"")
    NUM_RE='^[0-9]+$'
    if [[ $ID3 =~ $NUM_RE ]]; then
        echo -n $ID3
        return 0
    fi

    # in case of fresh install when there's no osd_id for newly-prepared data disks, create a new one
    local RETRYCNT=30
    local ID4=$($CEPH osd new $UUID 2>/dev/null)
    while [ -z "$ID4" ]; do
        sleep 1
        ID4=$($CEPH osd new $UUID 2>/dev/null)
        [ "$RETRYCNT" -gt 0 ] || break
        RETRYCNT=$((RETRYCNT-1))
    done
    echo -n $ID4
    return 0
}

ceph_osd_get_datapart()
{
    local METAPART=$1
    local DATAPART=
    # check if osd meta partition exists
    [ -n "$(readlink -e $METAPART)" ] || return 1
    DATAPART_PARTUUID=$(grep $METAPART $CEPH_OSD_MAP 2>/dev/null | cut -d" " -f4)
    DATAPART=$(blkid -o device  --match-token PARTUUID=$DATAPART_PARTUUID 2>/dev/null)
    if [ "x$DATAPART" = "x" ]; then
        local METAPART_NUM=$(echo ${METAPART} | grep -o "[0-9]$")
        local METAPART_STEM=$(echo ${METAPART} | sed "s/[0-9]$//")
        DATAPART=${METAPART_STEM}$((METAPART_NUM + 2))
    fi

    echo -n $DATAPART
}

ceph_osd_get_datapartuuid()
{
    local METAPART=$1
    local DATAPART_PARTUUID=
    # check if osd meta partition exists
    [ -n "$(readlink -e $METAPART)" ] || return 1
    DATAPART_PARTUUID=$(grep $METAPART $CEPH_OSD_MAP 2>/dev/null | cut -d" " -f4)
    if [ "x$DATAPART_PARTUUID" = "x" ]; then
        local METAPART_NUM=$(echo ${METAPART} | grep -o "[0-9]$")
        local METAPART_STEM=$(echo ${METAPART} | sed "s/[0-9]$//")
        local DATAPART=${METAPART_STEM}$((METAPART_NUM + 2))
        DATAPART=$(blkid | grep -e 'PARTLABEL=\"cube_data' | cut -d":" -f1 | grep $DATAPART)
        DATAPART_PARTUUID=$(blkid -o value -s PARTUUID $DATAPART)
    fi

    echo -n $DATAPART_PARTUUID
}

ceph_osd_remount()
{
    local OSDPTH=/var/lib/ceph/osd

    for OSD_DIR in $(find ${OSDPTH}/* -type d); do
        OSD_ID=${OSD_DIR##*-}
        if systemctl is-active ceph-osd@$OSD_ID -q; then
            $CEPH tell osd.$OSD_ID compact >/dev/null 2>&1 || true
            systemctl stop ceph-osd@$OSD_ID || true
        fi
        umount $OSD_DIR 2>/dev/null || true
    done

    while read LINE; do
        DEV=$(echo $LINE | cut -d" " -f1)
        OSD_ID=$(echo $LINE | cut -d" " -f2)
        DATAPART_PARTUUID=$(echo $LINE | cut -d" " -f4)
        LVM_JSON=$(ceph-volume lvm list $OSD_ID --format json)
        if echo $LVM_JSON | jq -r .[][].lv_uuid | grep -q "$DATAPART_PARTUUID"; then
            :
        else
            mkdir -p ${OSDPTH}/ceph-${OSD_ID}
            chmod 0755 ${OSDPTH}/ceph-${OSD_ID}
            mount $DEV $OSDPTH/ceph-${OSD_ID}
            if [ "x$(readlink $OSDPTH/ceph-$OSD_ID/block)" != "x/dev/disk/by-partuuid/$DATAPART_PARTUUID" ]; then
                unlink $OSDPTH/ceph-$OSD_ID/block 2>/dev/null
                (cd $OSDPTH/ceph-$OSD_ID && ln -sf /dev/disk/by-partuuid/$DATAPART_PARTUUID block)
            fi
            systemctl start ceph-osd@$OSD_ID
        fi
    done < $CEPH_OSD_MAP
}

ceph_osd_create_map()
{
    local OSDPTH=/var/lib/ceph/osd
    local OSDMAP_NEW=$(mktemp -u /tmp/dev_osd.mapXXXX)
    local OSDMAP_JSON=$(ceph-volume raw list --format json)

    if [ $(echo $OSDMAP_JSON | jq -r "keys[]" | wc -l) -gt 0 ]; then
        for METAPART_UUID in $(echo $OSDMAP_JSON | jq -r "keys[]"); do
            METAPART=$(readlink -f /dev/disk/by-uuid/$METAPART_UUID)
            OSD_ID=$(echo $OSDMAP_JSON | jq -r ".\"$METAPART_UUID\".osd_id")
            if [ ! -e $METAPART ] ; then
                LVM_JSON=$(ceph-volume lvm list $OSD_ID --format json)
                METAPART=$(echo $LVM_JSON | jq -r .[][].devices[] | sort -u)
                DATAPART=$METAPART
                DATAPART_PARTUUID=$(echo $LVM_JSON | jq -r .[][].lv_uuid)
            else
                DATAPART=$(echo $OSDMAP_JSON | jq -r ".\"$METAPART_UUID\".device")
                DATAPART_PARTUUID=$(blkid -o value -s PARTUUID $DATAPART)
            fi
            echo "${METAPART:-METAPART} ${OSD_ID:-OSD_ID} ${METAPART_UUID:-METAPART_UUID} ${DATAPART_PARTUUID:-DATAPART_PARTUUID}" >> $OSDMAP_NEW
        done
    fi
    cat $OSDMAP_NEW | sort -k1 > ${OSDMAP_NEW}.sorted
    unlink $OSDMAP_NEW
    if cmp -s ${OSDMAP_NEW}.sorted $CEPH_OSD_MAP ; then
        rm -f ${OSDMAP_NEW}.sorted
    else
        mv -f ${OSDMAP_NEW}.sorted $CEPH_OSD_MAP
    fi
    # clean up broken ceph osd folders
    for OSDDIR in $(ls -1d ${OSDPTH}/ceph-*) ; do
        if ! readlink -e ${OSDDIR}/block ; then
            rm -f ${OSDDIR}/block
            rmdir ${OSDDIR}
        fi
    done
}

ceph_wait_for_services()
{
    local COUNT=${1:-12}

    if ! Quiet $CEPH -s ; then
        # When HA cluster is powercycled, master node or any control node running alone has no quorum yet
        if [ $(cubectl node list -r control | wc -l) -gt 1 ]; then
            if [ $(cubectl node exec -r control -pn "systemctl is-active ceph-mon@\$HOSTNAME" | grep -i "^active$" | wc -l) -eq 1 ]; then
                return 0
            fi
        fi
    fi

    for i in $(seq $COUNT); do
        local FAIL=0
        $CEPH -s >/dev/null 2>&1 || ((FAIL++))
        ! ( $CEPH -s | grep -q "mgr: no daemons active" ) || ((FAIL++))
        ! ( $CEPH -s | grep -q "mds: 0.* up" ) || ((FAIL++))
        ! ( $CEPH -s | grep -q "volumes: 0.* healthy" ) || ((FAIL++))
        [[ $FAIL -ne 0 ]] || break
        sleep 10
    done

    return $FAIL
}

ceph_wait_for_status()
{
    local STATUS=${1:-ok}
    local TIMEOUT=${2:-60}

    Quiet $CEPH -s || return 0

    local i=0
    while [ $i -lt $TIMEOUT ]; do
        if $($CEPH health | grep -i -q $STATUS); then
            break;
        fi
        sleep 1
        i=$(expr $i + 1)
    done
}

ceph_osd_map()
{
    local OSD_TREE=$($CEPH osd tree -f json)

    readarray id_array <<<"$(echo $OSD_TREE | jq '.nodes[] | select(.type == "osd").id' | sort)"
    declare -p id_array > /dev/null
    for id in "${id_array[@]}"
    do
        id=$(echo -n $id | tr -d '\n')
        local host=$(echo $OSD_TREE | jq -r --arg OSDID $id '.nodes[] | select(.type == "host") | select(.children[] | select(. == ($OSDID | tonumber))).name')
        local dev=$(ssh $host sh -c "mount | grep 'ceph-$id '" 2>/dev/null | awk '{print $1}')
        echo "$id,$host,$dev"
    done
}

ceph_osd_repair()
{
    local OSD_PTH="/var/lib/ceph/osd/ceph-$1"

    if [ -e $OSD_PTH ]; then
        Quiet ceph_enter_maintenance || true
        Quiet $CEPH tell osd.$1 compact || true
        Quiet systemctl stop ceph-osd@$1 || true
        Quiet ceph-bluestore-tool repair --path $OSD_PTH 2>/dev/null || true
        Quiet ceph-kvstore-tool bluestore-kv $OSD_PTH compact 2>/dev/null || true
        Quiet systemctl start ceph-osd@$1 || true
        Quiet ceph_leave_maintenance || true
    else
        echo "$OSD_PTH not found on $(hostname)"
    fi
}

ceph_force_create_pg()
{
    local STATE=$1
    local LOST=$2

    readarray pg_array <<<"$($CEPH pg dump_stuck inactive unclean stale undersized degraded 2>/dev/null | grep $STATE | awk '{print $1}' | sort | uniq)"
    declare -p pg_array > /dev/null
    for pg in "${pg_array[@]}"
    do
        if [ -n "$pg" ]; then
            $CEPH osd force-create-pg $pg --yes-i-really-mean-it
            if [ "$LOST" == "lost" ]; then
                $CEPH pg $pg mark_unfound_lost delete
            fi
        fi
    done
}

ceph_force_create_unhealth_pg()
{
    local lost=$1

    readarray state_array <<<"$($CEPH -s -f json | jq -r .pgmap.pgs_by_state[].state_name | egrep -v "^active\+clean$")"
    declare -p state_array > /dev/null
    for obj in "${state_array[@]}"
    do
        local state=$(echo $obj | tr -d '\n')
        if [ -n "$state" ]; then
            ceph_force_create_pg $state $lost
        fi
    done
}

ceph_restful_username_list()
{
    $CEPH restful list-keys | jq -r 'keys[]'
}

ceph_restful_key_create()
{
    local username=$1
    $CEPH restful create-key $username
}

ceph_restful_key_delete()
{
    local username=$1
    $CEPH restful delete-key $username
}

ceph_restful_key_list()
{
    $CEPH restful list-keys
}

ceph_mgr_module_enable()
{
    local MODULE=$1
    local TIMEOUT=${2:-2}

    for i in 1 2 3 4 5 ; do ! $CEPH mgr module ls >/dev/null 2>&1 || break ; done

    local i=0
    while [ $i -lt $TIMEOUT ]; do
        local ready=$($CEPH mgr dump | jq -r .available | tr -d '\n')
        if [ "$ready" == "true" ]; then
            if ! $CEPH mgr module ls -f json | jq -r .enabled_modules[] | grep -q $MODULE; then
                $CEPH mgr module enable $MODULE 2>/dev/null
            else
                break;
            fi
        fi
        sleep 1
        i=$(expr $i + 1)
    done
}

ceph_mon_msgr2_enable()
{
    local TIMEOUT=${1:-60}

    $CEPH mon enable-msgr2 2>/dev/null
    local i=0
    while [ $i -lt $TIMEOUT ]; do
        if $CEPH -s | grep -q "not enabled msgr2"; then
            $CEPH mon enable-msgr2 2>/dev/null
        else
            break;
        fi
        sleep 10
        i=$(expr $i + 1)
    done
}

ceph_basic_config_gen()
{
    local conf=$1
    local host=$2
    local pass=$3
    if [ -n "$host" -a -n "$pass" ]; then
        local header=$(sshpass -p "$pass" ssh root@$host $CEPH config generate-minimal-conf &2>/dev/null)
    elif [ -n "$host" -a -z "$pass" ]; then
        local sshcmd="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
        local header=$($sshcmd root@$host "$CEPH config generate-minimal-conf 2>/dev/null" 2>/dev/null)
    else
        local header=$($CEPH config generate-minimal-conf &2>/dev/null)
    fi
    echo "$header" > $conf
    echo "        rbd concurrent management ops = 20" >> $conf
    echo "        auth cluster required = none" >> $conf
    echo "        auth service required = none" >> $conf
    echo "        auth client required = none" >> $conf
}

ceph_dashboard_init()
{
    local shareId=$1
    local name=dashboard

    Quiet $CEPH -s || return 0

    $CEPH dashboard set-ssl-certificate -i /var/www/certs/server.cert
    $CEPH dashboard set-ssl-certificate-key -i /var/www/certs/server.key
    $CEPH dashboard set-iscsi-api-ssl-verification false
    $CEPH dashboard set-rgw-api-ssl-verify false
    $CEPH dashboard set-grafana-api-ssl-verify false
    $CEPH dashboard set-grafana-api-url https://$shareId/grafana
    if ! timeout 5 radosgw-admin user list | jq -r .[] | grep -q $name; then
        local info=$(timeout 5 radosgw-admin user create --uid=$name --display-name=$name --system)
        echo "$(echo $info | jq -r .keys[0].access_key)" > /tmp/ceph_rgw_access_key
        echo "$(echo $info | jq -r .keys[0].secret_key)" > /tmp/ceph_rgw_secret_key
        $CEPH dashboard set-rgw-api-access-key -i /tmp/ceph_rgw_access_key
        $CEPH dashboard set-rgw-api-secret-key -i /tmp/ceph_rgw_secret_key
    fi
    $CEPH dashboard set-pwd-policy-enabled false
    echo "admin" > /tmp/ceph_admin_pass
    $CEPH dashboard ac-user-create admin -i /tmp/ceph_admin_pass administrator
    rm -f /tmp/ceph_ceph_admin_pass /tmp/ceph_rgw_access_key /tmp/ceph_rgw_secret_key
    $CEPH dashboard feature disable nfs
    $CEPH dashboard feature disable iscsi
}

ceph_dashboard_iscsi_gw_add()
{
    local addr=$1
    local password=$2

    if ! $CEPH dashboard iscsi-gateway-list | jq .gateways | jq -r 'keys[]' | grep -q $HOSTNAME; then
        local GW_CFG=$(mktemp /tmp/iscsigw.XXXX)
        echo "http://admin:$password@$addr:5010" >$GW_CFG
        $CEPH dashboard iscsi-gateway-add -i $GW_CFG
        rm -f $GW_CFG
    fi
}

ceph_dashboard_iscsi_gw_rm()
{
    if $CEPH dashboard iscsi-gateway-list | jq .gateways | jq -r 'keys[]' | grep -q $HOSTNAME; then
        $CEPH dashboard iscsi-gateway-rm $HOSTNAME >/dev/null
    fi
}

ceph_dashboard_idp_config()
{
    local SHARED_ID=$1
    local PORT=$2
    local TIMEOUT=${3:-2}
    local i=0

    Quiet $CEPH -s || return 0

    while [ $i -lt $TIMEOUT ]; do
        if ! curl -k https:/$SHARED_ID:$PORT/ceph/auth/saml2/metadata 2>/dev/null | grep -q "entityID.*$SHARED_ID"; then
            $CEPH dashboard sso setup saml2 \
                  https://$SHARED_ID:$PORT \
                  /etc/keycloak/saml-metadata.xml \
                  username \
                  https://$SHARED_ID:10443/auth/realms/master \
                  /var/www/certs/server.cert /var/www/certs/server.key
            $CEPH dashboard sso enable saml2
        else
            curl -k https://$SHARED_ID:$PORT/ceph/auth/saml2/metadata | xmllint --format - > /etc/keycloak/ceph_dashboard_sp_metadata.xml
            # WHY?! run twice to make configure default client scope work
            terraform-cube.sh apply -auto-approve -target=module.keycloak_ceph_dashboard -var cube_controller=$SHARED_ID >/dev/null
            terraform-cube.sh apply -auto-approve -target=module.keycloak_ceph_dashboard -var cube_controller=$SHARED_ID >/dev/null
            break;
        fi
        sleep 1
        i=$(expr $i + 1)
    done
}

ceph_mount_cephfs()
{
    if $CEPH -s >/dev/null ; then
        for i in {1..3}; do
            if [ $(mount | grep $CEPHFS_STORE_DIR | wc -l) -gt 1 ]; then
                timeout $SRVSTO umount $CEPHFS_STORE_DIR 2>/dev/null || umount -l $CEPHFS_STORE_DIR 2>/dev/null
            fi
            if [ $(mount | grep $CEPHFS_STORE_DIR | wc -l) -lt 1 ]; then
                timeout $SRVSTO mount -t ceph :/ $CEPHFS_STORE_DIR -o name=admin,secretfile=/etc/ceph/admin.key >/dev/null 2>&1 && break
            fi
            sleep 5
        done
    fi
}

ceph_node_group_list()
{
    if $CEPH -s >/dev/null ; then
        for BUCKET in $($CEPH osd tree | grep root | awk '{print $4}'); do
            printf %.1s ={1..60} $'\n'
            printf "%.60s\n" "GROUP: $BUCKET"

            $CEPH osd tree-from $BUCKET
        done
    fi
}

ceph_create_node_group()
{
    if [ $# -lt 2 ]; then
        echo "Usage: $0 group node(host) [<node2(host2)...>]"
        ceph_node_group_list
        exit 1
    fi

    local GROUP=$1
    shift 1

    if [ "$GROUP" = "default" ]; then
        local POOL=$BUILTIN_BACKPOOL
        local CPOOL=$BUILTIN_CACHEPOOL
        local RULE=replicated_rule
    else
        local POOL=${GROUP}-pool
        local CPOOL=${GROUP}-cache
        local RULE=${GROUP}
    fi

    local B_SIZE=$($CEPH osd pool get $BUILTIN_BACKPOOL size | awk '{print $2}' | tr -d '\n')
    local C_SIZE=$($CEPH osd pool get $BUILTIN_CACHEPOOL size | awk '{print $2}' | tr -d '\n')
    local NODE_IN_DFT=$($CEPH osd crush ls default | sort | uniq)
    local NODE_IN_DFT_CNT=$($CEPH osd crush ls default | sort | uniq | wc -l)
    for O in $NODE_IN_DFT; do
        for P in $*; do
            if [ "x$O" = "x$P" ]; then
                ((NODE_IN_DFT_CNT--))
                break
            fi
        done
    done
    if [ ${NODE_IN_DFT_CNT:-0} -lt ${B_SIZE:-1} ]; then
        echo "WARNING OF MISCONFIGURATIONS: num of remaining nodes($NODE_IN_DFT_CNT) in default group CANNOT be fewer than $B_SIZE"
        ceph_node_group_list
        exit 1
    fi

    if ! ($CEPH osd pool ls | grep -q $POOL); then
        ceph_create_pool $POOL rbd
        ceph_create_pool $CPOOL rbd
    fi

    if ! ($CEPH osd tree | grep root | grep -q $GROUP); then
        $CEPH osd crush add-bucket $GROUP root
    fi

    for N in $*; do
        $CEPH osd crush move $N root=$GROUP
    done

    local HOST_NUM=$($CEPH osd crush ls $GROUP | sort | uniq | wc -l)
    if [ $B_SIZE -gt $HOST_NUM ]; then
        B_SIZE=$HOST_NUM
        C_SIZE=$(expr $B_SIZE - 1)
    fi

    # set pool/cache size to the same as $BUILTIN_BACKPOOL/$BUILTIN_CACHEPOOL which were determined at set_ready
    ceph_adjust_pool_size "$POOL" $B_SIZE
    ceph_adjust_pool_size "$CPOOL" $C_SIZE

    if ! ($CEPH osd crush rule list | grep -q $RULE); then
        $CEPH osd crush rule create-replicated $RULE $GROUP host
    fi

    if ! ($CEPH osd pool get $POOL crush_rule | grep -q "$RULE"); then
        $CEPH osd pool set $POOL crush_rule $RULE
        $CEPH osd pool set $CPOOL crush_rule $RULE
    fi
    $CEPH osd pool get $POOL crush_rule

    os_volume_type_create $GROUP $POOL

    cubectl node exec -pn -r storage "hex_config restart_ceph_osd"
    cubectl node exec -pn -r control "hex_config reconfig_cinder"
    cubectl node exec -pn -r control "hex_config restart_cinder"

    # Make another attempt to ensure osds are up
    readarray node_array <<<"$(/usr/sbin/cubectl node list -r storage -j | jq -r .[].hostname | sort)"
    for node_entry in "${node_array[@]}"; do
        local node=$(echo $node_entry | head -c -1)
        ssh root@$node "systemctl is-active ceph-osd@* --quiet" || ssh root@$node "hex_config restart_ceph_osd"
    done
    # It can happen that openstack-cinder-volume stops after hex_config reconfig_cinder
    openstack volume service set --enable cube@${POOL} cinder-volume 2>/dev/null
    Quiet hex_cli -c cluster check_repair HaCluster 2>/dev/null
}

ceph_remove_node_group()
{
    if [ $# != 1 ]; then
        echo "Usage: $0 Group"
        ceph_node_group_list
        exit 1
    fi

    local GROUP=$1
    if [ "$GROUP" = "default" ]; then
        echo "Waring: $GROUP is a must-have bucket by system" && exit 1
    else
        local POOL=${GROUP}-pool
        local CPOOL=${GROUP}-cache
        local RULE=${GROUP}
    fi

    # Before deleting pools, try to free up volumes in use
    for VID in $(openstack volume list --all-projects --long --format value -c ID -c Name -c Status | grep $GROUP | grep "in-use" | cut -d' ' -f1); do
        for SID in $(openstack server list --long --format value -c ID); do
            if openstack server show $SID | grep "$VID"; then
                openstack server remove volume $SID $VID || openstack server delete $SID || true
            fi
        done
    done
    openstack volume list --all-projects --long --format value  -c ID -c Type | grep $GROUP | cut -d' ' -f1 | xargs -i openstack volume delete --force {} || true

    if [ "$(ceph_osd_test_cache $POOL)" == "on" ]; then
        ceph_osd_disable_cache $POOL
    fi

    if ($CEPH osd pool ls | grep -q $POOL); then
        $CEPH osd pool delete $POOL $POOL --yes-i-really-really-mean-it
        $CEPH osd pool delete $CPOOL $CPOOL --yes-i-really-really-mean-it
    fi

    for N in $($CEPH osd crush ls $GROUP); do
        $CEPH osd crush move $N root=default
    done

    if ($CEPH osd crush rule list | grep -q "^$RULE$"); then
        $CEPH osd crush rule rm $RULE
    fi

    if ($CEPH osd tree | grep root | grep -q "$GROUP"); then
        $CEPH osd crush rm $GROUP
    fi

    openstack volume type delete $GROUP

    cubectl node exec -pn -r storage "hex_config restart_ceph_osd"
    cubectl node exec -pn -r control "hex_config reconfig_cinder"
    cubectl node exec -pn -r control "hex_config restart_cinder"

    openstack volume service set --disable cube@$POOL cinder-volume >/dev/null 2>&1 || true
    cinder-manage service remove cinder-volume cube@$POOL >/dev/null 2>&1 || true
    # It can happen that openstack-cinder-volume stops after hex_config reconfig_cinder
    Quiet hex_cli -c cluster check_repair HaCluster 2>/dev/null

    # Make another attempt to ensure osds are up
    readarray node_array <<<"$(/usr/sbin/cubectl node list -r storage -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}"; do
        local node=$(echo $node_entry | head -c -1)
        ssh root@$node "systemctl is-active ceph-osd@* --quiet" || ssh root@$node "hex_config restart_ceph_osd"
    done
}

ceph_create_group_ssdpool()
{
    local GROUP=${1:-default}

    if [ "$GROUP" = "default" ]; then
        local POOL=${BUILTIN_BACKPOOL}-ssd
        local CPOOL=$BUILTIN_CACHEPOOL
        local RULE=rule-ssd
        local VTYPE=CubeStorage-ssd
    else
        local POOL=${GROUP}-ssd
        local CPOOL=${GROUP}-cache
        local RULE=${GROUP}-ssd
        local VTYPE=${GROUP}-ssd
    fi

    if ! ($CEPH osd crush rule list | grep -q "^$RULE_SSD$"); then
        $CEPH osd crush rule create-replicated $RULE $GROUP host ssd || return 1
    fi

    ceph_create_pool $POOL rbd

    local C_SIZE=$($CEPH osd pool get $CPOOL size | awk '{print $2}' | tr -d '\n')
    ceph_adjust_pool_size "$POOL" $C_SIZE
    $CEPH osd pool set $POOL crush_rule $RULE
    os_volume_type_create $VTYPE $POOL

    cubectl node exec -pn -r control "hex_config reconfig_cinder"
    cubectl node exec -pn -r control "hex_config restart_cinder"
    # It can happen that openstack-cinder-volume stops after hex_config reconfig_cinder
    openstack volume service set --enable cube@${POOL} cinder-volume 2>/dev/null
    Quiet hex_cli -c cluster check_repair HaCluster 2>/dev/null
}

ceph_remove_group_ssdpool()
{
    local GROUP=${1:-default}

    if [ "$GROUP" = "default" ]; then
        local POOL=${BUILTIN_BACKPOOL}-ssd
        local VTYPE=CubeStorage-ssd
    else
        local POOL=${GROUP}-ssd
        local VTYPE=${GROUP}-ssd
    fi

    openstack volume type delete $VTYPE 2>/dev/null || true
    for i in {1..15}; do
        openstack volume type list --long --format value -c Name | grep -q "^$VTYPE$" || break
    done

    if openstack volume type list --long --format value -c Name | grep -q "^$VTYPE$"; then
        echo "Error: Volume type $VTYPE was not deleted possibly due to existing volumes. " && return 1
    else
        if ($CEPH osd pool ls | grep -q "^$POOL$"); then
            $CEPH osd pool delete $POOL $POOL --yes-i-really-really-mean-it
        fi
        cubectl node exec -pn -r control "hex_config reconfig_cinder"
        cubectl node exec -pn -r control "hex_config restart_cinder"
        # It can happen that openstack-cinder-volume stops after hex_config reconfig_cinder
        Quiet hex_cli -c cluster check_repair HaCluster 2>/dev/null

    fi

    openstack volume service set --disable cube@$POOL cinder-volume >/dev/null 2>&1 || true
    cinder-manage service remove cinder-volume cube@$POOL >/dev/null 2>&1 || true
}

ceph_osd_restart()
{
    local OSD_IDS=${*:-$($CEPH osd tree-from $(hostname) -f json 2>/dev/null | jq .nodes[0].children[] | sort -n)}
    Quiet ceph-volume lvm activate --all 2>/dev/null
    for ID in $OSD_IDS; do
        local OSD_PTH="/var/lib/ceph/osd/ceph-$ID"
        if [ -e $OSD_PTH ]; then
            ( $CEPH tell osd.$ID compact || true ; \
              systemctl stop ceph-osd@$ID ; \
              ceph-kvstore-tool bluestore-kv $OSD_PTH compact && \
                  systemctl start ceph-osd@$ID ) >/dev/null 2>&1 &
        fi
    done
}

ceph_osd_compact()
{
    if $CEPH -s >/dev/null ; then
        HN=$(hostname)
        [ "$VERBOSE" != "1" ] || $CEPH osd df tree $HN 2>/dev/null || true
        $CEPH osd tree-from $HN -f json 2>/dev/null | jq .nodes[0].children[] | sort -n | xargs -i ceph tell osd.{} compact
        [ "$VERBOSE" != "1" ] || $CEPH osd df tree $HN 2>/dev/null || true
    fi
}

ceph_osd_host_set()
{
    local HOST=${1:-$(hostname)}
    local STATUS=$2
    local OSD_IDS=$($CEPH osd tree-from $HOST -f json 2>/dev/null | jq .nodes[0].children[] | sort -n)

    for ID in $OSD_IDS; do
        $CEPH osd $STATUS $ID
    done
}

ceph_osd_relabel()
{
    local LABEL_PTH="/dev/disk/by-partlabel"
    local PREFIXES="cube_meta cube_data"
    local TYPE=
    local DEV=
    local DISK=
    local PART_PTH=
    local PART=
    local PART_SYMBOL=
    local PART_NUM=
    local SLINK_SYMBOL=
    local SLINK_NUM=

    [ -e $LABEL_PTH ] || return 0

    pushd $LABEL_PTH >/dev/null
    for PREFIX in $PREFIXES; do
        for SLINK in $(find . -type l -name "*${PREFIX}*" | sort); do
            PART_PTH=$(readlink -e $SLINK)
            PART=${PART_PTH#/dev/}
            DISK=$(lsblk $PART_PTH -s -r -o NAME,TYPE | grep disk | cut -d' ' -f1 | sort -u)

            if [[ $DISK =~ nvme ]]; then
                # PART: nvme0n1p1
                # DISK: nvme0n1
                # PART_SYMBOL=0n1
                # PART_NUM=p1
                TYPE=nvme
            else
                # PART: sda1
                # DISK: sda
                # PART_SYMBOL=a
                # PART_NUM=1
                TYPE=sd
            fi
            PART_SYMBOL=${DISK#*$TYPE}
            PART_NUM=${PART#$TYPE$PART_SYMBOL}

            SLINK_SYMBOL=$(echo $SLINK | cut -d'_' -f3)
            SLINK_NUM=$(echo $SLINK | cut -d'_' -f4)

            if [ "${PART_SYMBOL}${PART_NUM}" != "${SLINK_SYMBOL}${SLINK_NUM}" ]; then
                unlink $SLINK
                ln -sf ../../${TYPE}${PART_SYMBOL}${PART_NUM} ./${PREFIX}_${PART_SYMBOL}_${PART_NUM}
            fi
        done
    done
    popd >/dev/null
}

ceph_osd_fix_fsid()
{
    local ID=$1
    local OSD_PTH="/var/lib/ceph/osd/ceph-$ID"

    if [ -e $OSD_PTH ]; then
        if ! ceph-bluestore-tool bluefs-stats --path $OSD_PTH >/dev/null 2>&1 ; then
            uuidgen > $OSD_PTH/fsid
            local NEW_FSID=$(ceph-bluestore-tool bluefs-stats --path $OSD_PTH 2>&1 | grep -o "fsid.*" | awk '{print $2}')
            echo $NEW_FSID > $OSD_PTH/fsid
            chown ceph:ceph $OSD_PTH/fsid
        fi
    fi
}

# $1: vip
# $2: pass
ceph_mirror_pair()
{
    local vip=$1
    local pass=$2

    local sshcmd="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

    if [ -z "$vip" -o -z "$pass" ]; then
        echo "Usage: $0 ceph_mirror_pair vip pass" && return 1
    fi

    Quiet sshpass -p "$pass" $sshcmd root@$vip "exit 0" || Error "Incorrect password to root@$vip"

    local self_id_rsa_pub=$(cat /root/.ssh/id_rsa.pub)
    local auth_keys=/root/.ssh/authorized_keys
    Quiet sshpass -p "$pass" $sshcmd root@$vip "cubectl node exec -r control \"echo $self_id_rsa_pub >>$auth_keys\""
    Quiet sshpass -p "$pass" $sshcmd root@$vip "cubectl node exec -r control \"hex_sdk dedup_sshauthkey\""

    local peer_id_rsa_pub=$($sshcmd root@$vip cat /root/.ssh/id_rsa.pub 2>/dev/null)
    Quiet cubectl node exec -r control "echo $peer_id_rsa_pub >> $auth_keys"
    Quiet cubectl node exec -r control "hex_sdk dedup_sshauthkey"
    $sshcmd root@$vip "exit 0" || Error "ssh-key not exchanged"

    local self_vip=$(health_vip_report | cut -d"/" -f1)
    [ "$self_vip" != "non-HA" ] || self_vip=$(cat /etc/settings.cluster.json | jq -r ".[].ip.management")
    local self_ctlr=$(grep cubesys.controller /etc/settings.txt | cut -d"=" -f2 | xargs 2>/dev/null)-$self_vip
    if [ -z "$(echo $self_ctlr | cut -d"-" -f1)" ]; then
        self_ctlr=$(hostname)${self_ctlr}
    fi
    Quiet cubectl node exec -r control "ln -sf /etc/ceph/ceph.conf /etc/ceph/${self_ctlr}-site.conf"
    Quiet cubectl node exec -r control "systemctl enable ceph-rbd-mirror@${self_ctlr}-site.service >/dev/null 2>&1"
    Quiet cubectl node exec -r control "systemctl restart ceph-rbd-mirror@${self_ctlr}-site.service >/dev/null 2>&1"

    local peer_ctlr=$($sshcmd root@$vip "grep cubesys.controller /etc/settings.txt | cut -d'=' -f2 | xargs" 2>/dev/null)-$vip
    if [ -z "$(echo $peer_ctlr | cut -d"-" -f1)" ]; then
        peer_ctlr=$($sshcmd root@$vip hostname 2>/dev/null)${peer_ctlr}
    fi
    Quiet $sshcmd root@$vip cubectl node exec -r control "ln -sf /etc/ceph/ceph.conf /etc/ceph/${peer_ctlr}-site.conf"
    Quiet $sshcmd root@$vip cubectl node exec -r control "systemctl enable ceph-rbd-mirror@${peer_ctlr}-site.service >/dev/null 2>&1"
    Quiet $sshcmd root@$vip cubectl node exec -r control "systemctl restart ceph-rbd-mirror@${peer_ctlr}-site.service >/dev/null 2>&1"

    Quiet rbd mirror pool enable glance-images image
    Quiet rbd mirror pool enable cinder-volumes image
    Quiet $sshcmd root@$vip rbd mirror pool enable glance-images image
    Quiet $sshcmd root@$vip rbd mirror pool enable cinder-volumes image

    ceph_mirror_pool_peer_set glance-images ${peer_ctlr}-site
    ceph_mirror_pool_peer_set cinder-volumes ${peer_ctlr}-site
    Quiet $sshcmd root@$vip "hex_sdk ceph_mirror_pool_peer_set glance-images ${self_ctlr}-site"
    Quiet $sshcmd root@$vip "hex_sdk ceph_mirror_pool_peer_set cinder-volumes ${self_ctlr}-site"

    ceph_basic_config_gen /etc/ceph/${peer_ctlr}-site.conf $vip
    Quiet cubectl node rsync -r control /etc/ceph/${peer_ctlr}-site.conf
    Quiet $sshcmd root@$vip "hex_sdk ceph_basic_config_gen /etc/ceph/${self_ctlr}-site.conf $self_vip"
    Quiet $sshcmd root@$vip "cubectl node rsync -r control /etc/ceph/${self_ctlr}-site.conf"
}

ceph_mirror_unpair()
{
    local self_site=$(find /etc/ceph/ -type l -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//")
    local peer_site=$(find /etc/ceph/ -type f -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//")
    local peer_vip=$(echo $peer_site | cut -d"-" -f2)
    local sshcmd="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

    ceph_mirror_disable >/dev/null 2>&1

    if [ "x$peer_vip" = "x" ]; then
        echo "already unpaired" && exit 0
    fi

    Quiet $sshcmd root@$peer_vip "hex_sdk ceph_mirror_disable >/dev/null 2>&1"

    # Do these 2nd time if necessary
    if [ -n "$(rbd mirror pool status $BUILTIN_BACKPOOL 2>/dev/null)" -o -n "$(rbd mirror pool status glance-images 2>/dev/null)" ]; then
        Quiet ceph_mirror_disable
        Quiet $sshcmd root@$peer_vip "hex_sdk ceph_mirror_disable >/dev/null 2>&1"
    fi

    cubectl node exec -r control "systemctl stop ceph-rbd-mirror@${self_site}.service >/dev/null 2>&1"
    Quiet $sshcmd root@$peer_vip cubectl node exec -r control "systemctl stop ceph-rbd-mirror@${peer_site}.service >/dev/null 2>&1"

    cubectl node exec -r control rm -f /etc/ceph/${peer_site}.conf /etc/ceph/${self_site}.conf
    Quiet $sshcmd root@$peer_vip cubectl node exec -r control "rm -f /etc/ceph/${peer_site}.conf /etc/ceph/${self_site}.conf"

    local mirror_dir=/var/lib/ceph/rbd-mirror
    cubectl node exec -r control rm -rf $mirror_dir
    Quiet $sshcmd root@$peer_vip "cubectl node exec -r control rm -rf $mirror_dir"
}

ceph_mirror_restart()
{
    local self_site=$(find /etc/ceph/ -type l -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//")
    local peer_site=$(find /etc/ceph/ -type f -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//")
    local peer_vip=$(echo $peer_site | cut -d"-" -f2)
    local sshcmd="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

    cubectl node exec -r control systemctl restart ceph-rbd-mirror@$self_site
    Quiet $sshcmd root@${peer_vip:-emptyIp} "cubectl node exec -r control systemctl restart ceph-rbd-mirror@$peer_site"
}

ceph_fs_mds_init()
{
    $CEPH -s >/dev/null || Error "ceph quorum is not ready"
    ceph_mgr_module_enable stats
    if [ $(cubectl node list -r control | wc -l) -ge 3 ]; then
        $CEPH fs set cephfs allow_standby_replay true
        $CEPH fs set cephfs session_timeout 30
        $CEPH fs set cephfs session_autoclose 30
        ceph_fs_mds_reorder
    fi
}

ceph_fs_mds_reorder()
{
    if [ $(cubectl node list -r control | wc -l) -ge 3 ]; then
        $CEPH -s >/dev/null || Error "ceph quorum is not ready"
        [ "x$($CEPH fs status -f json | jq -r '.mdsmap[] | select(.state == "standby-replay").name')" != "x" ] || return 0

        local MON_LEADER=$($CEPH mon stat -f json | jq -r ".leader")
        local MDS_ACTIVE=$($CEPH fs status -f json | jq -r '.mdsmap[] | select(.state == "active").name')
        local MODERATOR=$(cubectl node list -j | jq -r '.[] | select(.role == "moderator").hostname')

        if [ "x$MODERATOR" != "x" ]; then
            if [ "x$MODERATOR" = "x$MON_LEADER" ]; then
                remote_run $MODERATOR systemctl restart ceph-mon@$MODERATOR
                sleep 15
                MON_LEADER=$($CEPH mon stat -f json | jq -r ".leader")
            fi
            $CEPH mds fail $MODERATOR
            sleep 3
            MDS_ACTIVE=$($CEPH fs status -f json | jq -r '.mdsmap[] | select(.state == "active").name')
            for i in {1..5}; do
                HOT_STANDBY=$($CEPH fs status -f json | jq -r '.mdsmap[] | select(.state == "standby-replay").name')
                if [ "x$HOT_STANDBY" != "x$MODERATOR" ]; then
                    $CEPH mds fail $HOT_STANDBY
                    sleep 3
                else
                    break
                fi
            done
        else
            for i in {1..5}; do
                HOT_STANDBY=$($CEPH fs status -f json | jq -r '.mdsmap[] | select(.state == "standby-replay").name')
                if [ "x$HOT_STANDBY" = "x$MON_LEADER" ]; then
                    $CEPH mds fail $HOT_STANDBY
                    sleep 3
                else
                    break
                fi
            done
        fi

        $CEPH mds fail $MDS_ACTIVE
    fi
}

ceph_nfs_ganesha()
{
    case $1 in
        enable)
            Quiet cubectl node exec -r control -p "systemctl unmask nfs-ganesha"
            Quiet cubectl node exec -r control -p "systemctl start nfs-ganesha"
            ;;
        disable)
            Quiet cubectl node exec -r control -p "systemctl stop nfs-ganesha"
            Quiet cubectl node exec -r control -p "systemctl mask nfs-ganesha"
            ;;
        *)
            echo "usage: ceph_nfs_ganesha enable|disable"
            ;;
    esac
}

ceph_pg_scrub()
{
    $CEPH health detail | grep 'not deep-scrubbed since' | awk '{print $2}' | while read pg; do ceph pg deep-scrub $pg; done
}

ceph_rbd_fsck()
{
    local SVID=${1:-SERVER_ID}  # openstack server id
    local VLID=$(openstack server show $SVID -f json | jq -r .attached_volumes[0].id)
    [ "x$VLID" != "xnull" ] || VLID=$SVID

    for P in $BUILTIN_BACKPOOL $BUILTIN_EPHEMERAL $(ceph osd pool ls | grep "[-]pool$") ; do
        DISK=$(rbd ls -p $P | grep $VLID | grep -v "[.]config$" | head -1)
        if [ "x$DISK" != "x" ] ; then
            RBD=$P/$DISK
            break
        fi
    done
    if rbd info $RBD >/dev/null ; then
        local MOUNTED_RBD=$(rbd map $RBD 2>/dev/null)
        [ ! -e ${MOUNTED_RBD}p1 ] || fsck -y ${MOUNTED_RBD}p1
        rbd unmap $MOUNTED_RBD
    fi
}

ceph_osd_set_bucket_host()
{
    local BUCKET=${1:-ephemeral}

    if $CEPH osd tree | grep -q "host $BUCKET"; then
        for H in $(cubectl node list -j | jq -r .[].hostname); do
            for O in $(hex_sdk remote_run $H "hex_sdk ceph_osd_list | head -2"); do
                ceph osd crush set $O 1.0 root=$BUCKET host=${BUCKET}_${H} 2>/dev/null
            done
        done
    fi
}

ceph_osd_list()
{
    local OSD_ID=${1#osd.}
    local OSD_IDS=$OSD_ID
    if [ "x$OSD_IDS" = "x" ]; then
        OSD_IDS=$($CEPH osd ls-tree $HOSTNAME 2>/dev/null)
    else
        $CEPH osd ls-tree $HOSTNAME 2>/dev/null | grep -q "^${OSD_ID}$" || return 0
    fi
    local HW_LS=$(lshw -class disk -json 2>/dev/null)
    local BLKDEVS=$(lsblk -J | jq -r .blockdevices[])
    local LVM=$(ceph-volume lvm list --format json)
    local VALID_OUTPUT="overall-health self-assessment test result:"
    local SMART_SUPPORTED="device has SMART capability"
    local SMART_UNAVAILABLE="Unavailable - device lacks SMART capability"
    local CHK_ATTRS="Reallocated_Sector_Ct "
    CHK_ATTRS+="Reported_Uncorrect "
    CHK_ATTRS+="Command_Timeout "
    CHK_ATTRS+="Current_Pending_Sector "
    CHK_ATTRS+="Offline_Uncorrect "
    CHK_ATTRS+="CRC_Error_Count"

    for OSD_ID in $OSD_IDS; do
        DEV=$(ceph_get_dev_by_id $OSD_ID)
        PARENT_DEV=/dev/$(echo $BLKDEVS | jq -r ". | select(.children[].name == \"${DEV#/dev/}\").name" 2>/dev/null)
        [ "$PARENT_DEV" != "/dev/" ] || PARENT_DEV=$DEV
        SMART_FLG="-a"
        SMART_LOG=$(smartctl $SMART_FLG $PARENT_DEV)
        SN=$(hex_sdk ceph_get_sn_by_dev $PARENT_DEV)
        STATE=ok
        REMARK=
        ENCRYPTED=$(echo $LVM | jq -r ".[][] | select(.devices[] == \"$PARENT_DEV\").tags.\"ceph.encrypted\"")

        if [ "x$ENCRYPTED" = "x1" ]; then
            LUKS_VER=$(cryptsetup luksDump $(echo $LVM | jq -r ".[][] | select(.devices[] == \"$PARENT_DEV\").lv_path") | grep -i version | awk '{print $2}')
            REMARK="LUKS${LUKS_VER}-encrypted,"
        fi
        if echo $SMART_LOG | grep -q -i 'megaraid,N' ; then
            SELECTED_DEV=$(echo $HW_LS | jq -r ".[] | select(.logicalname == \"${PARENT_DEV}\")")
            SELECTED_DEV_ID=$(echo $SELECTED_DEV | jq -r .id | cut -d":" -f2)
            SMART_FLG+=" -d megaraid,${SELECTED_DEV_ID}"
            SMART_LOG=$(smartctl $SMART_FLG $PARENT_DEV)
        fi

        if [ "$VERBOSE" = "1" ]; then
            [ "x$ENCRYPTED" != "x1" ] || cryptsetup luksDump $(echo $LVM | jq -r ".[][] | select(.devices[] == \"$PARENT_DEV\").lv_path")
            if echo $SMART_LOG | grep -i -P -o "$VALID_OUTPUT .*? " ; then
                smartctl $SMART_FLG $PARENT_DEV | grep 'ID.*RAW_VALUE' -A 100 | egrep 'prefailure warning|^$' -m1 -B100
            else
                smartctl $SMART_FLG $PARENT_DEV
            fi
            hdsentinel -dev $PARENT_DEV 2>/dev/null | sed 1,4d | grep -v -i "No actions needed"
            $CEPH osd df osd.$OSD_ID
            printf "%8s %8s %16s %10s %18s %10s %6s %s\n" "OSD" "STATE" "HOST" "DEV" "SERIAL" "POWER_ON" "USE" "REMARK"
        fi
        if echo $SMART_LOG | grep -q -i "$VALID_OUTPUT PASSED" ; then
            SMART_JSON=$(smartctl $SMART_FLG $PARENT_DEV -json)
            if [ "x$(echo $SMART_JSON | jq -r .ata_smart_attributes.table)" != "xnull" ] ; then
                for CHK in $CHK_ATTRS ; do
                    VAL=$(echo $SMART_JSON | jq -r ".ata_smart_attributes.table[] | select(.name == \"${CHK}\").raw.value")
                    if [ ${VAL:-0} -ne 0 ]; then
                        REMARK+="${CHK}:${VAL},"
                        STATE=warning
                    fi
                done
            fi
        elif echo $SMART_LOG | grep -q -i "$VALID_OUTPUT" ; then
            REMARK="did not pass self-assessment test"
            STATE=fail
        elif echo $SMART_LOG | grep -q -i "$SMART_SUPPORTED" ; then
            REMARK="SMART supported but no self-test results"
            STATE=fail
        elif echo $SMART_LOG | grep -q -i "$SMART_UNAVAILABLE" ; then
            REMARK="SMART not supported"
        else
            STATE=$($CEPH osd tree down -f json | jq -r ".nodes[] | select(.name == \"${OSD_ID}\").status")
            [ "x$STATE" = "xdown" ] || STATE=unknown
            REMARK="$(echo $SMART_LOG | grep -o -i 'device lacks SMART capability')"
        fi

        POWER_ON=$(hdsentinel -dev $PARENT_DEV | grep -i "power on time" | cut -d":" -f2 | cut -d "," -f1 | head -1 | xargs)
        USE=$(ceph osd df tree osd.$OSD_ID -f json | jq -r .summary.average_utilization)
        printf "%8s %8s %16s %10s %18s %10s %6s %s\n" $OSD_ID $STATE ${HOSTNAME%,} ${DEV#/dev/} ${SN%,} "${POWER_ON}" "${USE%.*}%" "${REMARK%,}"
    done
}
