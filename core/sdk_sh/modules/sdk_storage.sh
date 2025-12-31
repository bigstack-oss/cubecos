# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

storage_update_device_maps()
{
    _hex_function_ret /usr/sbin/multipath -r
}

storage_update_partition_table()
{
    _hex_function_ret /usr/sbin/partprobe
}

storage_is_valid_block_device()
{
    # check if the device is a valid block device
    local device="${1:-""}"
    if [ -z "$device" ] ; then
        return 1
    fi

    if ! _hex_function_ret /usr/bin/lsblk "$device" ; then
        # not a valid block device
        return 1
    fi

    return 0
}

storage_is_das()
{
    # check if the device is a direct-attached storage, DAS
    local device="${1:-""}"
    if [ -z "$device" ] ; then
        return 1
    fi

    local exec_output=""
    local exec_error=""

    # test if mpath devices
    if ! _hex_function exec_output exec_error /usr/bin/lsblk -ln -o TYPE "$device" ; then
        # error, might not be a proper block device
        return 1
    fi

    local type=""
    while read -r type ; do
        if [[ "$type" == "mpath" ]] ; then
            # mpath devices are not DAS
            return 1
        fi
    done <<< "$exec_output"

    # test if fc devices
    if [[ "$(/usr/bin/lsblk -dn -o TRAN "$device")" == "fc" ]] ; then
        return 1
    fi

    # test if iscsi devices
    if [[ "$(/usr/bin/lsblk -dn -o TRAN "$device")" == "iscsi" ]] ; then
        return 1
    fi

    return 0
}

storage_update_partition_label_links()
{
    # update partition label links based on partlabel
    local label_pth="/dev/disk/by-partlabel"
    if [ ! -e $label_pth ] ; then
        log_error "disk label links /dev/disk/by-partlabel not found"
        return 1
    fi

    # force clean up old links
    if ! _hex_function_ret rm /dev/disk/by-partlabel/* ; then
        log_error "failed to cleanup old disk label links"
        return 1
    fi
    if ! storage_update_partition_table ; then
        log_error "failed to sync disk label links from the kernel"
        return 1
    fi

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

    for prefix in $prefixes ; do
        for slink in $(find "$label_pth" -type l -name "*${prefix}*" | sort) ; do
            part_pth=$(readlink -e $slink)
            part=${part_pth#/dev/}
            disk=$(lsblk -s -r -n -o NAME,TYPE "$part_pth" | grep "disk" | cut -d' ' -f1 | sort -u)

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
}

storage_list_all_disks()
{
    # list all nvme* and sd* on the system

    # force rescans of SCSI buses
    for host in /sys/class/scsi_host/* ; do
        if [ -e $host/rescan ] ; then
            echo "- - -" > $host/rescan
        elif [ -e $host/scan ] ; then
            echo "- - -" > $host/scan
        fi
    done

    # collect disk device names
    local nvmes=$(ls /dev/nvme* 2>/dev/null| grep -oe '/dev/nvme[0-9]\+n[0-9]\+$')
    local ssds=$(ls /dev/sd* 2>/dev/null| grep -oe '/dev/sd[a-z]\+$')

    local disks=
    for d in $nvmes $ssds ; do
        if lsblk -nd | grep -q "${d#/dev/}" ; then
            disks+="$d "
        fi
    done
    echo -n ${disks%% }
}

storage_list_available_disks()
{
    # list all free disks for Ceph OSD
    local disks_mounted=
    for d in $(storage_list_all_disks) ; do
        local available=true
        for b in $(ListMountedDisks) ; do
            if [ "x${d}" = "x${b}" ] ; then
                available=false
                break
            fi
        done
        [ "$available" = "false" ] || disks_available+="$d "
    done

    echo -n ${disks_available%% }
}
