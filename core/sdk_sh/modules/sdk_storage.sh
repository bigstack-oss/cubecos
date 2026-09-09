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
    sleep 10
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

# --- storage usage reporting -------------------------------------------------
# These functions live here rather than in their own sdk_storage_usage.sh
# because hex_sdk resolves a module by globbing sdk_<first-token>*.sh: a second
# file matching sdk_storage*.sh makes `[ -e f1 f2 ]` fail, silently pushing
# every storage_* call down the source-all-modules fallback.

# RBD pools CubeCOS creates. glance-images is shared overhead, never charged
# to a VM -- COW clones would otherwise double-count their parent.
STORAGE_USAGE_CEPH_POOLS="ephemeral-vms cinder-volumes glance-images k8s-volumes"

# Usage: $PROG storage_usage_ceph_disks
# One JSON object per line: provisioned vs allocated bytes per RBD image.
storage_usage_ceph_disks()
{
    local pool err kind stale

    err=$(mktemp /tmp/rbddu.XXXXXX)
    for pool in $STORAGE_USAGE_CEPH_POOLS ; do
        case $pool in
            ephemeral-vms) kind=ephemeral ;;
            glance-images) kind=image ;;
            *)             kind=volume ;;
        esac

        : > $err
        # librbd warns per image when the object map is invalid; used_size is
        # then a full scan or stale, so those report estimated rather than exact.
        stale=$(timeout -k 5 $SRVTO rbd du --format json -p $pool 2>$err >/tmp/rbddu.$$.json ; \
                sed -n 's|.*fast diff map is invalid for [^/]*/\([^.]*\)\..*|\1|p' $err | tr '\n' ',')
        jq -c --arg pool "$pool" --arg kind "$kind" --arg stale "$stale" '
          [ (.images // [])[] ] | group_by(.name) | .[] | . as $g | ($g[0].name) as $n |
          {
            scope: "disk",
            backend: "CubeStorage",
            backend_type: "ceph",
            pool: $pool,
            disk_id: $n,
            kind: $kind,
            provisioned_bytes: ([ $g[] | select(has("snapshot") | not) | .provisioned_size ] | first // 0),
            allocated_bytes:   ([ $g[] | select(has("snapshot") | not) | .used_size ]        | first // 0),
            snapshot_bytes:    ([ $g[] | select(has("snapshot"))       | .used_size ]        | add   // 0),
            confidence: (if ($stale | split(",") | index($n)) then "estimated" else "exact" end)
          }' /tmp/rbddu.$$.json 2>/dev/null
        rm -f /tmp/rbddu.$$.json
    done
    rm -f $err
}

# Usage: $PROG storage_usage_ceph_pools
# Logical vs raw bytes and compression ratio per pool. provisioned_bytes stays
# null -- ceph df has no such figure; the orchestrator sums it from disk rows.
storage_usage_ceph_pools()
{
    $CEPH df detail --format json 2>/dev/null | \
        jq -c --arg pools "$STORAGE_USAGE_CEPH_POOLS" '
          (.pools // [])[] | select(.name as $n | ($pools | split(" ") | index($n))) |
          {
            scope: "pool",
            backend: "CubeStorage",
            backend_type: "ceph",
            pool: .name,
            capacity_bytes: ((.stats.stored // 0) + (.stats.max_avail // 0)),
            stored_bytes: (.stats.stored // 0),
            raw_used_bytes: (.stats.bytes_used // 0),
            provisioned_bytes: null,
            replication_factor: (if (.stats.stored // 0) > 0
                                 then ((.stats.bytes_used / .stats.stored) | round) else null end),
            reduction_ratio: (if (.stats.compress_bytes_used // 0) > 0
                              then (.stats.compress_under_bytes / .stats.compress_bytes_used) else null end),
            confidence: (if (.stats.compress_bytes_used // 0) > 0 then "exact" else "unavailable" end)
          }'
}

# Usage: _storage_usage_os_maps
# {servers:{id:{name,project_id,project_name}}, volumes:{id:{project_id,project_name,server_id}}}
# Enumerated per project: neither volume list nor server list exposes the owning
# project at any --long level, and -c Project is silently dropped.
_storage_usage_os_maps()
{
    local projects pid pname sj vj servers volumes

    projects=$(timeout -k 5 $SRVTO openstack project list -f json 2>/dev/null || echo '[]')
    servers='{}' ; volumes='{}'

    while IFS='|' read -r pid pname ; do
        [ -n "$pid" ] || continue
        sj=$(timeout -k 5 $SRVTO openstack server list --project "$pid" -f json 2>/dev/null || echo '[]')
        vj=$(timeout -k 5 $SRVTO openstack volume list --project "$pid" -f json 2>/dev/null || echo '[]')
        servers=$(echo "$servers" | jq -c --argjson s "$sj" --arg pid "$pid" --arg pn "$pname" \
          '. + ($s | map({key: .ID, value: {name: .Name, project_id: $pid, project_name: $pn}}) | from_entries)')
        volumes=$(echo "$volumes" | jq -c --argjson v "$vj" --arg pid "$pid" --arg pn "$pname" \
          '. + ($v | map({key: .ID, value: {project_id: $pid, project_name: $pn,
                                            server_id: (.["Attached to"][0].server_id // null)}}) | from_entries)')
    done <<< "$(echo "$projects" | jq -r '.[] | "\(.ID)|\(.Name)"' 2>/dev/null)"

    jq -c -n --argjson s "$servers" --argjson v "$volumes" '{servers: $s, volumes: $v}'
}

# Usage: storage_usage_ceph_disks | $PROG storage_usage_attribute
# Adds instance_id/project_id/project_name/vm_name to disk rows, and
# project/vm names to guest rows (which already carry instance_id) -- the
# kapacitor alert message interpolates tenant and vm name and is useless
# without them. Pool rows pass through untouched.
storage_usage_attribute()
{
    local maps
    maps=$(_storage_usage_os_maps)

    jq -c --argjson m "$maps" '
      ($m.servers) as $s | ($m.volumes) as $v |
      if (.scope == "vm" or .scope == "fs") then
        (.instance_id) as $vm |
        . + { project_id: ($s[$vm].project_id // null),
              project_name: ($s[$vm].project_name // null),
              vm_name: ($s[$vm].name // null) }
      elif .scope != "disk" then .
      elif .kind == "image" then
        . + { instance_id: null, project_id: null, project_name: null, vm_name: null }
      elif .kind == "ephemeral" then
        (.disk_id | sub("_disk(\\..*)?$"; "")) as $vm |
        . + { instance_id: $vm, project_id: ($s[$vm].project_id // null),
              project_name: ($s[$vm].project_name // null), vm_name: ($s[$vm].name // null) }
      else
        (.disk_id | sub("^volume-"; "")) as $id |
        ($v[$id].server_id // null) as $vm |
        . + { instance_id: $vm, project_id: ($v[$id].project_id // null),
              project_name: ($v[$id].project_name // null),
              vm_name: (if $vm then ($s[$vm].name // null) else null end) }
      end'
}

# Filesystems below this never raise a disk alarm: a small always-full ESP is
# normal. Deliberately below /boot's typical size -- /boot is worth alarming on.
STORAGE_USAGE_FS_FLOOR=${STORAGE_USAGE_FS_FLOOR:-268435456}

# Usage: $PROG storage_usage_guest_disks
# In-guest filesystem usage via qemu-guest-agent, one parallel pass over compute
# nodes. domfsinfo carries no bytes; the raw guest-get-fsinfo reply does, and
# only on QEMU 5.2+ agents. The libvirt domain uuid is the nova instance uuid.
# Four confidence states, each needing a different fix: no_channel (image lacks
# hw_qemu_guest_agent), no_agent (absent, stopped, or still booting -- the
# channel reads disconnected for ~25s while udev starts qemu-ga),
# agent_too_old (pre-5.2, no byte fields), exact.
# Emits a summed scope=vm row for the GUI and a scope=fs row per filesystem for
# the alarm: a full 10G / beside an empty 500G /data sums to ~2%.
storage_usage_guest_disks()
{
    local uuid state json

    cmd -pv 'for u in $(virsh list --state-running --uuid 2>/dev/null) ; do
                 st=$(virsh dumpxml "$u" 2>/dev/null | sed -n "s/.*name=.org\.qemu\.guest_agent\.0. state=.\([a-z]*\).*/\1/p" | head -1)
                 if [ -z "$st" ] ; then echo "GUESTFS $u no_channel {}" ; continue ; fi
                 if [ "$st" != "connected" ] ; then echo "GUESTFS $u no_agent {}" ; continue ; fi
                 j=$(timeout 5 virsh qemu-agent-command "$u" "{\"execute\":\"guest-get-fsinfo\"}" 2>/dev/null) \
                     || { echo "GUESTFS $u no_agent {}" ; continue ; }
                 echo "GUESTFS $u ok $(echo "$j" | tr -d "\n")"
             done' 2>/dev/null \
        | cut -d"|" -f3- | sed -n 's/^GUESTFS //p' | \
    while read -r uuid state json ; do
        [ -n "$uuid" -a -n "$state" ] || continue
        if [ "$state" != "ok" ] ; then
            jq -c -n --arg vm "$uuid" --arg c "$state" '
              { scope: "vm", instance_id: $vm, guest_total_bytes: null,
                guest_used_bytes: null, fs_count: 0, confidence: $c }'
            continue
        fi
        echo "$json" | jq -c --arg vm "$uuid" --argjson floor "$STORAGE_USAGE_FS_FLOOR" '
          [ (.return // [])[]
            | select(.["total-bytes"] != null)
            | select((.type // "") | test("^(tmpfs|devtmpfs|squashfs|overlay|ramfs)$") | not) ]
          | unique_by(.name) as $fs |
          if ($fs | length) == 0 then
            { scope: "vm", instance_id: $vm, guest_total_bytes: null,
              guest_used_bytes: null, fs_count: 0, confidence: "agent_too_old" }
          else
            { scope: "vm", instance_id: $vm,
              guest_total_bytes: ([ $fs[] | .["total-bytes"] ] | add),
              guest_used_bytes:  ([ $fs[] | .["used-bytes"]  ] | add),
              fs_count: ($fs | length), confidence: "exact" },
            ( $fs[]
              | select(.["total-bytes"] >= $floor)
              | { scope: "fs", instance_id: $vm, mountpoint: .mountpoint, device: .name,
                  fs_total_bytes: .["total-bytes"], fs_used_bytes: .["used-bytes"],
                  used_percent: ((.["used-bytes"] * 100) / .["total-bytes"] | floor),
                  confidence: "exact" } )
          end' 2>/dev/null
    done
}

# Usage: $PROG storage_usage_nfs_disks
# NFS Cinder volumes are files on the share, so qemu-img gives the exact
# footprint. CubeCOS's builtin model uses sparse raw (nfs_qcow2_volumes=false,
# nfs_sparsed_volumes=true); qemu-img reports the sparse allocation either way.
# dedup_compress stays null -- these volumes are not compressed at all, and a
# 1.0 would read as "compression on, saving nothing".
# Cross-module reads go through $HEX_SDK: a bare cinder_get_storages call is a
# silent no-op, since hex_sdk sources only sdk_<first-token>*.sh.
storage_usage_nfs_disks()
{
    local storages name cfg shares mnt f info

    storages=$($HEX_SDK cinder_get_storages 2>/dev/null || echo '[]')
    for name in $(echo "$storages" | jq -r '.[] | select(.driver | test("nfs\\.NfsDriver$")) | .name' 2>/dev/null) ; do
        [ -n "$name" ] || continue
        cfg=$($HEX_SDK cinder_get_storage "{\"name\":\"$name\"}" 2>/dev/null | \
              jq -r '.storage.service.driverSection[]? | select(.key=="nfs_shares_config") | .value' 2>/dev/null)
        [ -n "$cfg" -a -f "$cfg" ] || continue

        # cinder mounts each share under its own hashed directory; find where
        shares=$(head -1 "$cfg" 2>/dev/null)
        [ -n "$shares" ] || continue
        mnt=$(findmnt -n -o TARGET --source "$shares" 2>/dev/null | head -1)
        [ -n "$mnt" -a -d "$mnt" ] || continue

        for f in "$mnt"/volume-* ; do
            [ -f "$f" ] || continue
            if info=$(timeout -k 5 $SRVTO qemu-img info --output=json "$f" 2>/dev/null) ; then
                echo "$info" | jq -c --arg b "$name" --arg p "$mnt" --arg d "$(basename "$f")" '
                  { scope: "disk", backend: $b, backend_type: "nfs", pool: $p, disk_id: $d,
                    kind: "volume",
                    provisioned_bytes: ."virtual-size", allocated_bytes: ."actual-size",
                    snapshot_bytes: 0, dedup_compress: null, confidence: "exact" }'
            else
                jq -c -n --arg b "$name" --arg p "$mnt" --arg d "$(basename "$f")" '
                  { scope: "disk", backend: $b, backend_type: "nfs", pool: $p, disk_id: $d,
                    kind: "volume",
                    provisioned_bytes: null, allocated_bytes: null,
                    snapshot_bytes: 0, dedup_compress: null, confidence: "unavailable" }'
            fi
        done
    done
}

# Usage: $PROG storage_usage_cinder_pools
# Pool capacity every Cinder driver already publishes, for backends with no
# adapter of their own -- so a mixed cluster still reports honest totals.
# The CLI returns a flattened summary, not the raw capabilities dict: Capacity
# and Allocated are GiB, and Allocated is allocated_capacity_gb (provisioned).
storage_usage_cinder_pools()
{
    timeout -k 5 $SRVTO openstack volume backend pool list --long -f json 2>/dev/null | \
        jq -c '
          .[] |
          (if (.Capacity | type) == "number" then (.Capacity * 1073741824 | floor) else null end) as $cap |
          (if (.Allocated | type) == "number" then (.Allocated * 1073741824 | floor) else null end) as $prov |
          {
            scope: "pool",
            backend: (.Name | split("#")[0] | split("@")[-1]),
            backend_type: "cinder",
            pool: .Name,
            protocol: (.Protocol // null),
            capacity_bytes: $cap,
            provisioned_bytes: $prov,
            thin: (if (.Thin | type) == "boolean" then .Thin else null end),
            max_over_subscription_ratio: (if (."Max Over Ratio" // "") == "" then null else ."Max Over Ratio" end),
            confidence: (if $cap == null then "unavailable" else "exact" end)
          }'
}

STORAGE_USAGE_LOCK=/run/cube_storage_usage.lock

# True when this node owns the VIP, or when there is no pacemaker at all (1cc).
# is_vip_active() cannot be used: it reports the resource Started anywhere in
# the cluster, which is true on every control node.
_storage_usage_is_vip_owner()
{
    local out
    out=$(timeout -k 5 $SRVSTO pcs resource status vip 2>/dev/null) || return 0
    echo "$out" | grep -q "Started $HOSTNAME\$"
}

# Escape an influx tag value: space, comma and equals are separators.
_storage_usage_esc()
{
    echo "$1" | sed -e 's/\\/\\\\/g' -e 's/ /\\ /g' -e 's/,/\\,/g' -e 's/=/\\=/g'
}

# Usage: <records on stdin> | _storage_usage_line <measurement>
# Influx line protocol. Null tags are omitted, never written as "null"; null
# fields are omitted rather than sent as 0, which would read as an empty disk.
_storage_usage_line()
{
    local m=$1 rec tags fields k v
    while read -r rec ; do
        [ -n "$rec" ] || continue
        tags="$m"
        for k in backend backend_type pool kind instance_id project_id project_name vm_name mountpoint confidence ; do
            v=$(echo "$rec" | jq -r --arg k "$k" '.[$k] // empty')
            [ -n "$v" ] && tags="$tags,$k=$(_storage_usage_esc "$v")"
        done
        fields=$(echo "$rec" | jq -r '
          [ (if .disk_id then "disk_id=\"\(.disk_id)\"" else empty end),
            (if .device then "device=\"\(.device)\"" else empty end),
            (if .provisioned_bytes != null then "provisioned_bytes=\(.provisioned_bytes)i" else empty end),
            (if .allocated_bytes != null then "allocated_bytes=\(.allocated_bytes)i" else empty end),
            (if .snapshot_bytes != null then "snapshot_bytes=\(.snapshot_bytes)i" else empty end),
            (if .capacity_bytes != null then "capacity_bytes=\(.capacity_bytes)i" else empty end),
            (if .stored_bytes != null then "stored_bytes=\(.stored_bytes)i" else empty end),
            (if .raw_used_bytes != null then "raw_used_bytes=\(.raw_used_bytes)i" else empty end),
            (if .free_bytes != null then "free_bytes=\(.free_bytes)i" else empty end),
            (if .guest_total_bytes != null then "guest_total_bytes=\(.guest_total_bytes)i" else empty end),
            (if .guest_used_bytes != null then "guest_used_bytes=\(.guest_used_bytes)i" else empty end),
            (if .fs_total_bytes != null then "fs_total_bytes=\(.fs_total_bytes)i" else empty end),
            (if .fs_used_bytes != null then "fs_used_bytes=\(.fs_used_bytes)i" else empty end),
            (if .fs_count != null then "fs_count=\(.fs_count)i" else empty end),
            (if .used_percent != null then "used_percent=\(.used_percent)i" else empty end),
            (if .replication_factor != null then "replication_factor=\(.replication_factor)i" else empty end),
            (if .reduction_ratio != null then "reduction_ratio=\(.reduction_ratio)" else empty end),
            (if .dedup_compress != null then "dedup_compress=\(.dedup_compress)" else empty end),
            (if .max_over_subscription_ratio != null then "max_over_subscription_ratio=\(.max_over_subscription_ratio|tonumber)" else empty end),
            (if (.allocated_bytes // 0) > 0 and (.provisioned_bytes // 0) > 0
               then "thin_ratio=\(.provisioned_bytes / .allocated_bytes)" else empty end)
          ] | join(",")')
        [ -n "$fields" ] && echo "$tags $fields"
    done
}

# Usage: <line protocol on stdin> | _storage_usage_influx_write <db>
# Posts to the Kapacitor write proxy, not to InfluxDB. Kapacitor's relay task
# copies one write out to the peer control nodes, and the same ingress is what
# feeds the stream tasks the VM alert templates are built on -- writing to
# InfluxDB directly reaches neither (cubecos#672), and is the bypass that left
# ceph metrics on a single node.
# The influx CLI is not an option either: `influx -execute "INSERT ..."` takes
# exactly ONE line of line protocol, so a batch writes only its first line.
_storage_usage_influx_write()
{
    local db=$1 body lp rc

    body=$(cat)
    [ -n "$body" ] || return 0

    lp=$(mktemp /tmp/su_lp.XXXXXX)
    echo "$body" > $lp

    $CURL -sf -X POST --data-binary @"$lp" \
        "http://$(shared_id):9092/write?db=$db&rp=def&precision=ns" >/dev/null 2>&1
    rc=$?
    [ $rc -eq 0 ] || Debug "storage usage: kapacitor write proxy rejected the batch (rc=$rc)"

    rm -f $lp
    return $rc
}

# Usage: $PROG storage_usage_collect
# Cron entry point. One writer per cluster; skips a run already in progress.
# Per-VM summaries and disk rows go to telegraf for the GUI; per-filesystem
# percentages carry the tags the VM alert templates interpolate. Everything
# lands in telegraf.def: monasca is retired (cubecos#672).
storage_usage_collect()
{
    _storage_usage_is_vip_owner || return 0
    mkdir "$STORAGE_USAGE_LOCK" 2>/dev/null || { Debug "storage usage collection already running" ; return 0 ; }

    local recs pools guest lines vmfs

    recs=$( { storage_usage_ceph_disks ; storage_usage_nfs_disks ; } | storage_usage_attribute )
    guest=$(storage_usage_guest_disks | storage_usage_attribute)

    # ceph df carries no provisioned figure, so sum it from the disk rows
    # rather than paying a second rbd du pass.
    pools=$( { storage_usage_ceph_pools ; storage_usage_cinder_pools ; } | \
             jq -c --argjson d "$(echo "$recs" | jq -s -c '.')" '
               . as $p |
               if .provisioned_bytes == null then
                 .provisioned_bytes = ([ $d[] | select(.pool == $p.pool) | .provisioned_bytes // 0 ] | add // 0)
               else . end' )

    lines=$( { echo "$recs"  | _storage_usage_line storage_usage ;
               echo "$pools" | _storage_usage_line storage_pool_usage ;
               echo "$guest" | jq -c 'select(.scope == "vm")' | _storage_usage_line storage_usage_guest ; } | grep .)
    [ -n "$lines" ] && echo "$lines" | _storage_usage_influx_write "$TELEGRAF_DB"

    # the VM alert templates stream these from telegraf.def
    vmfs=$(echo "$guest" | jq -c 'select(.scope == "fs")' | while read -r r ; do
        [ -n "$r" ] || continue
        echo "vm.disk.usage_perc,resource_id=$(_storage_usage_esc "$(echo "$r" | jq -r .instance_id)")\
,mountpoint=$(_storage_usage_esc "$(echo "$r" | jq -r .mountpoint)")\
,device=$(_storage_usage_esc "$(echo "$r" | jq -r '.device // "-"')")\
,tenant_id=$(_storage_usage_esc "$(echo "$r" | jq -r '.project_id // "-"')")\
,tenant_name=$(_storage_usage_esc "$(echo "$r" | jq -r '.project_name // "-"')")\
,vm_name=$(_storage_usage_esc "$(echo "$r" | jq -r '.vm_name // "-"')")\
 value=$(echo "$r" | jq -r .used_percent)i"
    done)
    [ -n "$vmfs" ] && echo "$vmfs" | _storage_usage_influx_write "$TELEGRAF_DB"

    echo "$pools" | storage_usage_thresholds

    rmdir "$STORAGE_USAGE_LOCK" 2>/dev/null
}

STORAGE_USAGE_STATE=/var/lib/cube/storage_usage_thresholds
STORAGE_USAGE_ENV=${STORAGE_USAGE_ENV:-/etc/cube/cos/storage_usage.env}
STORAGE_USAGE_HEX_LOG_EVENT=/usr/sbin/hex_log_event

# Usage: <pool records on stdin> | $PROG storage_usage_thresholds
# Fires on a threshold crossing only; re-arms 5 points below soft. Fullness and
# over-subscription are separate alarms: a pool 60% full with 4x provisioned is
# the one that ends in an outage, and no used_percent threshold catches it.
storage_usage_thresholds()
{
    # hex_config writes the tuned thresholds here, so the cron run, the CLI and
    # hex_config cannot disagree about them
    [ -f $STORAGE_USAGE_ENV ] && . $STORAGE_USAGE_ENV

    local soft=${STORAGE_USAGE_SOFT:-75} hard=${STORAGE_USAGE_HARD:-85}
    local oversub=${STORAGE_USAGE_OVERSUB_WARN:-2.0}
    local rec backend pool cap used prov pct ratio key prev now code

    mkdir -p $(dirname $STORAGE_USAGE_STATE) 2>/dev/null
    touch $STORAGE_USAGE_STATE
    now=$(mktemp)

    while read -r rec ; do
        [ -n "$rec" ] || continue
        backend=$(echo "$rec" | jq -r '.backend // empty')
        pool=$(echo "$rec" | jq -r '.pool // empty')
        cap=$(echo "$rec" | jq -r '.capacity_bytes // 0')
        used=$(echo "$rec" | jq -r '.raw_used_bytes // 0')
        prov=$(echo "$rec" | jq -r '.provisioned_bytes // 0')
        [ -n "$backend" -a -n "$pool" ] || continue
        [ "$cap" -gt 0 ] 2>/dev/null || continue

        pct=$(( used * 100 / cap ))
        ratio=$(echo "$prov $cap" | awk '{printf "%.2f", $1/$2}')
        key="$backend/$pool"
        prev=$(grep -F "$key=" $STORAGE_USAGE_STATE | cut -d= -f2)

        if   [ $pct -ge $hard ] ; then code=hard
        elif [ $pct -ge $soft ] ; then code=soft
        elif [ $pct -lt $(( soft - 5 )) ] ; then code=clear
        else code=${prev:-clear} ; fi

        if [ "$code" != "${prev:-clear}" ] ; then
            case $code in
                soft)  $STORAGE_USAGE_HEX_LOG_EVENT -e STO00001W "interface=system,host=$HOSTNAME,category=storage,sub=capacity,action=threshold,level=soft,backend=$backend,pool=$pool,used_percent=$pct,provisioned_ratio=$ratio" ;;
                hard)  $STORAGE_USAGE_HEX_LOG_EVENT -e STO00002E "interface=system,host=$HOSTNAME,category=storage,sub=capacity,action=threshold,level=hard,backend=$backend,pool=$pool,used_percent=$pct,provisioned_ratio=$ratio" ;;
                clear) $STORAGE_USAGE_HEX_LOG_EVENT -e STO00003I "interface=system,host=$HOSTNAME,category=storage,sub=capacity,action=cleared,backend=$backend,pool=$pool,used_percent=$pct" ;;
            esac
        fi
        echo "$key=$code" >> $now

        if [ "$(echo "$ratio $oversub" | awk '{print ($1 >= $2)}')" = "1" ] ; then
            grep -qF "$key.oversub=1" $STORAGE_USAGE_STATE || \
                $STORAGE_USAGE_HEX_LOG_EVENT -e STO00004W "interface=system,host=$HOSTNAME,category=storage,sub=capacity,action=oversubscribed,backend=$backend,pool=$pool,used_percent=$pct,provisioned_ratio=$ratio"
            echo "$key.oversub=1" >> $now
        fi
    done

    mv -f $now $STORAGE_USAGE_STATE
}

# Usage: _storage_usage_query <db> <influxql>
# Reads over HTTP so the same path serves both the CLI and any other consumer;
# the influx CLI's tabular output is not machine-parseable.
_storage_usage_query()
{
    local db=$1 q=$2
    timeout -k 5 $SRVTO curl -s -G "http://localhost:8086/query" \
        --data-urlencode "db=$db" --data-urlencode "q=$q" 2>/dev/null
}

# Usage: $PROG storage_usage_get [<instance_id>]
# Reads stored samples, never collects live, so the CLI and the GUI cannot
# disagree. Always reports sample age: a 15-minute sampler with no timestamp
# reads as a broken feature. Honours -f json.
storage_usage_get()
{
    local vm=${1:-} pools disks guest

    if [ -z "$vm" ] ; then
        pools=$(_storage_usage_query "$TELEGRAF_DB" \
          'select last(raw_used_bytes), stored_bytes, capacity_bytes, provisioned_bytes, replication_factor, reduction_ratio from storage_pool_usage group by backend, pool')
        if [ "x$FORMAT" = "xjson" ] ; then
            echo "$pools" | jq -c '[ (.results[0].series // [])[] | . as $s |
              ([$s.columns, $s.values[0]] | transpose | map({(.[0]): .[1]}) | add) as $r |
              { backend: $s.tags.backend, pool: $s.tags.pool,
                rawUsedBytes: $r.last, storedBytes: $r.stored_bytes,
                capacityBytes: $r.capacity_bytes, provisionedBytes: $r.provisioned_bytes,
                replicationFactor: $r.replication_factor, reductionRatio: $r.reduction_ratio,
                thinRatio: (if ($r.stored_bytes // 0) > 0 and ($r.provisioned_bytes // 0) > 0
                            then (($r.provisioned_bytes / $r.stored_bytes) * 100 | round / 100) else null end),
                sampledAt: $r.time } ]'
        else
            echo "$pools" | jq -r '(.results[0].series // [])[] | . as $s |
              ([$s.columns, $s.values[0]] | transpose | map({(.[0]): .[1]}) | add) as $r |
              "\($s.tags.backend)/\($s.tags.pool)  stored=\($r.stored_bytes)  raw=\($r.last)  capacity=\($r.capacity_bytes)  provisioned=\($r.provisioned_bytes)  repl=\($r.replication_factor // "-")  reduction=\($r.reduction_ratio // "n/a")  sampled=\($r.time)"'
        fi
        return 0
    fi

    disks=$(_storage_usage_query "$TELEGRAF_DB" \
      "select last(allocated_bytes), provisioned_bytes, snapshot_bytes from storage_usage where instance_id = '$vm' group by pool, kind")
    guest=$(_storage_usage_query "$TELEGRAF_DB" \
      "select last(guest_used_bytes), guest_total_bytes, fs_count from storage_usage_guest where instance_id = '$vm'")

    if [ "x$FORMAT" = "xjson" ] ; then
        jq -c -n --argjson d "$disks" --argjson g "$guest" --arg vm "$vm" '
          { instanceId: $vm,
            disks: [ ($d.results[0].series // [])[] | . as $s |
                     ([$s.columns, $s.values[0]] | transpose | map({(.[0]): .[1]}) | add) as $r |
                     { pool: $s.tags.pool, kind: $s.tags.kind, allocatedBytes: $r.last,
                       provisionedBytes: $r.provisioned_bytes, snapshotBytes: $r.snapshot_bytes,
                       sampledAt: $r.time } ],
            guest: ( ($g.results[0].series // [])[0] | if . then . as $s |
                     ([$s.columns, $s.values[0]] | transpose | map({(.[0]): .[1]}) | add) as $r |
                     { usedBytes: $r.last, totalBytes: $r.guest_total_bytes,
                       fsCount: $r.fs_count, sampledAt: $r.time } else null end ) }'
    else
        echo "$disks" | jq -r '(.results[0].series // [])[] | . as $s |
          ([$s.columns, $s.values[0]] | transpose | map({(.[0]): .[1]}) | add) as $r |
          "\($s.tags.pool)/\($s.tags.kind)  provisioned=\($r.provisioned_bytes)  allocated=\($r.last)  snapshots=\($r.snapshot_bytes)  sampled=\($r.time)"'
        echo "$guest" | jq -r '(.results[0].series // [])[0] | if . then . as $s |
          ([$s.columns, $s.values[0]] | transpose | map({(.[0]): .[1]}) | add) as $r |
          "guest-fs  used=\($r.last)  total=\($r.guest_total_bytes)  filesystems=\($r.fs_count)  sampled=\($r.time)"
          else "guest-fs  no agent data" end'
    fi
}
