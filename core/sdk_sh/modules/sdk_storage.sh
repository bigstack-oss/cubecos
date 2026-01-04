# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

STORAGE_FORCE_TO_USE_MPATH_DEVICES="/etc/cube/cos/ceph/force_to_use_mpath_devices"

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

storage_is_mpath()
{
    # check if the device is a mpath device
    local device="${1:-""}"
    if [ -z "$device" ] ; then
        return 1
    fi

    local exec_output=""
    local exec_error=""
    if ! _hex_function exec_output exec_error /usr/bin/lsblk -ln -o TYPE "$device" ; then
        # error, might not be a proper block device
        return 1
    fi

    local type=""
    while read -r type ; do
        if [[ "$type" == "mpath" ]] ; then
            return 0
        fi
    done <<< "$exec_output"

    return 1
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

    # test if mpath devices, mpath devices are not DAS
    if storage_is_mpath "$device" ; then
        return 1
    fi

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

storage_set_force_use_mpath_devices_for_ceph()
{
    if [ -f "$STORAGE_FORCE_TO_USE_MPATH_DEVICES" ] ; then
        return 0
    fi

    touch "$STORAGE_FORCE_TO_USE_MPATH_DEVICES"
}

storage_unset_force_use_mpath_devices_for_ceph()
{
    if [ ! -f "$STORAGE_FORCE_TO_USE_MPATH_DEVICES" ] ; then
        return 0
    fi

    rm -f "$STORAGE_FORCE_TO_USE_MPATH_DEVICES"
}

storage_are_mpath_devices_allowed_for_ceph()
{
    if [ -f "$STORAGE_FORCE_TO_USE_MPATH_DEVICES" ] ; then
        return 0
    fi

    # check if external storages are set on controls from the control node holding the vip
    if _hex_function_ret remote_run "$(shared_id)" "${HEX_SDK} cinder_is_storage_set" ; then
        return 1
    fi

    return 0
}

storage_list_all_disks()
{
    # list all nvme* and sd* on the system
    # output format: "/dev/sda /dev/sdb /dev/sdc"

    storage_update_device_maps

    # force rescans of SCSI buses
    for host in /sys/class/scsi_host/* ; do
        if [ -e $host/rescan ] ; then
            echo "- - -" > $host/rescan
        elif [ -e $host/scan ] ; then
            echo "- - -" > $host/scan
        fi
    done

    # collect disk device names
    local disks=""
    local block_dev=""
    for block_dev in /sys/block/sd* /sys/block/nvme* ; do
        # skip non-existing links
        if [[ "$block_dev" == "/sys/block/sd*" ]] ; then
            continue
        fi
        if [[ "$block_dev" == "/sys/block/nvme*" ]] ; then
            continue
        fi

        local device_basename="$(/usr/bin/basename "$block_dev")"
        local device="/dev/${device_basename}"

        # test if mpath devices, if so, skip it
        if storage_is_mpath "$device" ; then
            continue
        fi

        # exclude non-block devices
        if [[ "$(/bin/lsblk -dn -o TYPE "$device")" != "disk" ]] ; then
            continue
        fi

        # exclude not writable devices
        if [[ "$(/bin/lsblk -dn -o RO "$device")" =~ "1" ]] ; then
            continue
        fi

        # exclude zero size devices
        if [[ "$(/bin/lsblk -dn -o SIZE "$device")" == " 0B" ]] ; then
            continue
        fi

        # ensure the device is a block device
        if [ ! -b "$device" ] ; then
            continue
        fi

        disks+="$device "
    done

    # If external storage is set for Cinder volume driver,
    # disable mpath device support for Ceph unless we use the marker file to force it.
    if ! storage_are_mpath_devices_allowed_for_ceph ; then
        echo -n ${disks%% }
        return 0
    fi

    # collect mapper devices
    local mpath_dev=""
    for mpath_dev in /dev/mapper/* ; do
        # skip non-existing links
        if [[ "$block_dev" == "/dev/mapper/*" ]] ; then
            continue
        fi

        # a mapper device must be a symbolic link
        if [ ! -L "$mpath_dev" ] ; then
            continue
        fi

        # exclude partitions
        if [[ "$(/bin/lsblk -dn -o TYPE "$mpath_dev")" != "mpath" ]] ; then
            continue
        fi

        disks+="$mpath_dev "
    done

    echo -n ${disks%% }
}

storage_list_mounted_disks()
{
    # list all mounted (in-use) disks
    # output format: "/dev/sda /dev/sdb /dev/sdc"
    local disks=""

    # first, find all mounted disks for normal file systems
    local mounted_devices="$(grep /dev/ /proc/mounts | awk '{ print $1; }' | grep "/dev/.*")"
    local device=""
    local device_basename=""
    local disk_name=""
    while read -r device ; do
        device_basename="$(/usr/bin/basename "$device")"
        if [[ ! $device_basename =~ ^(sd|nvme) ]]; then
            # we are only interested in SCSI disks or NVME disks
            continue
        fi

        disk_name="$(/bin/lsblk -n -o PKNAME "$device")"
        if [ -z "$disk_name" ] ; then
            continue
        fi

        disks+="/dev/${disk_name} "
    done <<< "$mounted_devices"

    # second, find all mounted disks for LVM
    local lvms=$(ceph-volume lvm list --format json | jq -r ".[][].devices[]" | sort | uniq)
    local lvm=""
    for lvm in $lvms ; do
        disks+="$lvm "
    done

    # use awk to pick unique disks only
    disks="$(echo "$disks" | awk '{for(i=1;i<=NF;i++) if(!a[$i]++) printf "%s%s", $i, (i==NF?ORS:OFS)}')"
    echo -n ${disks%% }
}

storage_list_available_disks()
{
    # list all free disks for Ceph OSD
    local disks_mounted=""
    local available=""
    for d in $(storage_list_all_disks) ; do
        available=true
        for b in $(storage_list_mounted_disks) ; do
            if [ "x${d}" = "x${b}" ] ; then
                available=false
                break
            fi
        done
        [ "$available" = "false" ] || disks_available+="$d "
    done

    echo -n ${disks_available%% }
}
