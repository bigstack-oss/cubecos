# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

ceph_status()
{
    local type=${1:-na}

    $CEPH -s
    $CEPH osd status

    case $type in
        detail|details)
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
    local osd_id=${1#osd.}
    $CEPH osd ls 2>/dev/null | grep -q "${osd_id:-BADOSDID}" || return 1
    local host=$($CEPH osd find $osd_id -f json 2>/dev/null | jq -r .host)

    # make another attempt to find host
    if [ -z "$host" ] ; then
        host=$($CEPH device ls-by-daemon osd.$osd_id --format json 2>/dev/null | jq -r ".[].location[].host")
    fi
    if [ -z "$host" ] ; then
        host=$($CEPH osd tree -f json 2>/dev/null | jq -r --arg OSDID $osd_id '.nodes[] | select(.type == "host") | select(.children[] | select(. == ($OSDID | tonumber))).name')
    fi
    if [ -z "$host" ] ; then
        cubectl node exec -pn "ceph-volume lvm list --format json 2>/dev/null | jq -r '.[][] | select(.tags.\"ceph.osd_id\" == \"$osd_id\")' | grep -q osd-block && hostname"
    fi

    echo -n $host
}

ceph_get_ids_by_dev()
{
    local dev=$1
    # cehp device ls doesn't always sho correct osds associated with devices
    # local ids=$($CEPH device ls-by-host $HOSTNAME --format json | jq -r ".[] | select(.location[].dev == \"${dev#/dev/}\").daemons[]" | sed "s/osd.//g" | sort -u)
    local ids=$(ceph-volume raw list --format json | jq -r ".[] | select(.device | startswith(\"$dev\")).osd_id")
    ids+=$(ceph-volume lvm list --format json | jq -r ".[][] | select(.devices[] == \"$dev\").tags.\"ceph.osd_id\"")

    echo -n $ids
}

ceph_get_dev_by_id()
{
    local osd_id=${1#.osd}
    local dev=$(ceph-volume raw list --format json | jq -r ".[] | select(.osd_id == $osd_id).device")
    if echo $dev | grep -q '/dev/mapper' ; then
        dev=$(ceph-volume lvm list --format json | jq -r ".[][] | select(.tags.\"ceph.osd_id\" == \"$osd_id\").devices[]")
    fi
    echo -n $dev
}

ceph_get_sn_by_dev()
{
    local dev=$1
    local blkdevs=$(lsblk -J | jq -r .blockdevices[])
    while read blkdev ; do
        parent_dev=$(echo $blkdev | jq -r ". | select(.children[].name == \"${dev#/dev/}\").name" 2>/dev/null)
        if [ "x$parent_dev" != "x" ] ; then
            dev="/dev/$parent_dev"
            break
        fi
    done < <(echo $blkdevs | jq -c)
    local smart_flg="-i"
    local smart_log=$(smartctl $smart_flg $dev)

    if smartctl $smart_flg $dev | grep -q -i 'megaraid,N' ; then
        selected_dev=$(lshw -class disk -json 2>/dev/null | jq -r ".[] | select(.logicalname == \"${dev}\")")
        selected_dev_id=$(echo $selected_dev | jq -r .id | cut -d":" -f2)
        smart_flg+=" -d megaraid,${selected_dev_id}"
    fi
    local sn=$(smartctl $smart_flg $dev 2>/dev/null | grep -i "Serial number" | cut -d":" -f2 | xargs)
    [ "x$sn" != "x" ] || sn=$($CEPH device ls | grep "${HOSTNAME}:${dev#/dev/}" | awk '{print $1}')
    echo -n $sn
}

ceph_get_cache_by_backpool()
{
    local backpool=${1:-$BUILTIN_BACKPOOL}
    if [ "$backpool" = "$BUILTIN_BACKPOOL" ] ; then
        local cachepool=$BUILTIN_CACHEPOOL
    else
        local cachepool=${backpool%-pool}-cache
    fi

    echo -n $($CEPH osd pool ls | grep "^${cachepool}$")
}

ceph_get_pool_in_cacheable_backpool()
{
    local pool=${1:-NOSUCHPOOL}
    for p in $(ceph_cacheable_backpool_list) ; do
        if [ "$pool" = "$p" ] ; then
            echo $pool
            break
        fi
    done
}

ceph_cacheable_backpool_list()
{
    local cacheable_pools="$($CEPH osd pool ls | egrep -v "^${BUILTIN_CACHEPOOL}$|[.]rgw[.]|^cephfs_metadata$|^[.]mgr$|[-]cache$|^k8s-volumes$|^cephfs_data$|^rbd$|^glance-images$|^volume-backups$|^cinder-volumes-ssd$")"
    if [ "$VERBOSE" == "1" ] ; then
        for backpool in $cacheable_pools ; do
            if [ "$backpool" = "$BUILTIN_BACKPOOL" ] ; then
                cachepool=$BUILTIN_CACHEPOOL
            else
                cachepool=$($CEPH osd pool ls | grep "${backpool%-pool}-cache$")
            fi
            printf "%s%s\n" $backpool ${cachepool:+"/$cachepool"}
        done
    else
        for backpool in $cacheable_pools ; do
            printf "%s\n" $backpool
        done
    fi
}

ceph_backpool_cache_list()
{
    local cachepools="$($CEPH osd pool ls | egrep "$BUILTIN_CACHEPOOL|[-]cache$")"
    local backpool=${1:-$BUILTIN_BACKPOOL}

    for cachepool in $cachepools ; do
        if [ "$cachepool" = "$BUILTIN_CACHEPOOL" ] ; then
            backpool=$BUILTIN_BACKPOOL
        else
            backpool=$($CEPH osd pool ls | grep "${cachepool%-cache}-pool$")
            [ "x$backpool" != "x" ] || backpool=$($CEPH osd pool ls | grep "${cachepool%-cache}$")
        fi
        if [ "$VERBOSE" == "1" ] ; then
            [ "x$(ceph_osd_test_cache $backpool)" = "xoff" ] || printf "%s%s\n" $backpool ${cachepool:+"/$cachepool"}
        else
            [ "x$(ceph_osd_test_cache $backpool)" = "xoff" ] || printf "%s\n" $backpool
        fi
    done
}

ceph_mon_map_create()
{
    local conf=${1:-/etc/ceph/ceph.conf}
    if ! sudo -u ceph $CEPH -c $conf mon getmap -o $MAPFILE >/dev/null 2>&1 ; then
        if systemctl status ceph-mon@$HOSTNAME >/dev/null 2>&1 ; then
            Quiet -n systemctl stop ceph-mon@$HOSTNAME
            Quiet -n sudo -u ceph ceph-mon -i $HOSTNAME --extract-monmap $MAPFILE
            Quiet -n systemctl start ceph-mon@$HOSTNAME
        else
            Quiet -n sudo -u ceph ceph-mon -i $HOSTNAME --extract-monmap $MAPFILE
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
    timeout $SRVTO monmaptool --print $MAPFILE
}

ceph_crush_map_show()
{
    $CEPH osd getcrushmap -o $CRUSHMAPFILE
    crushtool -d $CRUSHMAPFILE -o $CRUSHMAPFILE.print
    cat $CRUSHMAPFILE.print
}

ceph_mon_store_renew()
{
    local mon_pth=/var/lib/ceph/mon/ceph-$HOSTNAME
    local store_pth=${mon_pth}/store.db
    MountOtherPartition
    if [ -e /mnt/target${store_pth}/CURRENT -a -e ${store_pth}/CURRENT ] ; then
        if [ /mnt/target${store_pth}/CURRENT -nt ${store_pth}/CURRENT ] ; then
            rm -rf ${store_pth}.bak
            mv ${store_pth} ${store_pth}.bak
            rsync -ar /mnt/target${store_pth} ${mon_pth}/
        elif [ /mnt/target${store_pth}/CURRENT -ot ${store_pth}/CURRENT ] ; then
            rm -rf /mnt/target${store_pth}.bak
            mv /mnt/target${store_pth} /mnt/target${store_pth}.bak
            rsync -ar ${store_pth} /mnt/target${mon_pth}/
        fi
    fi
    sync
    umount /mnt/target
}

ceph_mon_map_renew()
{
    local ip=$1
    local old_hostname=$2
    ceph_mon_map_create $3
    monmaptool --print $MAPFILE | egrep -q "$ip.*$HOSTNAME"
    if [ $? -eq 0 ] ; then
        echo "mon node exists"
    else
        if [ -n "$old_hostname" -a "$old_hostname" != "$HOSTNAME" ] ; then
            # hostname change
            sudo -u ceph monmaptool --rm $old_hostname $MAPFILE | grep monmaptool
        else
            # ip change
            sudo -u ceph monmaptool --rm $HOSTNAME $MAPFILE | grep monmaptool
        fi
        sudo -u ceph monmaptool --add $HOSTNAME $ip:6789 $MAPFILE | grep monmaptool
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
    for peer_entry in "${peer_array[@]}" ; do
        if [ -n "$peer_entry" ] ; then
            sudo -u ceph monmaptool --rm $peer_entry $MAPFILE | grep monmaptool
        fi
    done
    ceph_mon_map_inject
}

ceph_bootstrap_mon_ip()
{
    ceph_mon_map_create
    local ip=$(monmaptool --print $MAPFILE | grep $HOSTNAME | awk -F' ' '{print $2}' | awk -F':' '{print $1}' | tr -d '\n')
    if [ "$ip" == "[v2" -o "$ip" == "v1" ] ; then
        ip=$(monmaptool --print $MAPFILE | grep "6789.*$HOSTNAME" | awk -F':' '{print $3}' | tr -d '\n')
    fi
    echo -n $ip
}

ceph_mon_map_iplist()
{
    ceph_mon_map_create $1
    local iplist=$(monmaptool --print $MAPFILE | grep 6789 | awk -F' ' '{print $2}' | awk -F':' '{print $1}' | tr '\n' ',')
    if echo $iplist | grep -q '\[v2,' ; then
        iplist=$(monmaptool --print $MAPFILE | grep 6789 | awk '{print $2}' | tr '\n' ',')
    elif echo $iplist | grep -q 'v1' ; then
        iplist=$(monmaptool --print $MAPFILE | grep 6789 | awk -F' ' '{print $2}' | awk -F':' '{print $2}' | tr '\n' ',')
    fi
    echo -n ${iplist:-1}
}

ceph_mon_map_hosts()
{
    ceph_mon_map_create $1
    local hosts=$(monmaptool --print $MAPFILE | grep 6789 | awk -F' ' '{print $3}' | cut -c 5- | tr '\n' ',')
    echo -n ${hosts:-1}
}

ceph_mds_map_iplist()
{
    ceph_mon_map_create $1
    local iplist=$(monmaptool --print $MAPFILE | grep -v $HOSTNAME | grep 6789 | awk -F' ' '{print $2}' | awk -F':' '{print $1}' | tr '\n' ',')
    if echo $iplist | grep -q '\[v2,' ; then
        iplist=$(monmaptool --print $MAPFILE | grep -v $HOSTNAME | grep 6789 | awk '{print $2}' | tr '\n' ',')
    elif echo $iplist | grep -q 'v1' ; then
        iplist=$(monmaptool --print $MAPFILE | grep -v $HOSTNAME | grep 6789 | awk -F' ' '{print $2}' | awk -F':' '{print $2}' | tr '\n' ',')
    fi
    echo -n $iplist
}

ceph_mds_map_hosts()
{
    local monhosts=($(ceph_mon_map_hosts | tr ',' ' '))
    local mdshosts=
    for (( i=0 ; i<${#monhosts[@]} ; i++ )) ; do
        if [ "x$HOSTNAME" = "x${monhosts[$i]}" ] ; then
            continue
        else
            mdshosts+="${monhosts[$i]},"
        fi
    done
    echo -n ${mdshosts%,}
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
    if $($CEPH osd stat | grep -q noout) ; then
        echo "in maintenance mode"
    else
        echo "in production mode"
    fi
}

ceph_create_cachepool()
{
    local backpool=${1:-$BUILTIN_BACKPOOL}

    if [ "$backpool" = "$BUILTIN_BACKPOOL" ] ; then
        local cachepool=$BUILTIN_CACHEPOOL
    else
        local cachepool=${backpool%-pool}-cache
    fi
    local size=$($CEPH osd pool get $backpool size -f json | jq .size)
    local osnd=$($CEPH osd df $backpool | grep up | wc -l)
    local app=$($CEPH osd pool ls detail | grep $backpool | grep -o "application .*" | cut -d" " -f2)
    if [ $osnd -gt 100 -a $size -gt 2 ] ; then
        ((size --))
    fi

    ceph_create_pool $cachepool $app $size
    local pgs=$($CEPH osd pool get $backpool pg_num -f json | jq -r .pg_num)
    Quiet -n $CEPH osd pool set $cachepool pg_num $pgs  --yes-i-really-mean-it
    Quiet -n $CEPH osd pool set $cachepool pgp_num $pgs
}

ceph_create_pool()
{
    local volume=${1:-$BUILTIN_BACKPOOL}
    local app=${2:-rbd}
    local size=${3:-3}

    # pg number will update with cron job
    $CEPH osd pool create $volume 1 >/dev/null 2>&1 || true
    for i in {1..15} ; do
        if $CEPH osd pool ls | grep -q $volume ; then
            break
        else
            sleep 1
        fi
    done
    $CEPH osd pool set $volume size $size >/dev/null 2>&1 || true
    for i in {1..15} ; do
        if [ $($CEPH -s | grep creating -c) -gt 0 ] ; then
            sleep 1
        else
            break
        fi
    done
    Quiet -n $CEPH osd pool application enable $volume $app
}

ceph_create_ec_pool()
{
    local pool=$1
    local profile=$2

    Quiet -n $CEPH osd pool create $pool 1 1 erasure $profile
    Quiet -n $CEPH osd pool application enable $pool rgw
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 ; do
        if [ $($CEPH -s | grep creating -c) -gt 0 ] ; then
            sleep 1
        else
            break
        fi
    done
}

ceph_convert_to_ec_pool()
{
    local pool=$1
    local chunks=$2
    local parity=$3
    local ec_profile=$($CEPH osd pool get $pool erasure_code_profile 2>/dev/null | awk '{print $2}')
    local old_chunks=$(echo $ec_profile | awk -F'-' '{print $3}')
    local old_parity=$(echo $ec_profile | awk -F'-' '{print $4}')

    if [ "$old_chunks" != "$chunks" ] || [ "$old_parity" != "$parity" ] ; then
        local profile=ec-$(/usr/bin/uuid | fold -w 8 | head -n 1)-$chunks-$parity

        $CEPH osd erasure-code-profile set $profile k=$chunks m=$parity
        ceph_create_ec_pool $pool.new $profile
        rados cppool $pool $pool.new 2>/dev/null
        $CEPH osd pool rename $pool $pool.$profile.orig
        $CEPH osd pool rename $pool.new $pool
    fi
}

ceph_adjust_pool_size()
{
    local pool_name=$1
    local size=${2:-3}
    local min_size=$(expr $size - 1)
    local type=${3:-rf}

    if [[ "$pool_name" =~ "-pool" || "$pool_name" =~ "-cache" ]] ; then
        local bucket=$(echo $pool_name | sed -e 's/-pool$//' -e 's/-cache$//')
    else
        local bucket="default"
    fi

    local host_num=$($CEPH osd crush ls $bucket | sort | uniq | wc -l)

    if [ "$type" == "ec" ] ; then
        if [ "$(expr $size + $min_size)" -gt "$host_num" ] || [ "$size" -eq 1 ] ; then
            echo "can't set EC when there are no enough hosts, rollback to RF pool"
            type=rf
        fi
    fi

    if [ $min_size -eq 0 ] ; then
        min_size=1
    fi

    $CEPH config set global mon_allow_pool_size_one true
    case $type in
        rf)
            echo "set ceph pool $pool_name (size, min_size) to ($size, $min_size)"
            $CEPH osd pool set $pool_name size $size --yes-i-really-mean-it 2>/dev/null || true
            $CEPH osd pool set $pool_name min_size $min_size 2>/dev/null || true
            ;;
        ec)
            echo "set ceph ec pool $pool_name (chunks, parity) to ($size, $min_size)"
            ceph_convert_to_ec_pool $pool_name $size $min_size
            ;;
    esac
    $CEPH config set global mon_allow_pool_size_one false
    $CEPH config rm global mon_allow_pool_size_one
}

ceph_pool_replicate_init()
{
    local hosts=$($CEPH osd tree -f json | jq '[ .nodes[] | select(.type=="host") ] | length' 2>/dev/null)
    local size=1

    if [ -n "$hosts" ] ; then
        if [ $hosts -ge 3 ] ; then
            size=3
        else
            size=$hosts
        fi
    fi

    ceph_pool_replicate_set $size
}

ceph_pool_replicate_set()
{
    local size=${1:-3}
    local cachesize=
    [ $size -gt 1 ] && cachesize=2 || cachesize=1
    [ $size -gt 1 ] || $CEPH config set global mon_allow_pool_size_one true
    for P in $($CEPH osd pool ls) ; do
        case $P in
            default.rgw.buckets.data)
                ceph_adjust_pool_size $P $size ec
                ;;
            $BUILTIN_CACHEPOOL|$BUILTIN_EPHEMERAL|*-cache)
                ceph_adjust_pool_size $P $cachesize
                ;;
            *)
                ceph_adjust_pool_size $P $size
                ;;
        esac
    done
    [ $size -gt 1 ] || $CEPH config set global mon_allow_pool_size_one false
}

ceph_pool_autoscale_set()
{
    local state=$1

    for p in $($CEPH osd pool ls) ; do
        local mode=$($CEPH osd pool get $p pg_autoscale_mode | awk '{print $2}' | tr -d '\n')
        if [ "$mode" != "$state" ] ; then
            echo "set pool '$p' autoscale $state"
            Quiet -n $CEPH osd pool set $p pg_autoscale_mode $state
        fi
    done
}

ceph_adjust_pool_pg()
{
    local pool_name=$1
    local data_pct=$2
    local pg_osd=200
    local mode=$($CEPH osd pool get $pool_name pg_autoscale_mode | awk '{print $2}' | tr -d '\n')

    if [ "$mode" != "on" ] ; then
        local osd_num=$($CEPH osd stat | awk '{print $3}')
        local size=$($CEPH osd pool get $pool_name size -f json | jq .size)

        let pg=$(( ($pg_osd * $osd_num * $data_pct) / ($size * 1000) ))
        if [ $pg -eq 0 ] ; then
            pg=$osd_num
        fi

        local pg_p2=$(echo "x=l($PG)/l(2) ; scale=0 ; 2^((x+0.5)/1)" | bc -l)

        echo "set pool '$pool_name' pg number to $pg_p2"
        Quiet -n $CEPH osd pool set $pool_name pg_num $pg_p2 --yes-i-really-mean-it
        Quiet -n $CEPH osd pool set $pool_name pgp_num $pg_p2
    fi
}

ceph_adjust_cache_flush_bytes()
{
    [ "x$(ceph_osd_test_cache)" = "xon" ] || return 0

    for cp in $BUILTIN_CACHEPOOL $($CEPH osd pool ls | grep "[-]cache") ; do
        if $CEPH osd pool get $cp target_max_bytes >/dev/null 2>&1 ; then
            local cache_sz=$(ceph_osd_get_cache_size $cp)
            [ -n "$cache_sz" ] && Quiet -n $CEPH osd pool set $cp target_max_bytes $cache_sz
        fi
    done
    Quiet -n $CEPH health mute CACHE_POOL_NEAR_FULL
}

ceph_adjust_pgs()
{
    # reference: https://ceph.com/pgcalc/
    for p in $($CEPH osd pool ls) ; do
        case $p in
            # $BUILTIN_CACHEPOOL/userdef-cache 50%: 500
            # FIXME: what to do with variable no. of user-defined pools?
            $BUILTIN_CACHEPOOL|*-cache)
                ceph_adjust_pool_pg $p 100
                ;;
            $BUILTIN_BACKPOOL|*-pool)
                ceph_adjust_pool_pg $p 400
                ;;
            # others 35%: 350
            k8s-volumes|volume-backups|ephemeral-vms|glance-images)
                ceph_adjust_pool_pg $p 80
                ;;
            rbd)
                ceph_adjust_pool_pg $p 30
                ;;
            # others 5%: 50
            # adjust pg of data and metadata pools for ceph filesystem. Ratio should be 80:20
            # https://ceph.com/planet/cephfs-ideal-pg-ratio-between-metadata-and-data-pools/
            cephfs_data)
                ceph_adjust_pool_pg $p 40
                ;;
            cephfs_metadata)
                ceph_adjust_pool_pg $p 10
                ;;
            # rgw 10%: 100
            default.rgw.buckets.extra)
                ceph_adjust_pool_pg $p 8
                ;;
            default.rgw.buckets.index)
                ceph_adjust_pool_pg $p 16
                ;;
            default.rgw.buckets.data)
                ceph_adjust_pool_pg $p 64
                ;;
            *)
                ceph_adjust_pool_pg $p 1
                ;;
        esac
    done
    Quiet -n ceph_adjust_cache_flush_bytes
}

# params:
# $1: device name(e.g.: /dev/sdd)
ceph_osd_zap_disk()
{
    local dev=$1
    local lvm=$(ceph-volume lvm list --format json | jq -r ".[][] | select(.devices[] == \"$dev\").lv_path")
    if [ -e ${lvm:-NOSUCHLVM} ] ; then
        Quiet ceph-volume lvm zap $lvm --destroy
        Quiet dmsetup remove $lvm 2>/dev/null
    else
        Quiet timeout $SRVTO wipefs -a $dev 2>/dev/null
        Quiet timeout $SRVTO sgdisk -Z $dev 2>/dev/null
        Quiet ceph-volume lvm zap $dev --destroy
    fi
}

# list osd-typed disks (mounted)
ceph_osd_list_disk()
{
    local all_devs=
    local blkdevs=$(lsblk -J | jq -r .blockdevices[])
    # local raw_devs=$($CEPH device ls-by-host $HOSTNAME --format json | jq -r ".[] | select(.daemons[] | startswith(\"osd\")).location[].dev" | sort -u | xargs -i echo /dev/{})
    local raw_devs=$(ceph-volume raw list --format json | jq -r ".[] | select(.device | startswith(\"/dev/\")).device" | grep -v "/dev/mapper" | sort -u)
    for DEV in $raw_devs ; do
        parent_dev=/dev/$(echo $blkdevs | jq -r ". | select(.children[].name == \"${DEV#/dev/}\").name" 2>/dev/null)
        all_devs+="\n${parent_dev}"
    done
    local lvm_devs=$(ceph-volume lvm list --format json | jq -r ".[][].devices[]")
    [ -z "$lvm_devs" ] || all_devs+="\n$lvm_devs"
    all_devs=$(echo -e "$all_devs" | sort -u)
    echo "$all_devs" | tr "\n" " " | sed -e "s/^ //" -e "s/ $//"
}

# list osd meta partitions (umount)
ceph_osd_list_meta_partitions()
{
    local metaparts=$(blkid | grep -e 'PARTLABEL=\"cube_meta' | sort | cut -d":" -f1)

    echo -n $metaparts
}

# list osd-typed partitions
# (i.e.: typecode: 4fbd7e29-9d25-41b8-afd0-062c0ceff05d)
ceph_osd_list_partitions()
{
    local nvme_devs=$(blkid | grep -e 'PARTLABEL=\"cube_meta' | grep -oe '^/dev/nvme[0-9]\+n[0-9]\+p[0-9]\+' | sort | uniq)
    [ -z "$nvme_devs" ] || nvme_devs=$(readlink -e $nvme_devs)
    echo -n $nvme_devs
    if [ -n "$nvme_devs" ] ; then
        echo -n " "
    fi
    local scsi_devs=$(blkid | grep -e 'PARTLABEL=\"cube_meta' | grep -oe '^/dev/sd[a-z]\+[0-9]\+' | sort | uniq)
    [ -z "$scsi_devs" ] || scsi_devs=$(readlink -e $scsi_devs)
    echo -n $scsi_devs
}

# params:
# $1: device name(e.g.: /dev/sdd)
# $2: nums of meta partitions
# $3: size of meta partition (unit: sectors)
ceph_osd_prepare_bluestore()
{
    local typecode_data="4fbd7e29-9d25-41b8-afd0-062c0ceff05d"
    local typecode_block="cafecafe-9b03-4f30-b4c6-b4b80ceff106"
    local dev=$1
    local part_num=$2
    local part_size=$3
    local type=$4
    local part_symbol=
    local part_dev=

    # a. error handling
    [ -n "$dev" ] || return 1
    [[ "$part_num" =~ ^[0-9]+$ ]] || part_num=1
    [[ "$part_size" =~ ^[0-9]+$ ]] || part_size=409600

    # b. zap and partition osd data device
    Quiet ceph_osd_zap_disk $dev
    i=1
    part_size=$(( $part_size / 2048))

    if [ "$type" == "scsi" ] ; then
        part_symbol=${dev/\/dev\/sd/}
        part_dev="$dev"
    elif [ "$type" == "nvme" ] ; then
        part_symbol=${dev/\/dev\/nvme/}
        part_dev="${dev}p"
    fi

    for (( ; i<=$part_num ; i++ )) ; do
        Quiet sgdisk -n $i:0:+${part_size}M -c $i:"cube_meta_"$part_symbol"_"$i -u 1:$(uuidgen) --mbrtogpt -- $dev
        partprobe $part_dev$i 2>/dev/null || true
        # zero-out 100mb for each partition
        dd if=/dev/zero of=${part_dev}${i} bs=1M count=100 oflag=sync
        Quiet mkfs.xfs -f ${part_dev}${i}
    done
    # c. partition osd block device
    free_size=$(GetFreeSectorsByDisk $dev)
    log_sec=$(lsblk -t -J $dev | jq -r .blockdevices[].\"log-sec\")
    multiplier=$(( $log_sec / 512 ))
    part_size=$(( $free_size / $part_num / 2048 * ${multiplier:-1} ))
    part_num=$(( $part_num * 2 ))
    for (( ; i<=$part_num ; i++ )) ; do
        Quiet sgdisk -n $i:0:+${part_size}M -c $i:"cube_data_"$part_symbol"_"$i -u 1:$(uuidgen) --mbrtogpt -- $dev
        partprobe $part_dev$i 2>/dev/null || true
        # zero-out 100mb for each partition
        dd if=/dev/zero of=${part_dev}${i} bs=1M count=100 oflag=sync
    done
}

ceph_osd_down_list()
{
    if [ "$VERBOSE" == "1" ] ; then
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
    local devs="$*"
    for dev in $devs ; do
        [ -n "$(readlink -e $dev)" ] || continue
        Quiet timeout $SRVTO wipefs -a $dev 2>/dev/null
        if ceph-volume inventory $dev | grep -q -i "available.*true" ; then
            Quiet -n ceph-volume lvm create --bluestore --data $dev
        else
            Quiet -n ceph-volume inventory $dev
        fi
    done
    Quiet -n ceph-volume lvm activate --bluestore --all
    Quiet -n ceph_adjust_cache_flush_bytes
}

# prepare free disks and make them lvm LUKS encrypted OSDs
# !!!USE WITH CAUTIONS!!!
ceph_osd_add_disk_encrypt()
{
    local devs="$*"
    for dev in $devs ; do
        [ -n "$(readlink -e $dev)" ] || continue
        Quiet timeout $SRVTO wipefs -a $dev 2>/dev/null
        if ceph-volume inventory $dev | grep -q -i "available.*true" ; then
            Quiet -n ceph-volume lvm create --dmcrypt --bluestore --data $dev
        else
            Quiet -n ceph-volume inventory $dev
        fi
    done
    Quiet -n ceph-volume lvm activate --bluestore --all
    Quiet -n ceph_adjust_cache_flush_bytes
}

# prepare free disks and make them raw OSDs
# !!!USE WITH CAUTIONS!!!
ceph_osd_add_disk_raw()
{
    local devs="$*"
    for dev in $devs ; do
        [ -n "$(readlink -e $dev)" ] || continue
        PrepareDataDisk $dev
    done
    Quiet -n $HEX_CFG refresh_ceph_osd
    Quiet -n ceph_adjust_cache_flush_bytes
}

# remove an existing OSD
# !!!USE WITH CAUTIONS!!!
ceph_osd_remove_disk()
{
    local dev=$1
    local mode=${2:-safe}
    [ -n "$(readlink -e $dev)" ] || Error "no such device $dev"
    ceph_osd_list_disk 2>/dev/null | grep -q $dev || Error "no such OSD disk $dev"
    [[ "$($CEPH -s -f json | jq -r .health.status)" == "HEALTH_OK" || "$mode" == "force" ]] || Error "ceph health has to be OK to proceed disk removals"

    local part_num=$(( $(ListNumOfPartitions $dev) / 2 ))
    if [ $part_num -gt 0 ] ; then
        local part_enum="$(seq 1 $part_num)"
    else
        local part_enum=$part_num
    fi
    local disk_removable=true
    for i in $part_enum ; do
        osd_id=
        if [ $i -eq 0 ] ; then
            osd_id=$(ceph_osd_get_id ${dev})
        else
            if [[ "$dev" =~ nvme.n. ]] ; then
                osd_id=$(ceph_osd_get_id ${dev}p${i})
            elif [[ "$dev" =~ nvme ]] ; then
                osd_id=$(ceph_osd_get_id ${dev}n1p${i})
            else
                osd_id=$(ceph_osd_get_id ${dev}${i})
            fi
        fi
        ceph_osd_remove $osd_id $mode 2>/dev/null || disk_removable=false
        # For raw osd disk, modify PARTLABEL to exclude disk in next hex_config refresh_ceph_osd
        # Quiet parted $dev name $i removed
    done
    if [ "$disk_removable" = "true" ] ; then
        Quiet ceph_osd_zap_disk $dev
        Quiet ceph_osd_create_map
        Quiet ceph_adjust_cache_flush_bytes
    fi
}

ceph_osd_remove()
{
    local osd_id=${1#osd.}
    local mode=${2:-safe}
    local host=$(ceph_get_host_by_id $osd_id)

    $CEPH osd df osd.$osd_id
    timeout 600 ceph tell osd.$osd_id compact >/dev/null 2>&1 || true
    local crush_weight=$($CEPH osd tree -f json | jq -r ".[][] | select(.name == \"osd.${osd_id}\").crush_weight")
    Quiet $CEPH osd crush reweight osd.$osd_id 0
    Quiet $CEPH osd out $osd_id
    if [ "x$mode" = "xsafe" ] ; then
        sleep 10
        local cnt=0
        local max=30
        local pgs_log=$(mktemp -u /tmp/remove_osd.1.XXX)
        local why_quitting=
        while ! $CEPH osd safe-to-destroy osd.$osd_id >$pgs_log 2>&1 ; do
            tail -1 $pgs_log | sed "s/Error EBUSY: //"
            ((cnt++))
            sleep 60
            if [ $cnt -gt $max ] ; then
                why_quitting="timed out moving data from disk"
            elif [ "x$($CEPH -s -f json | jq -r .health.status)" = "xHEALTH_ERR" ] ; then
                [ $cnt -lt 3 ] || why_quitting="ceph would be in error state without this disk"
            elif [ "x$($CEPH osd safe-to-destroy osd.$osd_id 2>&1 | egrep -o '[0-9]+ pgs')" == "x$(egrep -o '[0-9]+ pgs' $pgs_log)" ] ; then
                [ $cnt -lt 3 ] || why_quitting="pgs could not be moved likely due to too few disks or little space in the failure domain"
            fi
            if [ "x$why_quitting" != "x" ] ; then
                systemctl restart ceph-osd@$osd_id
                Quiet $CEPH osd crush reweight osd.$osd_id $crush_weight
                Quiet $CEPH osd in $osd_id
                echo "Restored ${dev}: osd.$osd_id as $why_quitting." && exit 1
            fi
        done
        rm -f $pgs_log
        $CEPH osd down $osd_id
    fi

    Quiet -n remote_run $host "systemctl stop ceph-osd@$osd_id"
    Quiet -n $CEPH osd purge $osd_id --force
    Quiet -n remote_run $host ceph-volume lvm deactivate $osd_id
    Quiet -n remote_run $host umount -l /var/lib/ceph/osd/ceph-$osd_id
    Quiet -n remote_run $host rmdir /var/lib/ceph/osd/ceph-$osd_id
    remote_run $host "[ ! -e /var/lib/ceph/osd/ceph-$osd_id ]" || return 1
}

ceph_osd_host_remove()
{
    local host=$1

    for osd in $($CEPH osd tree -f json | jq -r '.nodes[] | select(.name == "$host").children[]') ; do
        Quiet -n ceph_osd_remove $osd
    done
    Quiet -n $CEPH osd crush rm $host
}

ceph_osd_get_cache_size()
{
    local cachepool=${1:-$BUILTIN_CACHEPOOL}
    local rf=$($CEPH osd pool get $cachepool size | awk '{print $2}')
    local result=0
    # add each size into result (e.g.: 8.31,TiB 865,GiB)
    for sz in $($CEPH osd df $cachepool | grep " ssd " | awk '{print $5","$6}') ; do
        local N=$(echo $sz | awk -F',' '{print $1}')
        local U=$(echo $sz | awk -F',' '{print $2}')
        case "$U" in
            "PiB") result=$(bc <<< "$result+$N*1024*1024*1024*1024*1024") ;;
            "TiB") result=$(bc <<< "$result+$N*1024*1024*1024*1024") ;;
            "GiB") result=$(bc <<< "$result+$N*1024*1024*1024") ;;
            "MiB") result=$(bc <<< "$result+$N*1024*1024") ;;
            "KiB") result=$(bc <<< "$result+$N*1024") ;;
            ?) return 2
        esac
    done
    # cut-off 10% just in case ceph over-report the size
    result=$(bc <<< "$result/$rf*0.9")
    result=$(echo $result | grep -oe '^[0-9]\+')
    # returned result has to be prorated by configured burst rate
    local CACHE_FULL_RATIO=$($CEPH osd pool get $cachepool cache_target_full_ratio -f json 2>/dev/null | jq -r .cache_target_full_ratio)
    result=$(bc <<< "$result * ${CACHE_FULL_RATIO:-1} / 1")

    echo -n $result
}

# check if cache of backPool is on or off
# $1 - backPool name (e.g.: $BUILTIN_BACKPOOL)
ceph_osd_test_cache()
{
    local cachepool=$(ceph_get_cache_by_backpool $1)

    if [ -z "$cachepool" ] ; then
        echo "No cache associated with backpool: $1" && return 1
    else
        $CEPH osd pool get $cachepool hit_set_type &>/dev/null && echo -n "on" || echo -n "off"
    fi
}

# params:
# $1 - disk name (e.g.: /dev/sdb)
# $2 - rule name (e.g.: ssd)
# $3 - cache pool name (e.g.: $BUILTIN_CACHEPOOL or userdef-cache)
ceph_osd_promote_disk()
{
    local dev=$1
    local rule=${2:-ssd}
    local cachepool=${3:-$BUILTIN_CACHEPOOL}
    # check
    [ -n "$dev" ] || return 1
    [ "x$(ceph_osd_get_class $dev)" != "x$rule" ] || return 0
    [ "$($CEPH -s -f json | jq -r .health.status)" = "HEALTH_OK" ] || Error "ceph health has to be OK to proceed disk promotion"
    [ "x$($CEPH -s -f json | jq -r .pgmap.recovering_objects_per_sec)" = "xnull" ] || Error "cannot promote disk while ceph is recovering"
    local osd_list=$(for i in $($HEX_SDK ceph_get_ids_by_dev $dev) ; do echo osd.$i ; done)
    Quiet -n $CEPH osd out $osd_list
    # move osd to $rule
    Quiet -n $CEPH osd crush rm-device-class $osd_list
    Quiet -n $CEPH osd crush set-device-class $rule $osd_list

    for i in {1..60} ; do
        sleep 10
        recovering=$($CEPH -s -f json | jq -r .pgmap.recovering_objects_per_sec)
        if [ "x$recovering" = "xnull" ] ; then
            sleep 5
            recovering_CONFIRM=$($CEPH -s -f json | jq -r .pgmap.recovering_objects_per_sec)
            if [ "x$recovering_CONFIRM" = "xnull" ] ; then
                $CEPH osd in $osd_list
                Quiet -n ceph_adjust_cache_flush_bytes
                break
            fi
        else
            echo "recovering $recovering obj/sec"
        fi
    done
}

# params:
# $1 - disk name (e.g.: /dev/sdb)
# $2 - rule name (e.g.: hdd)
ceph_osd_demote_disk()
{
    local dev=$1
    local rule=${2:-hdd}
    # check
    [ -n "$dev" ] || return 1
    [ "x$(ceph_osd_get_class $dev)" != "x$rule" ] || return 0
    [ "$($CEPH -s -f json | jq -r .health.status)" = "HEALTH_OK" ] || Error "ceph health has to be OK to proceed disk demotion"
    [ "x$($CEPH -s -f json | jq -r .pgmap.recovering_objects_per_sec)" = "xnull" ] || Error "cannot demote disk while ceph is recovering"
    local osd_list=$(for i in $($HEX_SDK ceph_get_ids_by_dev $dev) ; do echo osd.$i ; done)
    local old_rule=$(ceph_osd_get_class $dev)
    local nums=$($CEPH osd crush class ls-osd $old_rule | wc -l)
    # MUST leave at least 1 disk in cache
    if [ "$(ceph_osd_test_cache)" == "on" ] ; then
        [ $nums -gt 2 ] || return 1
    fi
    Quiet -n $CEPH osd out $osd_list
    # move osd to new $rule
    Quiet -n $CEPH osd crush rm-device-class $osd_list
    Quiet -n $CEPH osd crush set-device-class $rule $osd_list

    for i in {1..60} ; do
        sleep 10
        recovering=$($CEPH -s -f json | jq -r .pgmap.recovering_objects_per_sec)
        if [ "x$recovering" = "xnull" ] ; then
            sleep 5
            recovering_CONFIRM=$($CEPH -s -f json | jq -r .pgmap.recovering_objects_per_sec)
            if [ "x$recovering_CONFIRM" = "xnull" ] ; then
                $CEPH osd in $osd_list
                Quiet -n ceph_adjust_cache_flush_bytes
                break
            fi
        else
            echo "recovering $recovering obj/sec"
        fi
    done
}

# params:
# $1 - backPool
# $2 - mode
ceph_osd_set_cache_mode()
{
    local cachepool=$(ceph_get_cache_by_backpool $1)
    if [ -z "$cachepool" ] ; then
        echo "Error: no cache associated with backpool: $1"
        ceph_backpool_cache_list
        return 1
    fi
    local mode=$2

    if [ $# -lt 2 ] ; then
        echo "Usage: $0 backPool Mode" && return 1
    fi

    if [ "$cachepool" = "$BUILTIN_CACHEPOOL" ] || ($CEPH osd pool ls | grep "[-]cache" | grep -q $cachepool) ; then
        Quiet -n $CEPH osd tier cache-mode $cachepool $mode --yes-i-really-mean-it
    else
        echo "$cachepool is not a recognized cache pool" && return 1
    fi
}

# $1 - backPool name (e.g.: $BUILTIN_BACKPOOL)
ceph_osd_cache_flush()
{
    local cachepool=$(ceph_get_cache_by_backpool $1)
    if [ -z "$cachepool" ] ; then
        echo "Error: no cache associated with backpool: $1"
        Quiet -n ceph_backpool_cache_list
        return 1
    fi

    rados -p $cachepool cache-try-flush-evict-all
}

# $1 - backPool name (e.g.: $BUILTIN_BACKPOOL)
ceph_osd_cache_profile_get()
{
    local cachepool=$(ceph_get_cache_by_backpool $1)
    if [ -z "$cachepool" ] ; then
        echo "Error: no cache associated with backpool: $1"
        Quiet -n ceph_backpool_cache_list
        return 1
    fi

    local ratio=$($CEPH osd pool get $cachepool cache_target_full_ratio -f json 2>/dev/null | jq .cache_target_full_ratio_micro)
    if [ "$ratio" = "300000" ] ; then
        echo 'high-burst'
    elif [ "$ratio" = "600000" ] ; then
        echo 'default'
    elif [ "$ratio" = "800000" ] ; then
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
    local cachepool=$(ceph_get_cache_by_backpool $1)
    if [ -z "$cachepool" ] ; then
        echo "Error: no cache associated with backpool: $1"
        ceph_backpool_cache_list
        return 1
    fi
    local profile=$2

    if [ "$profile" = "high-burst" ] ; then
        Quiet -n $CEPH osd pool set $cachepool cache_target_dirty_ratio .1
        Quiet -n $CEPH osd pool set $cachepool cache_target_dirty_high_ratio .2
        Quiet -n $CEPH osd pool set $cachepool cache_target_full_ratio .3
    elif [ "$profile" = "default" ] ; then
        Quiet -n $CEPH osd pool set $cachepool cache_target_dirty_ratio .2
        Quiet -n $CEPH osd pool set $cachepool cache_target_dirty_high_ratio .4
        Quiet -n $CEPH osd pool set $cachepool cache_target_full_ratio .6
    elif [ "$profile" = "low-burst" ] ; then
        Quiet -n $CEPH osd pool set $cachepool cache_target_dirty_ratio .4
        Quiet -n $CEPH osd pool set $cachepool cache_target_dirty_high_ratio .6
        Quiet -n $CEPH osd pool set $cachepool cache_target_full_ratio .8
    else
        echo "Error: $profile is not one of the valid settings, high-burst, default or low-burst"
    fi
    Quiet -n ceph_adjust_cache_flush_bytes
}

# $1 - pool name (e.g.: $BUILTIN_BACKPOOL)
ceph_osd_enable_cache()
{
    local backpool=${1:-$BUILTIN_BACKPOOL}
    local cachepool=$(ceph_get_cache_by_backpool $backpool)
    if [ -z "$cachepool" ] ; then
        echo "Error: no cache associated with backpool: $1"
        Quiet -n ceph_backpool_cache_list
        return 1
    fi

    # associate backdev, ceph osd tier add {cold} {hot}
    if ! $CEPH osd tier add $backpool $cachepool ; then
        # failed to add tier pool, recreate it
        Quiet -n ceph_recreate_cache_pool $backpool
        Quiet -n $CEPH osd tier add $backpool $cachepool
    fi
    Quiet -n $CEPH osd tier set-overlay $backpool $cachepool
    # set cache mode, ceph osd tier cache-mode ${hot} ${mode}
    Quiet -n $CEPH osd tier cache-mode $cachepool readproxy
    Quiet -n $CEPH osd pool set $cachepool hit_set_type bloom
    Quiet -n $CEPH osd pool set $cachepool hit_set_period 28800
    # set cache size

    Quiet -n $CEPH osd pool set $cachepool cache_min_flush_age 600
    Quiet -n $CEPH osd pool set $cachepool cache_min_evict_age 43200
    Quiet -n ceph_osd_cache_profile_set $backpool default
    Quiet -n ceph_adjust_cache_flush_bytes
}

ceph_osd_disable_cache()
{
    local backpool=${1:-$BUILTIN_BACKPOOL}
    local cachepool=$(ceph_get_cache_by_backpool $backpool)
    if [ -z "$cachepool" ] ; then
        echo "Error: no cache associated with backpool: $1"
        Quiet -n ceph_backpool_cache_list
        return 1
    fi

    if echo "$backpool" | grep -q "[-]pool$" ; then
        local bucket=${backpool%-pool}
        local rule=$bucket
        local rule_ssd=${bucket}-ssd
        local rule_hdd=${bucket}-hdd
    else
        if [ "$cachepool" = "$BUILTIN_CACHEPOOL" ] ; then
            local fsmetapool="cephfs_metadata"
        fi
        local bucket=default
        local rule=replicated_rule
        local rule_ssd=rule-ssd
        local rule_hdd=rule-hdd
    fi

    $CEPH osd pool ls | grep -q "^${backpool}$" || exit 1
    $CEPH osd pool ls | grep -q "^${cachepool}$" || exit 1
    [ "x$(ceph_osd_test_cache $backpool)" = "xon" ] || exit 1

    # set to forward so no more dirty objects
    rados -p $cachepool cache-flush-evict-all &>/dev/null || true
    Quiet -n $CEPH osd tier cache-mode $cachepool none --yes-i-really-mean-it
    # flush cache
    # It's ok to have dirty objects when cache-mode is readproxy, which
    # makes possible no downtime while switching on/off cache
    rados -p $cachepool cache-flush-evict-all &>/dev/null || true
    # de-couple hot/cold devices
    Quiet -n $CEPH osd tier remove-overlay $backpool
    Quiet -n $CEPH osd tier remove $backpool $cachepool

    if [ "$backpool" = "$BUILTIN_BACKPOOL" ] ; then
        for p in $($CEPH osd pool ls) ; do
            case $p in
                *-pool|*-cache|*-ssd)
                    continue
                    ;;
                *)
                    if ! $CEPH osd pool get $p erasure_code_profile >/dev/null 2>&1 ; then
                        if [ "x$(ceph_osd_test_cache $p)" != "xon" ] ; then
                            $CEPH osd pool get $p crush_rule | grep -q replicated_rule || $CEPH osd pool set $p crush_rule $rule
                        fi
                    fi
                    ;;
            esac
        done
    elif echo "$backpool" | grep -q "[-]pool$" ; then
        Quiet -n $CEPH osd pool set $backpool crush_rule $rule
        Quiet -n $CEPH osd pool set $cachepool crush_rule $rule
    else
        if [ "x$(ceph_osd_test_cache $BUILTIN_BACKPOOL)" = "xon" ] ; then
            Quiet -n $CEPH osd pool set $backpool crush_rule $rule_hdd
        else
            Quiet -n $CEPH osd pool set $backpool crush_rule $rule
        fi
        Quiet -n $CEPH osd pool set $cachepool crush_rule $rule
    fi
    # Don't remove rule-ssd because it could be used by cinder-volumes-ssd pool
    # Don't remove rule-hdd because it could be used by other cache pools
}

# $1 - pool name (e.g.: $BUILTIN_BACKPOOL)
ceph_osd_create_cache()
{
    local backpool=${1:-$BUILTIN_BACKPOOL}
    local cachepool=$(ceph_get_cache_by_backpool $1)
    if [ -z "$cachepool" ] ; then
        echo "Error: no cache associated with backpool: $1"
        Quiet -n ceph_backpool_cache_list
        return 1
    fi

    if echo "$backpool" | grep -q "[-]pool$" ; then
        local bucket=${backpool%-pool}
        local rule=$bucket
        local rule_ssd=${bucket}-ssd
        local rule_hdd=${bucket}-hdd
    else
        if [ "$cachepool" = "$BUILTIN_CACHEPOOL" ] ; then
            local fsmetapool="cephfs_metadata"
        fi
        local bucket=default
        local rule=replicated_rule
        local rule_ssd=rule-ssd
        local rule_hdd=rule-hdd
    fi

    Quiet -n ceph_osd_enable_cache $backpool

    if ! ($CEPH osd crush rule list | grep -q $rule_ssd) ; then
        # create $rule
        Quiet -n $CEPH osd crush rule create-replicated $rule_ssd $bucket host ssd
    fi
    if ! ($CEPH osd crush rule list | grep -q $rule_hdd) ; then
        # create $rule
        Quiet -n $CEPH osd crush rule create-replicated $rule_hdd $bucket host hdd
    fi
    if ! ($CEPH osd pool get $cachepool crush_rule | grep -q $rule_ssd) ; then
        # set ${hot} rule for cache tier
        Quiet -n $CEPH osd pool set $cachepool crush_rule $rule_ssd
    fi
    if [ "$backpool" = "$BUILTIN_BACKPOOL" ] ; then
        if ! ($CEPH osd pool get $fsmetapool crush_rule | grep -q $rule_ssd) ; then
            # set ${hot} rule for cache tier
            Quiet -n $CEPH osd pool set $fsmetapool crush_rule $rule_ssd
        fi
        for p in $($CEPH osd pool ls) ; do
            case $p in
                $BUILTIN_CACHEPOOL|cephfs_metadata)
                    continue
                    ;;
                *-pool|*-cache|*-ssd)
                    continue
                    ;;
                *)
                    if ! $CEPH osd pool get $p erasure_code_profile >/dev/null 2>&1 ; then
                        if ! ($CEPH osd pool get $p crush_rule | grep -q $rule_hdd) ; then
                            Quiet -n $CEPH osd pool set $p crush_rule $rule_hdd
                        fi
                    fi
                    ;;
            esac
        done
    else
        Quiet -n $CEPH osd pool set $backpool crush_rule $rule_hdd
    fi
}

# $1 - backpool name (e.g.: $BUILTIN_BACKPOOL)
ceph_recreate_cache_pool()
{
    local backpool=${1:-$BUILTIN_BACKPOOL}
    local cachepool=$(ceph_get_cache_by_backpool $backpool)
    if [ -z "$cachepool" ] ; then
        echo "Error: no cache associated with backpool: $backpool"
        Quiet -n ceph_backpool_cache_list
        return 1
    fi
    local size=$($CEPH osd pool get $cachepool size | awk '{print $2}' | tr -d '\n')

    Quiet -n $CEPH osd pool delete $cachepool $cachepool --yes-i-really-really-mean-it
    Quiet -n ceph_create_pool $cachepool rbd
    Quiet -n ceph_adjust_pool_size "$cachepool" $size
    local pgs=$($CEPH osd pool get $backpool pg_num -f json | jq -r .pg_num)
    Quiet -n $CEPH osd pool set $cachepool pg_num $pgs  --yes-i-really-mean-it
    Quiet -n $CEPH osd pool set $cachepool pgp_num $pgs
}

# $1: pool name
# $2: peer name
ceph_mirror_pool_peer_set()
{
    local pool=$1
    local peer=$2

    if ! rbd mirror pool info $pool --format json | jq -r .peers[].site_name 2>/dev/null | grep -q $peer ; then
        Quiet -n rbd mirror pool peer add $pool $peer
    fi
}

# params:
# $1: mirror mode
# $2: image id(s)
ceph_mirror_image_enable()
{
    local mode=journal
    local interval=15m
    if [ "$1" = "snapshot" -o "$1" = "journal" ] ; then
        mode=$1
        shift
        if [ "$mode" = "snapshot" ] ; then
            interval=$1
            shift
        fi
    fi

    local vols=$($OPENSTACK volume list --all-projects -f json)
    for i in $* ; do
        local img_id=${i#volume-}
        local img_name=volume-${img_id}
        if rbd info $BUILTIN_BACKPOOL/$img_name >/dev/null 2>&1 ; then
            local img_info=$(rbd info $BUILTIN_BACKPOOL/${img_name} --format json 2>/dev/null)
            local enabled=$(echo $img_info | jq -r '.mirroring.state')
            local sshcmd="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
            local peer_vip=$(find /etc/ceph/ -type f -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//" | cut -d"-" -f2)


            if [ "$enabled" != "enabled" ] ; then
                local parent_pool=$(echo $img_info | jq -r '.parent.pool')
                local parent_img=$(echo $img_info | jq -r '.parent.image')
                if [ "$parent_img" != "null" ] ; then
                    local p_info=$(rbd info $parent_pool/$parent_img --format json 2>/dev/null)
                    local p_enabled=$(echo $p_info | jq -r '.mirroring.state')
                    if [ "$p_enabled" != "enabled" ] ; then
                        Quiet -n rbd mirror image enable $parent_pool/$parent_img $mode
                    fi
                fi
                Quiet -n $sshcmd root@$peer_vip "rbd remove $BUILTIN_BACKPOOL/${img_name}"
                if rbd mirror image enable $BUILTIN_BACKPOOL/${img_name} $mode >/dev/null 2>&1 ; then
                    printf "%60s enabled in $mode mode\n" $BUILTIN_BACKPOOL/${img_name}
                    Quiet -n $HEX_SDK os_volume_meta_sync $peer_vip NEEDNOPASS $img_id
                    if [ "$mode" = "snapshot" ] ; then
                        Quiet -n rbd mirror snapshot schedule remove --pool $BUILTIN_BACKPOOL --image $img_name
                        Quiet -n rbd mirror snapshot schedule add --pool $BUILTIN_BACKPOOL --image $img_name $interval
                        Quiet -n $sshcmd root@$peer_vip "rbd mirror snapshot schedule remove --pool $BUILTIN_BACKPOOL --image $img_name"
                        Quiet -n $sshcmd root@$peer_vip "rbd mirror snapshot schedule add --pool $BUILTIN_BACKPOOL --image $img_name $interval"
                    fi

                    local server_id=$(echo $vols | jq -r ".[] | select(.ID == \"${img_id}\").\"Attached to\"[].server_id")
                    if [ "x${server_id}" != "x" ] ; then
                        local server_info=$($OPENSTACK server show ${server_id:-EMPTYSERVERID} --format json)
                        local proj_id=$(echo "$server_info" | jq -r .project_id)
                        local proj=$($OPENSTACK project list -f value | grep "$proj_id " | awk '{print $2}')
                        server_info=$(echo "$server_info" | jq -r | sed "s/\"project_id\": .*/\"project_name\": \"$proj\",/")
                        local mirror_dir=/var/lib/ceph/rbd-mirror
                        local server_file=$mirror_dir/$(echo $server_info | jq -r .name)
                        mkdir -p $mirror_dir ; echo "$server_info" > $server_file
                        Quiet -n cubectl node rsync -r control $server_file
                        echo "$server_info" | $sshcmd root@$peer_vip "mkdir -p $mirror_dir ; cat - > $server_file" 2>/dev/null
                        Quiet -n $sshcmd root@$peer_vip "cubectl node rsync -r control $server_file"
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
            if [ "$(rbd info $BUILTIN_BACKPOOL/$img_name --format json | jq -r .mirroring.primary)" = "true" ] ; then
                echo "$BUILTIN_BACKPOOL/${img_name}"
                Quiet -n rbd mirror image disable $BUILTIN_BACKPOOL/$img_name --force
                local peer_vip=$(find /etc/ceph/ -type f -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//" | cut -d"-" -f2)
                Quiet -n $sshcmd root@$peer_vip "$HEX_SDK ceph_mirror_image_meta_remove $img_id"
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
    local vol=$($OPENSTACK volume show $img_id -f json)

    Quiet -n rbd mirror image disable $BUILTIN_BACKPOOL/volume-$img_id --force
    echo $vol | jq -r ".attachments[].server_id" | xargs -i $OPENSTACK server stop {} 2>/dev/null || true
    echo $vol | jq -r ".attachments[].server_id" | xargs -i $OPENSTACK server delete {} 2>/dev/null || true
    Quiet -n $OPENSTACK volume delete $img_id
}

ceph_mirror_avail_volume_list()
{
    if [ "$VERBOSE" == "1" ] ; then
        local FLAG="-v"
    fi

    local vols=$($HEX_SDK $FLAG os_list_volume_by_tenant_basic)
    for img_name in $(rbd mirror pool status $BUILTIN_BACKPOOL --verbose --format json | jq -r .images[].name 2>/dev/null) ; do
        vols=$(echo "$vols" | grep -v ${img_name#volume-})
    done
    [ -z "$vols" ] || echo "$vols"
}

ceph_mirror_added_volume_list()
{
    if [ "$VERBOSE" == "1" ] ; then
        local flag="-v"
    fi

    local vols=$(HEX_SDK $flag os_list_volume_by_tenant_basic)
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
    if [ "$2" = "promoted" ] ; then
        images=$(rbd mirror pool status $pool --verbose --format json | jq -r ".images[] | select(.description == \"local image is primary\").name" 2>/dev/null)
    elif [ "$2" = "demoted" ] ; then
        images=$(rbd mirror pool status $pool --verbose --format json | jq -r ".images[] | select(.description != \"local image is primary\").name" 2>/dev/null)
    else
        images=$(rbd mirror pool status $pool --verbose --format json | jq -r .images[].name 2>/dev/null)
    fi

    for img_name in $images ; do
        if [ "$VERBOSE" == "1" ] ; then
            echo "$img_name"
        else
            echo "${img_name/volume-/}"
        fi
    done
}

ceph_mirror_image_state_sync()
{
    local enabled=$1
    for img_name in $(rbd mirror pool status $BUILTIN_BACKPOOL --verbose --format json | jq -r .images[].name 2>/dev/null) ; do
        local img_id=${img_name/volume-/}
        if ! echo "$enabled" | grep -q $img_id ; then
            echo "disable mirrored image $img_name from $BUILTIN_BACKPOOL"
            Quiet -n rbd mirror image disable $BUILTIN_BACKPOOL/${img_name} --force
        fi
    done
}

ceph_mirror_parent_image_remove()
{
    local id=$1
    local pool=${2:-glance-images}

    Quiet -n rbd snap unprotect $pool/${id}@snap
    Quiet -n rbd snap purge $pool/$id
    Quiet -n rbd remove $pool/$id
}

ceph_mirror_disable()
{
    # sequence matters: glance is the parent of cinder
    # disable children pool/images first
    for pool in $BUILTIN_BACKPOOL glance-images ; do
        # remove peers
        for peer_id in $(timeout 5 rbd mirror pool info $pool --format json 2>/dev/null | jq -r .peers[].uuid 2>/dev/null) ; do
            echo "remove peer $peer_id from pool $pool"
            Quiet -n rbd mirror pool peer remove $pool $peer_id
        done

        for img_name in $(timeout 5 rbd mirror pool status $pool --verbose --format json 2>/dev/null | jq -r .images[].name 2>/dev/null) ; do
            echo "disable mirroring $img_name from pool $pool"
            if [ "$pool" = "$BUILTIN_BACKPOOL" ] ; then
                Quiet -n ceph_mirror_image_disable $img_name
            else
                Quiet -n rbd mirror image disable glance-images/$img_name --force
            fi
        done

        Quiet -n timeout 5 rbd mirror pool disable $pool
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

    if [ -z "$self_site" -o -z "$peer_site" ] ; then
        printf "%s\n" $border && return 0
    fi

    local vols=$($OPENSTACK volume list --all-projects -f json)
    local ins=$($OPENSTACK server list --all-projects -f value -c ID -c Name)
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
        if [ "$(echo $vol_info | jq -r .mirroring.mode)" = "snapshot" ] ; then
            if [  "$self_desc" != "local image is primary" ] ; then
                local next_schedule="$(rbd mirror snapshot schedule status --pool $BUILTIN_BACKPOOL --image $img_name --cluster $self_site --format json 2>/dev/null | jq -r .[].schedule_time)"
                [ -n "$next_schedule" ] || next_schedule="$(rbd mirror snapshot schedule status --pool $BUILTIN_BACKPOOL --image $img_name --cluster $peer_site --format json 2>/dev/null | jq -r .[].schedule_time)"
                local snapshot_interval="$(rbd mirror snapshot schedule ls --pool $BUILTIN_BACKPOOL --image $img_name --cluster $self_site 2>/dev/null)"
                [ -n "$snapshot_interval" ] || snapshot_interval="$(rbd mirror snapshot schedule ls --pool $BUILTIN_BACKPOOL --image $img_name --cluster $peer_site 2>/dev/null)"
                local self_sync="next sync ${next_schedule#20*-}(${snapshot_interval#every })"
            fi
        else
            local self_behind=$(echo $self_status | jq -r ".[] | select(.name == \"${img_name}\").description" | awk -F', ' '{print $2}' | jq -r .entries_behind_primary 2>/dev/null)
            if [ -n "$self_behind" ] ; then
                if [ "$self_behind" = "0" ] ; then
                    self_sync="synced"
                else
                    self_sync="${self_behind:-unknown} entries behind"
                fi
            fi
        fi

        if [ "$(echo $vol_info | jq -r .mirroring.mode)" = "snapshot" ] ; then
            if [  "$peer_desc" != "local image is primary" ] ; then
                local next_schedule="$(rbd mirror snapshot schedule status --pool $BUILTIN_BACKPOOL --image $img_name --cluster $self_site --format json 2>/dev/null | jq -r .[].schedule_time)"
                [ -n "$next_schedule" ] || next_schedule="$(rbd mirror snapshot schedule status --pool $BUILTIN_BACKPOOL --image $img_name --cluster $peer_site --format json 2>/dev/null | jq -r .[].schedule_time)"
                local snapshot_interval="$(rbd mirror snapshot schedule ls --pool $BUILTIN_BACKPOOL --image $img_name --cluster $self_site 2>/dev/null)"
                [ -n "$snapshot_interval" ] || snapshot_interval="$(rbd mirror snapshot schedule ls --pool $BUILTIN_BACKPOOL --image $img_name --cluster $peer_site 2>/dev/null)"
                local peer_sync="next sync ${next_schedule#20*-}(${snapshot_interval#every })"
            fi
        else
            local peer_behind=$(echo $peer_status | jq -r ".[] | select(.name == \"${img_name}\").description" | awk -F', ' '{print $2}' | jq -r .entries_behind_primary 2>/dev/null)
            if [ -n "$peer_behind" ] ; then
                if [ "$peer_behind" = "0" ] ; then
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

        if [ "$vol_status" == "in-use" ] ; then
            device=$(echo $vols | jq -r ".[] | select(.ID == \"${vol_id}\").\"Attached to\"[0].device")
            srv_id=$(echo $vols | jq -r ".[] | select(.ID == \"${vol_id}\").\"Attached to\"[0].server_id")
            host=$(echo "$ins" | grep ${srv_id:-NOSRVID} | awk '{print $2}')
        fi
        echo "${vol_id},${vol_mode},${vol_name},${vol_size},${device},${host},${self_sync},${img_state},${peer_sync},${peer_img_state}" >> /tmp/${self_site}.status
        img_idx=$(( img_idx + 1 ))
    done

    cat /tmp/${self_site}.status | sort -t"," -k6 |  while read -r line ; do
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
        if [ "x$host" = "x" -o "x$host" = "xnull" -o "x$host" != "x$prev_host" ] ; then
            printf "%s\n" $border
        fi

        if [ -n "$device" -a -n "$host" ] ; then
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
            if Quiet rbd info $BUILTIN_BACKPOOL/$img_name 2>/dev/null ; then
                if [ "$(rbd info $BUILTIN_BACKPOOL/$img_name --format json | jq -r .mirroring.primary)" = "true" ] ; then
                    continue
                else
                    vols_promoted=false
                fi
            else
                vols_promoted=false
            fi

        done

        if [ "$vols_promoted" = "true" ] ; then
            if [ "$VERBOSE" == "1" ] ; then
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

    for srv in $* ; do
        local server_info=$(cat $mirror_dir/$srv)
        local name=$(echo $server_info | jq -r .name)
        local project=$(echo $server_info | jq -r .project_name)
        local flavor=$(echo $server_info | jq -r .flavor | cut -d" " -f1)
        local network=$(echo $server_info | jq -r | grep addresses -A1 | tail -1 | cut -d":" -f1 | xargs)
        local volume_ids=$(echo $server_info | jq -r ".attached_volumes[].id")
        local bootable_vid=
        local vol_status=

        $OPENSTACK flavor list --format value -c Name | grep -q "$flavor" || echo "Mirror site has no flavor: $flavor"

        for vid in $volume_ids ; do
            local vol_info=$($OPENSTACK volume show $vid --format json)
            if [ "$(echo $vol_info | jq -r .bootable)" = "true" ] ; then
                bootable_vid=$vid
                vol_status=$(echo $vol_info | jq -r .status)
                break
            fi
        done

        local server_id=$($OPENSTACK server list --project $project --format value -c Name -c ID | grep "$name" | cut -d" " -f1)
        if [ -n "$bootable_vid" -a "$vol_status" != "in-use" ] ; then
            if [ "x$server_id" = "x" ] ; then
                server_id=$(OS_PROJECT_NAME=$project $OPENSTACK server create --network $network --flavor $flavor --volume $bootable_vid --wait --format value -c id $name)
                if [ "x$server_id" = "x" ] ; then
                    echo "failed to create service instance" && continue
                else
                    echo "created server: $name ${server_id:-EMPTYSERVERID}"
                fi
            else
                if $OPENSTACK server show $server_id --format json | jq -r .attached_volumes[].id | grep -q "$bootable_vid" ; then
                    echo "server existed: $name ${server_id:-EMPTYSERVERID}"
                else
                    echo "please manually fix duplicated server name: $server" && continue
                fi
            fi
        else
            if [ -n "$server_id" ] ; then
                $OPENSTACK server start ${server_id:-EMPTYSERVERID} 2>/dev/null
            else
                echo "bootable volume image of server ($name ${server_id:-EMPTYSERVERID}) is not yet mirrored" && continue
            fi
        fi

        local server_status=$($OPENSTACK server show ${server_id:-EMPTYSERVERID} --format value -c status)
        if [ -z "$server_status" ] ; then
            echo "unable to create server: $name"
        elif [ "$server_status" = "SHUTOFF" ] ; then
            echo "unable to start server ($name ${server_id:-EMPTYSERVERID}) as not all of its volumes were promoted"
        elif [ "$server_status" = "ERROR" ] ; then
            $OPENSTACK server delete ${server_id:-EMPTYSERVERID} 2>/dev/null
            echo "deleted server ($name ${server_id:-EMPTYSERVERID}) in ERROR state"
            echo "make sure all volumes belonging to this server were promoted to primary"
        else
            for vid in $volume_ids ; do
                local vol_info=$($OPENSTACK volume show $vid --format json)
                if [ "$vid" != "$bootable_vid" -a "$($OPENSTACK volume show $vid --format json | jq -r .status)" = "available" ] ; then
                    if $OPENSTACK server add volume ${server_id:-EMPTYSERVERID} $vid ; then
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

    if [ "$mode" = "force" ] ; then
        local rbdflg="--force"
        while [ $img_idx -lt $img_num ] ; do
            local img_name=$(echo $status | jq -r --arg idx $img_idx '.images[$idx | tonumber].name')
            if [ "$img_name" = "$name" -a "$(rbd info $BUILTIN_BACKPOOL/$img_name --format json | jq -r .mirroring.primary)" = "false" ] ; then
                echo "$mode promote $BUILTIN_BACKPOOL/$img_name on local site"
                for i in {1..10} ; do
                    sleep 10
                    Quiet rbd mirror image promote $rbdflg $BUILTIN_BACKPOOL/$img_name 2>/dev/null && break
                done

                if timeout 3 $sshcmd root@${peer_vip:-emptyIp} "exit 0" 2>/dev/null ; then
                    Quiet $sshcmd root@${peer_vip:-emptyIp} "$HEX_SDK ceph_mirror_demote_image $id $mode"
                else
                    echo "remote site $peer_vip unreachable"
                fi
                break
            fi
            img_idx=$(( img_idx + 1 ))
        done
    else
        local rbdflg=
        while [ $img_idx -lt $img_num ] ; do
            local img_name=$(echo $status | jq -r --arg idx $img_idx '.images[$idx | tonumber].name')
            if [ "$img_name" = "$name" -a "$(rbd info $BUILTIN_BACKPOOL/$img_name --format json | jq -r .mirroring.primary)" = "false" ] ; then
                if timeout 3 $sshcmd root@${peer_vip:-emptyIp} "exit 0" 2>/dev/null ; then
                    Quiet $sshcmd root@${peer_vip:-emptyIp} "$HEX_SDK ceph_mirror_demote_image $id $mode"
                else
                    rbdflg="--force"
                fi
                echo "$mode promote $BUILTIN_BACKPOOL/$img_name on local site"
                for i in {1..10} ; do
                    sleep 10
                    Quiet rbd mirror image promote $rbdflg $BUILTIN_BACKPOOL/$img_name 2>/dev/null && break
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

    while [ $img_idx -lt $img_num ] ; do
        local img_name=$(echo $status | jq -r --arg idx $img_idx '.images[$idx | tonumber].name')
        if [ "$img_name" = "$name" ] ; then
            local vol=$($OPENSTACK volume show $id -f json)
            echo $vol | jq -r ".attachments[].server_id" | xargs -i $OPENSTACK server stop {} 2>/dev/null || true
            if [ "$mode" = "force" ] ; then
                sleep 10
                Quiet -n rbd mirror image demote $BUILTIN_BACKPOOL/$img_name
                Quiet -n rbd mirror image resync $BUILTIN_BACKPOOL/$img_name
            else
                ( sleep 10 ; rbd config image set $BUILTIN_BACKPOOL/$img_name rbd_cache_block_writes_upfront true ; rbd config image set $BUILTIN_BACKPOOL/$img_name rbd_cache_block_writes_upfront false ; rbd mirror image demote $BUILTIN_BACKPOOL/$img_name) >/dev/null 2>&1 &
                pids[${img_idx}]=$!
            fi
            break
        fi
        img_idx=$(( img_idx + 1 ))
    done
    if [ "$mode" != "force" ] ; then
        for p in ${pids[*]} ; do
            wait $p && echo "RBD journal upfronted ($p)"
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

    if [ "$mode" = "force" ] ; then
        local rbdflg="--force"
        while [ $img_idx -lt $img_num ] ; do
            local img_name=$(echo $status | jq -r --arg idx $img_idx '.images[$idx | tonumber].name')
            if [ "$(rbd info $BUILTIN_BACKPOOL/$img_name --format json | jq -r .mirroring.primary)" = "false" ] ; then
                echo "$mode promote $BUILTIN_BACKPOOL/$img_name on local site"
                for i in {1..10} ; do
                    sleep 10
                    Quiet rbd mirror image promote $rbdflg $BUILTIN_BACKPOOL/$img_name 2>/dev/null && break
                done
            fi
            img_idx=$(( img_idx + 1 ))
        done
        if timeout 3 $sshcmd root@${peer_vip:-emptyIp} "exit 0" 2>/dev/null ; then
            Quiet -n $sshcmd root@${peer_vip:-emptyIp} "$HEX_SDK ceph_mirror_demote_site $mode"
        else
            echo "remote site $peer_vip unreachable"
        fi
    else
        local rbdflg=
        if timeout 3 $sshcmd root@${peer_vip:-emptyIp} "exit 0" 2>/dev/null ; then
            Quiet -n $sshcmd root@${peer_vip:-emptyIp} "$HEX_SDK ceph_mirror_demote_site $mode"
        else
            echo "remote site $peer_vip unreachable"
            rbdflg="--force"
        fi
        while [ $img_idx -lt $img_num ] ; do
            local img_name=$(echo $status | jq -r --arg idx $img_idx '.images[$idx | tonumber].name')
            if [ "$(rbd info $BUILTIN_BACKPOOL/$img_name --format json | jq -r .mirroring.primary)" = "false" ] ; then
                echo "$mode promote $BUILTIN_BACKPOOL/$img_name on local site"
                for i in {1..10} ; do
                    sleep 10
                    Quiet rbd mirror image promote $rbdflg $BUILTIN_BACKPOOL/$img_name 2>/dev/null && break
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

    while [ $img_idx -lt $img_num ] ; do
        local img_name=$(echo $status | jq -r --arg idx $img_idx '.images[$idx | tonumber].name')
        local vol=$($OPENSTACK volume show ${img_name#volume-} -f json)
        echo $vol | jq -r ".attachments[].server_id" | xargs -i $OPENSTACK server stop {} 2>/dev/null || true
        echo "$mode demote $BUILTIN_BACKPOOL/$img_name pool on peer site"
        if [ "$mode" = "force" ] ; then
            sleep 10
            Quiet -n rbd mirror image demote $BUILTIN_BACKPOOL/$img_name
            Quiet -n rbd mirror image resync $BUILTIN_BACKPOOL/$img_name
        else
            ( sleep 10 ; rbd config image set $BUILTIN_BACKPOOL/$img_name rbd_cache_block_writes_upfront true ; rbd config image set $BUILTIN_BACKPOOL/$img_name rbd_cache_block_writes_upfront false ; rbd mirror image demote $BUILTIN_BACKPOOL/$img_name) >/dev/null 2>&1 &
            pids[${img_idx}]=$!
        fi

        img_idx=$(( img_idx + 1 ))
    done
    if [ "$mode" != "force" ] ; then
        for p in ${pids[*]} ; do
            wait $p && echo "RBD journal upfronted ($p)"
        done
    fi

    local self_site=$(find /etc/ceph/ -type l -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//")
    Quiet -n cubectl node exec -r control -pn "systemctl restart ceph-rbd-mirror@${self_site}.service"
}

# return crush class by SCSI disk
# params: $1 - partition name (e.g.: /dev/sdb)
ceph_osd_get_class()
{
    local dev=$1
    if ceph-volume lvm list --format json | jq -r ".[][] | select(.devices[] == \"$dev\").devices[]" | grep -q "^${dev}$" ; then
        :
    elif echo $dev | grep -q 'sd' ; then
        dev=$(echo $dev | sed -e 's/[0-9]*$/1/g')
    elif echo $dev | grep -q 'nvme' ; then
        dev="$(echo $dev | grep -oe '/dev/nvme[0-9]\+n[0-9]\+')p1"
    fi

    local osd_id=$(ceph_osd_get_id $dev)
    [ -n "$osd_id" ] || return 1
    local class_type=$($CEPH osd tree -f json | jq -r --arg OSDID $osd_id '.nodes[] | select((.id == ($OSDID | tonumber))).device_class')
    echo -n $class_type
}

# list osd id by partition
# params: $1 - partition name (e.g.: /dev/sdd1)
# return: int (e.g.: 1)
ceph_osd_get_id()
{
    local dev=$1
    # check if device exists
    [ -n "$(readlink -e $dev)" ] || Error "no such device $dev"

    local uuid=$(GetBlkUuid $dev)
    [ "x$uuid" != "x" ] || Error "$dev uuid not found"

    # get osd_id from device osd map
    if [ -f $CEPH_OSD_MAP ] ; then
        local id0=$(cat $CEPH_OSD_MAP | grep $dev | awk '{print $2}')
        if [ -n "$id0" ] ; then
            if grep "$dev" $CEPH_OSD_MAP | grep -q "$uuid" ; then
                echo -n $id0
                return 0
            fi
        fi
    fi

    # get osd_id from mount point map
    local id1=$(lsblk $dev -d -n -o MOUNTPOINT | grep -m 1 -oe '[0-9]\+$')
    if [ -n "$id1" ] ; then
        echo -n $id1
        return 0
    fi

    # get osd_id from ceph osd dump
    local id2=$($CEPH osd dump | grep "$uuid" 2>/dev/null | grep -oe '^osd\.[0-9]\+' | grep -m 1 -oe '[0-9]\+')
    if [ -n "$id2" ] ; then
        echo -n $id2
        return 0
    fi

    # get osd_id from ceph-volume lvm
    local id3=$(ceph-volume lvm list --format json | jq -r ".[][] | select(.devices[] == \"$dev\").tags.\"ceph.osd_id\"")
    num_re='^[0-9]+$'
    if [[ $id3 =~ $num_re ]] ; then
        echo -n $id3
        return 0
    fi

    # in case of fresh install when there's no osd_id for newly-prepared data disks, create a new one
    local retrycnt=30
    local id4=$($CEPH osd new $uuid 2>/dev/null)
    while [ -z "$id4" ] ; do
        sleep 1
        id4=$($CEPH osd new $uuid 2>/dev/null)
        [ "$retrycnt" -gt 0 ] || break
        retrycnt=$((retrycnt-1))
    done
    echo -n $id4
    return 0
}

ceph_osd_get_datapart()
{
    local metapart=$1
    local datapart=
    # check if osd meta partition exists
    [ -n "$(readlink -e $metapart)" ] || return 1
    datapart_partuuid=$(grep $metapart $CEPH_OSD_MAP 2>/dev/null | cut -d" " -f4)
    datapart=$(blkid -o device  --match-token PARTUUID=$datapart_partuuid 2>/dev/null)
    if [ "x$datapart" = "x" ] ; then
        local metapart_num=$(echo ${metapart} | grep -o "[0-9]$")
        local metapart_stem=$(echo ${metapart} | sed "s/[0-9]$//")
        datapart=${metapart_stem}$((metapart_num + 2))
    fi

    echo -n $datapart
}

ceph_osd_get_datapartuuid()
{
    local metapart=$1
    local datapart_partuuid=
    # check if osd meta partition exists
    [ -n "$(readlink -e $metapart)" ] || return 1
    datapart_partuuid=$(grep $metapart $CEPH_OSD_MAP 2>/dev/null | cut -d" " -f4)
    if [ "x$datapart_partuuid" = "x" ] ; then
        local metapart_num=$(echo ${metapart} | grep -o "[0-9]$")
        local metapart_stem=$(echo ${metapart} | sed "s/[0-9]$//")
        local datapart=${metapart_stem}$((metapart_num + 2))
        datapart=$(blkid | grep -e 'PARTLABEL=\"cube_data' | cut -d":" -f1 | grep $datapart)
        datapart_partuuid=$(blkid -o value -s PARTUUID $datapart)
    fi

    echo -n $datapart_partuuid
}

ceph_osd_remount()
{
    local osdpth=/var/lib/ceph/osd

    for osd_dir in $(find ${osdpth}/* -type d) ; do
        osd_id=${osd_dir##*-}
        if systemctl is-active ceph-osd@$osd_id -q ; then
            $CEPH tell osd.$osd_id compact >/dev/null 2>&1 || true
            systemctl stop ceph-osd@$osd_id || true
        fi
        umount $osd_dir 2>/dev/null || true
    done

    while read LINE ; do
        dev=$(echo $LINE | cut -d" " -f1)
        osd_id=$(echo $LINE | cut -d" " -f2)
        datapart_partuuid=$(echo $LINE | cut -d" " -f4)
        lvm_json=$(ceph-volume lvm list $osd_id --format json)
        if echo $lvm_json | jq -r .[][].lv_uuid | grep -q "$datapart_partuuid" ; then
            :
        else
            mkdir -p ${osdpth}/ceph-${osd_id}
            chmod 0755 ${osdpth}/ceph-${osd_id}
            mount $dev $osdpth/ceph-${osd_id}
            if [ "x$(readlink $osdpth/ceph-$osd_id/block)" != "x/dev/disk/by-partuuid/$datapart_partuuid" ] ; then
                unlink $osdpth/ceph-$osd_id/block 2>/dev/null
                (cd $osdpth/ceph-$osd_id && ln -sf /dev/disk/by-partuuid/$datapart_partuuid block)
            fi
            Quiet -n systemctl start ceph-osd@$osd_id
        fi
    done < $CEPH_OSD_MAP
}

ceph_osd_create_map()
{
    local osdpth=/var/lib/ceph/osd
    local osdmap_new=$(mktemp -u /tmp/dev_osd.mapXXXX)
    local osdmap_json=$(ceph-volume raw list --format json)

    if [ $(echo $osdmap_json | jq -r "keys[]" | wc -l) -gt 0 ] ; then
        for metapart_uuid in $(echo $osdmap_json | jq -r "keys[]") ; do
            metapart=$(readlink -f /dev/disk/by-uuid/$metapart_uuid)
            osd_id=$(echo $osdmap_json | jq -r ".\"$metapart_uuid\".osd_id")
            if [ ! -e $metapart ] ; then
                lvm_json=$(ceph-volume lvm list $osd_id --format json)
                metapart=$(echo $lvm_json | jq -r .[][].devices[] | sort -u)
                datapart=$metapart
                datapart_partuuid=$(echo $lvm_json | jq -r .[][].lv_uuid)
            else
                datapart=$(echo $osdmap_json | jq -r ".\"$metapart_uuid\".device")
                datapart_partuuid=$(blkid -o value -s PARTUUID $datapart)
            fi
            echo "${metapart:-metapart} ${osd_id:-osd_id} ${metapart_uuid:-metapart_uuid} ${datapart_partuuid:-datapart_partuuid}" >> $osdmap_new
        done
    fi
    cat $osdmap_new | sort -k1 > ${osdmap_new}.sorted
    unlink $osdmap_new
    if cmp -s ${osdmap_new}.sorted $CEPH_OSD_MAP ; then
        rm -f ${osdmap_new}.sorted
    else
        mv -f ${osdmap_new}.sorted $CEPH_OSD_MAP
    fi
    # clean up broken ceph osd folders
    for osddir in $(ls -1d ${osdpth}/ceph-*) ; do
        if ! readlink -e ${osddir}/block ; then
            rm -f ${osddir}/block
            rmdir ${osddir}
        fi
    done
}

ceph_wait_for_services()
{
    local count=${1:-12}

    if ! Quiet $CEPH -s ; then
        # When HA cluster is powercycled, master node or any control node running alone has no quorum yet
        if [ $(cubectl node list -r control | wc -l) -gt 1 ] ; then
            if [ $(cubectl node exec -r control -pn "systemctl is-active ceph-mon@\$HOSTNAME" | grep -i "^active$" | wc -l) -eq 1 ] ; then
                return 0
            fi
        fi
    fi

    for i in $(seq $count) ; do
        local fail=0
        $CEPH -s >/dev/null 2>&1 || ((fail++))
        ! ( $CEPH -s | grep -q "mgr: no daemons active" ) || ((fail++))
        ! ( $CEPH -s | grep -q "mds: 0.* up" ) || ((fail++))
        ! ( $CEPH -s | grep -q "volumes: 0.* healthy" ) || ((fail++))
        [[ $fail -ne 0 ]] || break
        sleep 10
    done

    return $fail
}

ceph_wait_for_status()
{
    local status=${1:-ok}
    local timeout=${2:-60}

    Quiet $CEPH -s || return 0

    local i=0
    while [ $i -lt $timeout ] ; do
        if $($CEPH health | grep -i -q $status) ; then
            break
        fi
        sleep 1
        i=$(expr $i + 1)
    done
}

ceph_osd_map()
{
    local osd_tree=$($CEPH osd tree -f json)

    readarray id_array <<<"$(echo $osd_tree | jq '.nodes[] | select(.type == "osd").id' | sort)"
    declare -p id_array > /dev/null
    for id in "${id_array[@]}" ; do
        id=$(echo -n $id | tr -d '\n')
        local host=$(echo $osd_tree | jq -r --arg OSDID $id '.nodes[] | select(.type == "host") | select(.children[] | select(. == ($OSDID | tonumber))).name')
        local dev=$(ssh $host sh -c "mount | grep 'ceph-$id '" 2>/dev/null | awk '{print $1}')
        echo "$id,$host,$dev"
    done
}

ceph_osd_repair()
{
    local osd_pth="/var/lib/ceph/osd/ceph-$1"

    if [ -e $osd_pth ] ; then
        Quiet -n ceph_enter_maintenance
        Quiet -n $CEPH tell osd.$1 compact
        Quiet -n systemctl stop ceph-osd@$1
        Quiet -n ceph-bluestore-tool repair --path $osd_pth
        Quiet -n ceph-kvstore-tool bluestore-kv $osd_pth compact
        Quiet -n systemctl start ceph-osd@$1
        Quiet -n ceph_leave_maintenance
    else
        echo "$osd_pth not found on $(hostname)"
    fi
}

ceph_force_create_pg()
{
    local state=$1
    local lost=$2

    readarray pg_array <<<"$($CEPH pg dump_stuck inactive unclean stale undersized degraded 2>/dev/null | grep $state | awk '{print $1}' | sort | uniq)"
    declare -p pg_array > /dev/null
    for pg in "${pg_array[@]}" ; do
        if [ -n "$pg" ] ; then
            $CEPH osd force-create-pg $pg --yes-i-really-mean-it
            if [ "$lost" == "lost" ] ; then
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
    for obj in "${state_array[@]}" ; do
        local state=$(echo $obj | tr -d '\n')
        if [ -n "$state" ] ; then
            Quiet -n ceph_force_create_pg $state $lost
        fi
    done
}

ceph_restful_username_list()
{
    $CEPH restful list-keys 2>/dev/null | jq -r 'keys[]'
}

ceph_restful_key_create()
{
    local username=$1
    Quiet -n $CEPH restful create-key $username
}

ceph_restful_key_delete()
{
    local username=$1
    Quiet -n $CEPH restful delete-key $username
}

ceph_restful_key_list()
{
    Quiet -n $CEPH restful list-keys
}

ceph_mgr_module_enable()
{
    local module=$1
    local timeout=${2:-2}

    for i in 1 2 3 4 5 ; do ! $CEPH mgr module ls >/dev/null 2>&1 || break ; done

    local i=0
    while [ $i -lt $timeout ] ; do
        local ready=$($CEPH mgr dump | jq -r .available | tr -d '\n')
        if [ "$ready" == "true" ] ; then
            if ! $CEPH mgr module ls -f json | jq -r .enabled_modules[] | grep -q $module ; then
                Quiet -n $CEPH mgr module enable $module
            else
                break
            fi
        fi
        sleep 1
        i=$(expr $i + 1)
    done
}

ceph_mon_msgr2_enable()
{
    local timeout=${1:-60}

    Quiet -n $CEPH mon enable-msgr2
    local i=0
    while [ $i -lt $timeout ] ; do
        if $CEPH -s | grep -q "not enabled msgr2" ; then
            Quiet -n $CEPH mon enable-msgr2
        else
            break
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
    if [ -n "$host" -a -n "$pass" ] ; then
        local header=$(sshpass -p "$pass" ssh root@$host $CEPH config generate-minimal-conf &2>/dev/null)
    elif [ -n "$host" -a -z "$pass" ] ; then
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

    Quiet -n $CEPH dashboard set-ssl-certificate -i /var/www/certs/server.cert
    Quiet -n $CEPH dashboard set-ssl-certificate-key -i /var/www/certs/server.key
    Quiet -n $CEPH dashboard set-iscsi-api-ssl-verification false
    Quiet -n $CEPH dashboard set-rgw-api-ssl-verify false
    Quiet -n $CEPH dashboard set-grafana-api-ssl-verify false
    Quiet -n $CEPH dashboard set-grafana-api-url https://$shareId/grafana
    if ! timeout 5 radosgw-admin user list | jq -r .[] | grep -q $name ; then
        local info=$(timeout 5 radosgw-admin user create --uid=$name --display-name=$name --system)
        echo "$(echo $info | jq -r .keys[0].access_key)" > /tmp/ceph_rgw_access_key
        echo "$(echo $info | jq -r .keys[0].secret_key)" > /tmp/ceph_rgw_secret_key
        Quiet -n $CEPH dashboard set-rgw-api-access-key -i /tmp/ceph_rgw_access_key
        Quiet -n $CEPH dashboard set-rgw-api-secret-key -i /tmp/ceph_rgw_secret_key
    fi
    Quiet -n $CEPH dashboard set-pwd-policy-enabled false
    echo "admin" > /tmp/ceph_admin_pass
    Quiet -n $CEPH dashboard ac-user-create admin -i /tmp/ceph_admin_pass administrator
    rm -f /tmp/ceph_ceph_admin_pass /tmp/ceph_rgw_access_key /tmp/ceph_rgw_secret_key
    Quiet -n $CEPH dashboard feature disable nfs
    Quiet -n $CEPH dashboard feature disable iscsi
}

ceph_dashboard_iscsi_gw_add()
{
    local addr=$1
    local password=$2

    if ! $CEPH dashboard iscsi-gateway-list | jq .gateways | jq -r 'keys[]' | grep -q $HOSTNAME ; then
        local gw_cfg=$(mktemp /tmp/iscsigw.XXXX)
        echo "http://admin:$password@$addr:5010" >$gw_cfg
        Quiet -n $CEPH dashboard iscsi-gateway-add -i $gw_cfg
        rm -f $gw_cfg
    fi
}

ceph_dashboard_iscsi_gw_rm()
{
    if $CEPH dashboard iscsi-gateway-list | jq .gateways | jq -r 'keys[]' | grep -q $HOSTNAME ; then
        Quiet -n $CEPH dashboard iscsi-gateway-rm $HOSTNAME
    fi
}

ceph_dashboard_idp_config()
{
    local shared_id=$1
    local port=$2
    local timeout=${3:-2}
    local i=0

    Quiet $CEPH -s || return 0

    while [ $i -lt $timeout ] ; do
        if ! curl -k https:/$shared_id:$port/ceph/auth/saml2/metadata 2>/dev/null | grep -q "entityID.*$shared_id" ; then
            $CEPH dashboard sso setup saml2 \
                  https://$shared_id:$port \
                  /etc/keycloak/saml-metadata.xml \
                  username \
                  https://$shared_id:10443/auth/realms/master \
                  /var/www/certs/server.cert /var/www/certs/server.key
            Quiet -n $CEPH dashboard sso enable saml2
        else
            curl -k https://$shared_id:$port/ceph/auth/saml2/metadata | xmllint --format - > /etc/keycloak/ceph_dashboard_sp_metadata.xml
            # WHY?! run twice to make configure default client scope work
            Quiet -n terraform-cube.sh apply -auto-approve -target=module.keycloak_ceph_dashboard -var cube_controller=$shared_id
            Quiet -n terraform-cube.sh apply -auto-approve -target=module.keycloak_ceph_dashboard -var cube_controller=$shared_id
            break
        fi
        sleep 1
        i=$(expr $i + 1)
    done
}

ceph_mount_cephfs()
{
    if $CEPH -s >/dev/null ; then
        for i in {1..3} ; do
            if [ $(mount | grep $CEPHFS_STORE_DIR | wc -l) -gt 1 ] ; then
                timeout $SRVSTO umount $CEPHFS_STORE_DIR 2>/dev/null || umount -l $CEPHFS_STORE_DIR 2>/dev/null
            fi
            if [ $(mount | grep $CEPHFS_STORE_DIR | wc -l) -lt 1 ] ; then
                timeout $SRVSTO mount -t ceph :/ $CEPHFS_STORE_DIR -o name=admin,secretfile=/etc/ceph/admin.key >/dev/null 2>&1 && break
            fi
            sleep 5
        done
    fi
}

ceph_node_group_list()
{
    if $CEPH -s >/dev/null ; then
        for bucket in $($CEPH osd tree | grep root | awk '{print $4}') ; do
            printf %.1s ={1..60} $'\n'
            printf "%.60s\n" "GROUP: $bucket"

            Quiet -n $CEPH osd tree-from $bucket
        done
    fi
}

ceph_create_node_group()
{
    if [ $# -lt 2 ] ; then
        echo "Usage: $0 group node(host) [<node2(host2)...>]"
        Quiet -n ceph_node_group_list
        exit 1
    fi

    local group=$1
    shift 1

    if [ "$group" = "default" ] ; then
        local pool=$BUILTIN_BACKPOOL
        local cpool=$BUILTIN_CACHEPOOL
        local rule=replicated_rule
    else
        local pool=${group}-pool
        local cpool=${group}-cache
        local rule=${group}
    fi

    local b_size=$($CEPH osd pool get $BUILTIN_BACKPOOL size | awk '{print $2}' | tr -d '\n')
    local c_size=$($CEPH osd pool get $BUILTIN_CACHEPOOL size | awk '{print $2}' | tr -d '\n')
    local node_in_dft=$($CEPH osd crush ls default | sort | uniq)
    local node_in_dft_cnt=$($CEPH osd crush ls default | sort | uniq | wc -l)
    for o in $node_in_dft ; do
        for p in $* ; do
            if [ "x$o" = "x$p" ] ; then
                ((node_in_dft_cnt--))
                break
            fi
        done
    done
    if [ ${node_in_dft_cnt:-0} -lt ${b_size:-1} ] ; then
        echo "WARNING OF MISCONFIGURATIONS: num of remaining nodes($node_in_dft_cnt) in default group CANNOT be fewer than $b_size"
        Quiet -n ceph_node_group_list
        exit 1
    fi

    if ! ($CEPH osd pool ls | grep -q $pool) ; then
        Quiet -n ceph_create_pool $pool rbd
        Quiet -n ceph_create_pool $cpool rbd
    fi

    if ! ($CEPH osd tree | grep root | grep -q $group) ; then
        Quiet -n $CEPH osd crush add-bucket $group root
    fi

    for N in $* ; do
        Quiet -n $CEPH osd crush move $N root=$group
    done

    local host_num=$($CEPH osd crush ls $group | sort | uniq | wc -l)
    if [ $b_size -gt $host_num ] ; then
        b_size=$host_num
        c_size=$(expr $b_size - 1)
    fi

    # set pool/cache size to the same as $BUILTIN_BACKPOOL/$BUILTIN_CACHEPOOL which were determined at set_ready
    Quiet -n ceph_adjust_pool_size "$pool" $b_size
    Quiet -n ceph_adjust_pool_size "$cpool" $c_size

    if ! ($CEPH osd crush rule list | grep -q $rule) ; then
        Quiet -n $CEPH osd crush rule create-replicated $rule $group host
    fi

    if ! ($CEPH osd pool get $pool crush_rule | grep -q "$rule") ; then
        Quiet -n $CEPH osd pool set $pool crush_rule $rule
        Quiet -n $CEPH osd pool set $cpool crush_rule $rule
    fi
    Quiet -n $CEPH osd pool get $pool crush_rule

    Quiet -n $HEX_SDK os_volume_type_create $group $pool

    Quiet -n cubectl node exec -pn -r storage "hex_config restart_ceph_osd"
    Quiet -n cubectl node exec -pn -r control "hex_config reconfig_cinder"
    Quiet -n cubectl node exec -pn -r control "hex_config restart_cinder"

    # Make another attempt to ensure osds are up
    readarray node_array <<<"$(/usr/sbin/cubectl node list -r storage -j | jq -r .[].hostname | sort)"
    for node_entry in "${node_array[@]}" ; do
        local node=$(echo $node_entry | head -c -1)
        ssh root@$node "systemctl is-active ceph-osd@* --quiet" || ssh root@$node "hex_config restart_ceph_osd"
    done
    # It can happen that openstack-cinder-volume stops after hex_config reconfig_cinder
    Quiet -n $OPENSTACK volume service set --enable cube@${pool} cinder-volume
    Quiet -n $HEX_CLI -c cluster check_repair HaCluster
}

ceph_remove_node_group()
{
    if [ $# != 1 ] ; then
        echo "Usage: $0 Group"
        ceph_node_group_list
        exit 1
    fi

    local group=$1
    if [ "$group" = "default" ] ; then
        echo "Waring: $group is a must-have bucket by system" && exit 1
    else
        local pool=${group}-pool
        local cpool=${group}-cache
        local rule=${group}
    fi

    # Before deleting pools, try to free up volumes in use
    for vid in $($OPENSTACK volume list --all-projects --long --format value -c ID -c Name -c Status | grep $group | grep "in-use" | cut -d' ' -f1) ; do
        for SID in $($OPENSTACK server list --long --format value -c ID) ; do
            if $OPENSTACK server show $SID | grep "$vid" ; then
                Quiet -n $OPENSTACK server remove volume $SID $vid || $OPENSTACK server delete $SID
            fi
        done
    done
    $OPENSTACK volume list --all-projects --long --format value  -c ID -c Type 2>/dev/null | grep $group | cut -d' ' -f1 | xargs -i $OPENSTACK volume delete --force {} || true

    if [ "$(ceph_osd_test_cache $pool)" == "on" ] ; then
        Quiet -n ceph_osd_disable_cache $pool
    fi

    if ($CEPH osd pool ls | grep -q $pool) ; then
        Quiet -n $CEPH osd pool delete $pool $pool --yes-i-really-really-mean-it
        Quiet -n $CEPH osd pool delete $cpool $cpool --yes-i-really-really-mean-it
    fi

    for N in $($CEPH osd crush ls $group) ; do
        Quiet -n $CEPH osd crush move $N root=default
    done

    if ($CEPH osd crush rule list | grep -q "^$rule$") ; then
        Quiet -n $CEPH osd crush rule rm $rule
    fi

    if ($CEPH osd tree | grep root | grep -q "$group") ; then
        Quiet -n $CEPH osd crush rm $group
    fi

    Quiet -n $OPENSTACK volume type delete $group

    Quiet -n cubectl node exec -pn -r storage "hex_config restart_ceph_osd"
    Quiet -n cubectl node exec -pn -r control "hex_config reconfig_cinder"
    Quiet -n cubectl node exec -pn -r control "hex_config restart_cinder"

    Quiet -n $OPENSTACK volume service set --disable cube@$pool cinder-volume
    Quiet -n cinder-manage service remove cinder-volume cube@$pool
    # It can happen that openstack-cinder-volume stops after hex_config reconfig_cinder
    Quiet -n hex_cli -c cluster check_repair HaCluster

    # Make another attempt to ensure osds are up
    for node in ${CUBE_NODE_STORAGE_HOSTNAMES[@]} ; do
        ssh root@$node "systemctl is-active ceph-osd@* --quiet" || ssh root@$node "hex_config restart_ceph_osd"
    done
}

ceph_create_group_ssdpool()
{
    local group=${1:-default}

    if [ "$group" = "default" ] ; then
        local pool=${BUILTIN_BACKPOOL}-ssd
        local cpool=$BUILTIN_CACHEPOOL
        local rule=rule-ssd
        local vtype=CubeStorage-ssd
    else
        local pool=${group}-ssd
        local cpool=${group}-cache
        local rule=${group}-ssd
        local vtype=${group}-ssd
    fi

    if ! ($CEPH osd crush rule list | grep -q "^$rule_ssd$") ; then
        $CEPH osd crush rule create-replicated $rule $group host ssd || return 1
    fi

    Quiet -n ceph_create_pool $pool rbd

    local c_size=$($CEPH osd pool get $cpool size | awk '{print $2}' | tr -d '\n')
    Quiet -n ceph_adjust_pool_size "$pool" $c_size
    $CEPH osd pool set $pool crush_rule $rule
    Quiet -n $HEX_SDK os_volume_type_create $vtype $pool

    Quiet -n cubectl node exec -pn -r control "hex_config reconfig_cinder"
    Quiet -n cubectl node exec -pn -r control "hex_config restart_cinder"
    # It can happen that openstack-cinder-volume stops after hex_config reconfig_cinder
    Quiet -n $OPENSTACK volume service set --enable cube@${pool} cinder-volume
    Quiet hex_cli -c cluster check_repair HaCluster 2>/dev/null
}

ceph_remove_group_ssdpool()
{
    local group=${1:-default}

    if [ "$group" = "default" ] ; then
        local pool=${BUILTIN_BACKPOOL}-ssd
        local vtype=CubeStorage-ssd
    else
        local pool=${group}-ssd
        local vtype=${group}-ssd
    fi

    Quiet -n $OPENSTACK volume type delete $vtype
    for i in {1..15} ; do
        $OPENSTACK volume type list --long --format value -c Name | grep -q "^$vtype$" || break
    done

    if $OPENSTACK volume type list --long --format value -c Name | grep -q "^$vtype$" ; then
        echo "Error: Volume type $vtype was not deleted possibly due to existing volumes. " && return 1
    else
        if ($CEPH osd pool ls | grep -q "^$pool$") ; then
            Quiet -n $CEPH osd pool delete $pool $pool --yes-i-really-really-mean-it
        fi
        Quiet -n cubectl node exec -pn -r control "hex_config reconfig_cinder"
        Quiet -n cubectl node exec -pn -r control "hex_config restart_cinder"
        # It can happen that openstack-cinder-volume stops after hex_config reconfig_cinder
        Quiet -n $HEX_CLI -c cluster check_repair HaCluster

    fi

    Quiet -n $OPENSTACK volume service set --disable cube@$pool cinder-volume
    Quiet -n cinder-manage service remove cinder-volume cube@$pool
}

ceph_osd_restart()
{
    local osd_ids=${*:-$($CEPH osd tree-from $(hostname) -f json 2>/dev/null | jq .nodes[0].children[] | sort -n)}
    Quiet -n ceph-volume lvm activate --all
    for id in $osd_ids ; do
        local osd_pth="/var/lib/ceph/osd/ceph-$id"
        if [ -e $osd_pth ] ; then
            ( $CEPH tell osd.$id compact || true ; \
              systemctl stop ceph-osd@$id ; \
              ceph-kvstore-tool bluestore-kv $osd_pth compact && \
                  systemctl start ceph-osd@$id ) >/dev/null 2>&1 &
        fi
    done
}

ceph_osd_compact()
{
    if $CEPH -s >/dev/null ; then
        hn=$(hostname)
        [ "$VERBOSE" != "1" ] || $CEPH osd df tree $hn 2>/dev/null || true
        $CEPH osd tree-from $hn -f json 2>/dev/null | jq .nodes[0].children[] | sort -n | xargs -i ceph tell osd.{} compact
        [ "$VERBOSE" != "1" ] || $CEPH osd df tree $hn 2>/dev/null || true
    fi
}

ceph_osd_host_set()
{
    local host=${1:-$(hostname)}
    local status=$2
    local osd_ids=$($CEPH osd tree-from $host -f json 2>/dev/null | jq .nodes[0].children[] | sort -n)

    for id in $osd_ids ; do
        Quiet -n $CEPH osd $status $id
    done
}

ceph_osd_relabel()
{
    local label_pth="/dev/disk/by-partlabel"
    local prefixes="cube_meta cube_data"
    local type=
    local dev=
    local disk=
    local part_pth=
    local part=
    local part_symbol=
    local part_num=
    local slink_symbol=
    local slink_num=

    [ -e $label_pth ] || return 0

    pushd $label_pth >/dev/null
    for prefix in $prefixes ; do
        for slink in $(find . -type l -name "*${prefix}*" | sort) ; do
            part_pth=$(readlink -e $slink)
            part=${part_pth#/dev/}
            disk=$(lsblk $part_pth -s -r -o NAME,TYPE | grep disk | cut -d' ' -f1 | sort -u)

            if [[ $disk =~ nvme ]] ; then
                # part: nvme0n1p1
                # disk: nvme0n1
                # part_symbol=0n1
                # part_num=p1
                type=nvme
            else
                # part: sda1
                # disk: sda
                # part_symbol=a
                # part_num=1
                type=sd
            fi
            part_symbol=${disk#*$type}
            part_num=${part#$type$part_symbol}

            slink_symbol=$(echo $slink | cut -d'_' -f3)
            slink_num=$(echo $slink | cut -d'_' -f4)

            if [ "${part_symbol}${part_num}" != "${slink_symbol}${slink_num}" ] ; then
                unlink $slink
                ln -sf ../../${type}${part_symbol}${part_num} ./${prefix}_${part_symbol}_${part_num}
            fi
        done
    done
    popd >/dev/null
}

ceph_osd_fix_fsid()
{
    local id=$1
    local osd_pth="/var/lib/ceph/osd/ceph-$id"

    if [ -e $osd_pth ] ; then
        if ! ceph-bluestore-tool bluefs-stats --path $osd_pth >/dev/null 2>&1 ; then
            uuidgen > $osd_pth/fsid
            local new_fsid=$(ceph-bluestore-tool bluefs-stats --path $osd_pth 2>&1 | grep -o "fsid.*" | awk '{print $2}')
            echo $new_fsid > $osd_pth/fsid
            chown ceph:ceph $osd_pth/fsid
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

    if [ -z "$vip" -o -z "$pass" ] ; then
        echo "Usage: $0 ceph_mirror_pair vip pass" && return 1
    fi

    Quiet sshpass -p "$pass" $sshcmd root@$vip "exit 0" || Error "Incorrect password to root@$vip"

    local self_id_rsa_pub=$(cat /root/.ssh/id_rsa.pub)
    local auth_keys=/root/.ssh/authorized_keys
    Quiet sshpass -p "$pass" $sshcmd root@$vip "cubectl node exec -r control \"echo $self_id_rsa_pub >>$auth_keys\""
    Quiet sshpass -p "$pass" $sshcmd root@$vip "cubectl node exec -r control \"$HEX_SDK dedup_sshauthkey\""

    local peer_id_rsa_pub=$($sshcmd root@$vip cat /root/.ssh/id_rsa.pub 2>/dev/null)
    Quiet cubectl node exec -r control "echo $peer_id_rsa_pub >> $auth_keys"
    Quiet cubectl node exec -r control "$HEX_SDK dedup_sshauthkey"
    $sshcmd root@$vip "exit 0" || Error "ssh-key not exchanged"

    local self_vip=$($HEX_SDK -f json health_vip_report | jq -r .description | cut -d"/" -f1)
    [ "$self_vip" != "non-HA" ] || self_vip=$(cat /etc/settings.cluster.json | jq -r ".[].ip.management")
    local self_ctlr=$(grep cubesys.controller /etc/settings.txt | cut -d"=" -f2 | xargs 2>/dev/null)-$self_vip
    if [ -z "$(echo $self_ctlr | cut -d"-" -f1)" ] ; then
        self_ctlr=$(hostname)${self_ctlr}
    fi
    Quiet cubectl node exec -r control "ln -sf /etc/ceph/ceph.conf /etc/ceph/${self_ctlr}-site.conf"
    Quiet cubectl node exec -r control "systemctl enable ceph-rbd-mirror@${self_ctlr}-site.service >/dev/null 2>&1"
    Quiet cubectl node exec -r control "systemctl restart ceph-rbd-mirror@${self_ctlr}-site.service >/dev/null 2>&1"

    local peer_ctlr=$($sshcmd root@$vip "grep cubesys.controller /etc/settings.txt | cut -d'=' -f2 | xargs" 2>/dev/null)-$vip
    if [ -z "$(echo $peer_ctlr | cut -d"-" -f1)" ] ; then
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
    Quiet $sshcmd root@$vip "$HEX_SDK ceph_mirror_pool_peer_set glance-images ${self_ctlr}-site"
    Quiet $sshcmd root@$vip "$HEX_SDK ceph_mirror_pool_peer_set cinder-volumes ${self_ctlr}-site"

    ceph_basic_config_gen /etc/ceph/${peer_ctlr}-site.conf $vip
    Quiet cubectl node rsync -r control /etc/ceph/${peer_ctlr}-site.conf
    Quiet $sshcmd root@$vip "$HEX_SDK ceph_basic_config_gen /etc/ceph/${self_ctlr}-site.conf $self_vip"
    Quiet $sshcmd root@$vip "cubectl node rsync -r control /etc/ceph/${self_ctlr}-site.conf"
}

ceph_mirror_unpair()
{
    local self_site=$(find /etc/ceph/ -type l -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//")
    local peer_site=$(find /etc/ceph/ -type f -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//")
    local peer_vip=$(echo $peer_site | cut -d"-" -f2)
    local sshcmd="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

    ceph_mirror_disable >/dev/null 2>&1

    if [ "x$peer_vip" = "x" ] ; then
        echo "already unpaired" && exit 0
    fi

    Quiet -n $sshcmd root@$peer_vip "$HEX_SDK ceph_mirror_disable"

    # Do these 2nd time if necessary
    if [ -n "$(rbd mirror pool status $BUILTIN_BACKPOOL 2>/dev/null)" -o -n "$(rbd mirror pool status glance-images 2>/dev/null)" ] ; then
        Quiet -n ceph_mirror_disable
        Quiet -n $sshcmd root@$peer_vip "$HEX_SDK ceph_mirror_disable"
    fi

    Quiet -n cubectl node exec -r control "systemctl stop ceph-rbd-mirror@${self_site}.service"
    Quiet -n $sshcmd root@$peer_vip cubectl node exec -pn -r control "systemctl stop ceph-rbd-mirror@${peer_site}.service"

    Quiet -n cubectl node exec -pn -r control rm -f /etc/ceph/${peer_site}.conf /etc/ceph/${self_site}.conf
    Quiet -n $sshcmd root@$peer_vip cubectl node exec -pn -r control "rm -f /etc/ceph/${peer_site}.conf /etc/ceph/${self_site}.conf"

    local mirror_dir=/var/lib/ceph/rbd-mirror
    Quiet -n cubectl node exec -pn -r control rm -rf $mirror_dir
    Quiet -n $sshcmd root@$peer_vip "cubectl node exec -pn -r control rm -rf $mirror_dir"
}

ceph_mirror_restart()
{
    local self_site=$(find /etc/ceph/ -type l -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//")
    local peer_site=$(find /etc/ceph/ -type f -name *-site.conf | sed  -e "s;.*/;;" -e "s/.conf//")
    local peer_vip=$(echo $peer_site | cut -d"-" -f2)
    local sshcmd="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

    Quiet -n cubectl node exec -r control systemctl restart ceph-rbd-mirror@$self_site
    Quiet -n $sshcmd root@${peer_vip:-emptyIp} "cubectl node exec -r control systemctl restart ceph-rbd-mirror@$peer_site"
}

ceph_fs_mds_init()
{
    $CEPH -s >/dev/null || Error "ceph quorum is not ready"
    Quiet -n ceph_mgr_module_enable stats
    if [ $(cubectl node list -r control | wc -l) -ge 3 ] ; then
        Quiet -n $CEPH fs set cephfs allow_standby_replay true
        Quiet -n $CEPH fs set cephfs session_timeout 30
        Quiet -n $CEPH fs set cephfs session_autoclose 30
        Quiet -n ceph_fs_mds_reorder
    fi
}

ceph_fs_mds_reorder()
{
    if [ ${#CUBE_NODE_CONTROL_HOSTNAMES[@]} -ge 3 ] ; then
        $CEPH -s >/dev/null || Error "ceph quorum is not ready"
        [ "x$($CEPH fs status -f json | jq -r '.mdsmap[] | select(.state == "standby-replay").name')" != "x" ] || return 0

        local mon_leader=$($CEPH mon stat -f json | jq -r ".leader")
        local mds_active=$($CEPH fs status -f json | jq -r '.mdsmap[] | select(.state == "active").name')
        local moderator=$(cubectl node list -j | jq -r '.[] | select(.role == "moderator").hostname')

        if [ "x$moderator" != "x" ] ; then
            if [ "x$moderator" = "x$mon_leader" ] ; then
                Quiet -n remote_run $moderator systemctl restart ceph-mon@$moderator
                sleep 15
                mon_leader=$($CEPH mon stat -f json | jq -r ".leader")
            fi
            Quiet -n $CEPH mds fail $moderator
            sleep 3
            mds_active=$($CEPH fs status -f json | jq -r '.mdsmap[] | select(.state == "active").name')
            for i in {1..5} ; do
                hot_standby=$($CEPH fs status -f json | jq -r '.mdsmap[] | select(.state == "standby-replay").name')
                if [ "x$hot_standby" != "x$moderator" ] ; then
                    Quiet -n $CEPH mds fail $hot_standby
                    sleep 3
                else
                    break
                fi
            done
        else
            for i in {1..5} ; do
                hot_standby=$($CEPH fs status -f json | jq -r '.mdsmap[] | select(.state == "standby-replay").name')
                if [ "x$hot_standby" = "x$mon_leader" ] ; then
                    Quiet -n $CEPH mds fail $hot_standby
                    sleep 3
                else
                    break
                fi
            done
        fi

        Quiet -n $CEPH mds fail $mds_active
    fi
}

ceph_nfs_ganesha()
{
    case $1 in
        enable)
            Quiet -n cubectl node exec -r control -p "systemctl unmask nfs-ganesha"
            Quiet -n cubectl node exec -r control -p "systemctl start nfs-ganesha"
            ;;
        disable)
            Quiet -n cubectl node exec -r control -p "systemctl stop nfs-ganesha"
            Quiet -n cubectl node exec -r control -p "systemctl mask nfs-ganesha"
            ;;
        *)
            echo "usage: ceph_nfs_ganesha enable|disable"
            ;;
    esac
}

ceph_pg_scrub()
{
    $CEPH health detail | grep 'not deep-scrubbed since' | awk '{print $2}' | while read pg ; do $CEPH pg deep-scrub $pg ; done
}

ceph_rbd_fsck()
{
    local svid=${1:-SERVER_ID}  # openstack server id
    local vlid=$($OPENSTACK server show $svid -f json | jq -r .attached_volumes[0].id)
    [ "x$vlid" != "xnull" ] || vlid=$svid

    for p in $BUILTIN_BACKPOOL $BUILTIN_EPHEMERAL $(ceph osd pool ls | grep "[-]pool$") ; do
        disk=$(rbd ls -p $p | grep $vlid | grep -v "[.]config$" | head -1)
        if [ "x$disk" != "x" ] ; then
            rbd=$p/$disk
            break
        fi
    done
    if rbd info $rbd >/dev/null ; then
        local mounted_rbd=$(rbd map $rbd 2>/dev/null)
        [ ! -e ${mounted_rbd}p1 ] || fsck -y ${mounted_rbd}p1
        Quiet -n rbd unmap $mounted_rbd
    fi
}

ceph_osd_set_bucket_host()
{
    local bucket=${1:-ephemeral}

    if $CEPH osd tree | grep -q "host $bucket" ; then
        for H in $(cubectl node list -j | jq -r .[].hostname) ; do
            for O in $($HEX_SDK remote_run $H "$HEX_SDK ceph_osd_list | head -2") ; do
                Quiet -n ceph osd crush set $O 1.0 root=$bucket host=${bucket}_${H}
            done
        done
    fi
}

ceph_osd_list()
{
    local osd_id=${1#osd.}
    local osd_ids=$osd_id
    if [ "x$osd_ids" = "x" ] ; then
        osd_ids=$($CEPH osd ls-tree $HOSTNAME 2>/dev/null)
    else
        $CEPH osd ls-tree $HOSTNAME 2>/dev/null | grep -q "^${osd_id}$" || return 0
    fi
    local hw_ls=$(lshw -class disk -json 2>/dev/null)
    local blkdevs=$(lsblk -J | jq -r .blockdevices[])
    local lvm=$(ceph-volume lvm list --format json)
    local valid_output="overall-health self-assessment test result:"
    local smart_supported="device has SMART capability"
    local smart_unavailable="Unavailable - device lacks SMART capability"
    local chk_attrs="Reallocated_Sector_Ct "
    chk_attrs+="Reported_Uncorrect "
    chk_attrs+="Command_Timeout "
    chk_attrs+="Current_Pending_Sector "
    chk_attrs+="Offline_Uncorrect "
    chk_attrs+="CRC_Error_Count"

    for osd_id in $osd_ids ; do
        dev=$(ceph_get_dev_by_id $osd_id)
        parent_dev=/dev/$(echo $blkdevs | jq -r ". | select(.children[].name == \"${dev#/dev/}\").name" 2>/dev/null)
        [ "$parent_dev" != "/dev/" ] || parent_dev=$dev
        smart_flg="-a"
        smart_log=$(smartctl $smart_flg $parent_dev)
        sn=$($HEX_SDK ceph_get_sn_by_dev $parent_dev)
        state=ok
        remark=
        encrypted=$(echo $lvm | jq -r ".[][] | select(.devices[] == \"$parent_dev\").tags.\"ceph.encrypted\"")

        if [ "x$encrypted" = "x1" ] ; then
            luks_ver=$(cryptsetup luksDump $(echo $lvm | jq -r ".[][] | select(.devices[] == \"$parent_dev\").lv_path") | grep -i version | awk '{print $2}')
            remark="LUKS${luks_ver}-encrypted,"
        fi
        if echo $smart_log | grep -q -i 'megaraid,N' ; then
            selected_dev=$(echo $hw_ls | jq -r ".[] | select(.logicalname == \"${parent_dev}\")")
            selected_dev_id=$(echo $selected_dev | jq -r .id | cut -d":" -f2)
            smart_flg+=" -d megaraid,${selected_dev_id}"
            smart_log=$(smartctl $smart_flg $parent_dev)
        fi

        if [ "$VERBOSE" = "1" ] ; then
            [ "x$encrypted" != "x1" ] || cryptsetup luksDump $(echo $lvm | jq -r ".[][] | select(.devices[] == \"$parent_dev\").lv_path")
            if echo $smart_log | grep -i -P -o "$valid_output .*? " ; then
                smartctl $smart_flg $parent_dev | grep 'ID.*RAW_VALUE' -A 100 | egrep 'prefailure warning|^$' -m1 -B100
            else
                smartctl $smart_flg $parent_dev
            fi
            hdsentinel -dev $parent_dev 2>/dev/null | sed 1,4d | grep -v -i "No actions needed"
            Quiet -n $CEPH osd df osd.$osd_id
            printf "%8s %8s %16s %10s %18s %10s %6s %s\n" "OSD" "STATE" "HOST" "DEV" "SERIAL" "POWER_ON" "USE" "REMARK"
        fi
        if echo $smart_log | grep -q -i "$valid_output PASSED" ; then
            SMART_JSON=$(smartctl $smart_flg $parent_dev -json)
            if [ "x$(echo $SMART_JSON | jq -r .ata_smart_attributes.table)" != "xnull" ] ; then
                for chk in $chk_attrs ; do
                    val=$(echo $SMART_JSON | jq -r ".ata_smart_attributes.table[] | select(.name == \"${chk}\").raw.value")
                    if [ ${val:-0} -ne 0 ] ; then
                        remark+="${chk}:${val},"
                        state=warning
                    fi
                done
            fi
        elif echo $smart_log | grep -q -i "$valid_output" ; then
            remark="did not pass self-assessment test"
            state=fail
        elif echo $smart_log | grep -q -i "$smart_supported" ; then
            remark="SMART supported but no self-test results"
            state=fail
        elif echo $smart_log | grep -q -i "$smart_unavailable" ; then
            remark="SMART not supported"
        else
            state=$($CEPH osd tree down -f json | jq -r ".nodes[] | select(.name == \"${osd_id}\").status")
            [ "x$state" = "xdown" ] || state=unknown
            remark="$(echo $smart_log | grep -o -i 'device lacks SMART capability')"
        fi

        power_on=$(hdsentinel -dev $parent_dev | grep -i "power on time" | cut -d":" -f2 | cut -d "," -f1 | head -1 | xargs)
        use=$(ceph osd df tree osd.$osd_id -f json | jq -r .summary.average_utilization)
        printf "%8s %8s %16s %10s %18s %10s %6s %s\n" $osd_id $state ${HOSTNAME%,} ${dev#/dev/} ${sn%,} "${power_on}" "${use%.*}%" "${remark%,}"
    done
}
