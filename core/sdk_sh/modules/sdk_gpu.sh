# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ]; then
    echo "Error: PROG not set" >&2
    exit 1
fi

GPU_CONFIG_FILE_PATH="/etc/cube/cos/gpu/config.json"
SRIOV_PROFILE_NAME_REGEX="^[A-Za-z0-9]+-[0-9]+[A-Za-z]+$"
MIG_PROFILE_NAME_REGEX="^[A-Za-z0-9]+-[0-9]+-[0-9]+[A-Za-z]+$"

gpu_iommu_list()
{
    shopt -s nullglob
    output=

    for g in $(find /sys/kernel/iommu_groups/* -maxdepth 0 -type d 2>/dev/null | sort -V); do
        for d in $g/devices/*; do
            source $d/uevent
            # nvidia vender id: 10de
            if echo $PCI_ID | grep -iq "10de:"; then
                if [ "$VERBOSE" == "1" ]; then
                    drv=$(echo $DRIVER)
                    echo -e "IOMMU Group ${g##*/}: $(lspci -nns ${d##*/}) (driver: $drv)"
                else
                    pci_id=$(echo $PCI_ID | tr '[:upper:]' '[:lower:]')
                    if [ -n "$output" ]; then
                        if ! echo $output | grep -q $pci_id; then
                            output="$output,$pci_id"
                        fi
                    else
                        output=$pci_id
                    fi
                fi
            fi
        done
    done

    if [ "$VERBOSE" != "1" ]; then
        echo $output
    fi
}

gpu_is_installed()
{
    /usr/bin/nvidia-smi >/dev/null
}

gpu_vf_enable()
{
    local bus=${1:-ALL}

    $NVIDIA_SRIOV -e $bus

    # persist the change after reboot
    rm -f /etc/modprobe.d/gpu-vfio.conf

    for g in $(find /sys/kernel/iommu_groups/* -maxdepth 0 -type d 2>/dev/null | sort -V); do
        for d in $g/devices/*; do
            source $d/uevent
            # nvidia vender id: 10de
            if echo $PCI_ID | grep -iq "10de:"; then
                pci_id=$(echo $PCI_ID | tr '[:upper:]' '[:lower:]')
                echo "set device $pci_id at $PCI_SLOT_NAME driver to nvidia"
                echo $PCI_SLOT_NAME > /sys/bus/pci/drivers/$DRIVER/unbind 2>/dev/null
                echo $PCI_SLOT_NAME > /sys/bus/pci/drivers/nvidia/bind 2>/dev/null
            fi
        done
    done
}

gpu_vf_disable()
{
    local bus=${1:-ALL}

    $NVIDIA_SRIOV -d $bus

    # pci passthrough support
    modprobe vfio-pci

    # persist the change after reboot
    echo "options vfio-pci ids=$(gpu_iommu_list)" > /etc/modprobe.d/gpu-vfio.conf

    for g in $(find /sys/kernel/iommu_groups/* -maxdepth 0 -type d 2>/dev/null | sort -V); do
        for d in $g/devices/*; do
            source $d/uevent
            # nvidia vender id: 10de
            if echo $PCI_ID | grep -iq "10de:"; then
                pci_id=$(echo $PCI_ID | tr '[:upper:]' '[:lower:]')
                echo "set device $pci_id at $PCI_SLOT_NAME driver to vfio-pci"
                echo $PCI_SLOT_NAME > /sys/bus/pci/drivers/$DRIVER/unbind 2>/dev/null
                echo $PCI_SLOT_NAME > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null
            fi
        done
    done
}

gpu_service_config()
{
    if gpu_is_installed; then
        /usr/bin/systemctl start nvidia-vgpud
        /usr/bin/systemctl start nvidia-vgpu-mgr
    else
        /usr/bin/systemctl stop nvidia-vgpud
        /usr/bin/systemctl stop nvidia-vgpu-mgr
    fi
}

gpu_device_status()
{
    printf "+%11s+\n" | tr " " "-"
    printf "| %-9s |\n" "Node View"
    printf "+%11s+%39s\n" | tr " " "-"
    printf "\n"

    if /usr/bin/virt-host-validate | grep -q "IOMMU is enabled by kernel.*PASS"; then
        printf "IOMMU: on\n"
    else
        printf "IOMMU: off\n"
    fi
    printf "\n"

    printf "GPU IOMMU Group List\n"
    VERBOSE=1 gpu_iommu_list
    printf "\n"

    if gpu_is_installed; then
        $NVIDIA_SMI
        printf "\n"
        $NVIDIA_SMI vgpu
        printf "\n"
        $NVIDIA_SMI vgpu -m
        printf "\nVirtualization:\n"
        gpu_nova_type_show
        printf "\nSupported vGPU types:\n"
        VERBOSE=1 gpu_supported_type_list
    else
        echo "No Nvidia GPU managed by the host"
    fi
    printf "\n"

    printf "+%14s+\n" | tr " " "-"
    printf "| %-12s |\n" "Cluster View"
    printf "+%14s+%36s\n" | tr " " "-"
    printf "\n"

    hex_sdk -v -f none health_cyborg_report

    printf "\n"
}

gpu_nova_type_show()
{
    local type=$(grep enabled_vgpu_types /etc/nova/nova.conf | awk '{print $3}')
    if [ -n "$type" ]; then
        echo "Using vGPU type \"$type\""
    else
        echo "No vGPU type configured"
    fi
}

gpu_supported_type_list()
{
    for t in $($NVIDIA_SMI vgpu -s -v | grep "vGPU Type ID" | awk '{print $5}' | sort | uniq) ; do
        local type=$(echo $t | awk '{print "nvidia-" strtonum($0)}')
        if [ -z "$t" ]; then
            continue
        fi
        if [ "$VERBOSE" == "1" ]; then
            local desc=$($NVIDIA_SMI vgpu -s -v | grep $t -A 12 | head -n 13)
            local name=$(echo "$desc"| grep "Name" | awk '{ s = ""; for (i = 3; i <= NF; i++) s = s $i " "; print s }' | awk '{$1=$1;print}')
            local heads=$(echo "$desc"| grep "Display Heads" | awk '{ print $4 }')
            local frl=$(echo "$desc"| grep "Frame Rate Limit" | awk '{ print $5 }')
            local buffer=$(echo "$desc"| grep "FB Memory" | awk '{ print $4 "M" }')
            local max_x=$(echo "$desc"| grep "Maximum X Resolution" | awk '{ print $5 }')
            local max_y=$(echo "$desc"| grep "Maximum Y Resolution" | awk '{ print $5 }')
            local max_ins=$(echo "$desc"| grep "Max Instances" | awk '{ print $4 }')
            printf "type: %s, name: %s, spec: heads=%s, frame_rate_limit=%s, framebuffer=%s, max_resolution=%sx%s, max_instance=%s\n" "$type" "$name" "$heads" "$frl" "$buffer" "$max_x" "$max_y" "$max_ins"
        else
            echo $type
        fi
    done
}

gpu_default_type_get()
{
    $HEX_SDK gpu_supported_type_list | head -n 1
}

gpu_vm_stats()
{
    if ! gpu_is_installed; then
        return 0
    fi

    local vid=$1
    local stats=$($NVIDIA_SMI vgpu -q)

    for v in $(echo "$stats" | grep "VM UUID" | awk '{print $4}') ; do
        if [ -z "$v" ]; then
            continue
        elif [ -n "$vid" -a "$vid" != "$v" ]; then
            continue
        fi
        local vm_stats=$(echo "$stats" | grep "VM UUID.*$v" -A 29 -B 1)
        if [ "$FORMAT" == "line" ]; then
            local gid=$(echo "$vm_stats" | grep "vGPU ID" | awk '{print $4}')
            local name=$(echo "$vm_stats" | grep "vGPU Name" | cut -d' ' -f 32- | tr " " "-")
            local mem=$(echo "$vm_stats" | grep "FB Memory Usage" -A 3)
            local mem_total=$(echo "$mem" | grep Total | awk '{print $3}')
            local mem_used=$(echo "$mem" | grep Used | awk '{print $3}')
            local mem_free=$(echo "$mem" | grep Free | awk '{print $3}')
            local util=$(echo "$vm_stats" | grep Utilization -A 4)
            local util_gpu=$(echo "$util" | grep Gpu | awk '{print $3}')
            local util_mem=$(echo "$util" | grep Memory | awk '{print $3}')
            local util_encoder=$(echo "$util" | grep Encoder | awk '{print $3}')
            local util_decoder=$(echo "$util" | grep Decoder | awk '{print $3}')
            local encode=$(echo "$vm_stats" | grep "Encoder Stats" -A 3)
            local encode_sess=$(echo "$encode" | grep "Active Sessions" | awk '{print $4}')
            local encode_fps=$(echo "$encode" | grep "Average FPS" | awk '{print $4}')
            local encode_latency=$(echo "$encode" | grep "Average Latency" | awk '{print $4}')
            local fbc=$(echo "$vm_stats" | grep "FBC Stats" -A 3)
            local fbc_sess=$(echo "$fbc" | grep "Active Sessions" | awk '{print $4}')
            local fbc_fps=$(echo "$fbc" | grep "Average FPS" | awk '{print $4}')
            local fbc_latency=$(echo "$fbc" | grep "Average Latency" | awk '{print $4}')
            printf \
                "gpu.vm,gid=%s,name=%s,vm_uuid=%s \
mem_total=%s,mem_free=%s,mem_used=%s,\
util_gpu=%s,util_mem=%s,util_encoder=%s,util_decoder=%s,\
encode_sess=%s,encode_fps=%s,encode_latency=%s,\
fbc_sess=%s,fbc_fps=%s,fbc_latency=%s\n" \
                "$gid" "$name" "$v" "$mem_total" "$mem_free" "$mem_used" \
                "$util_gpu" "$util_mem" "$util_encoder" "$util_decoder" \
                "$encode_sess" "$encode_fps" "$encode_latency" \
                "$fbc_sess" "$fbc_fps" "$fbc_latency"
        else
            printf "%s\n\n" "$vm_stats"
        fi
    done
}

# Returns a stringified JSON array conforming to the following schema:
# {
#   id: string
#   name: string
#   type: "unset" | "pgpu" | "sriovVgpu" | "migBackedVgpu"
#   supportTypes: ("pgpu" | "sriovVgpu" | "migBackedVgpu")[]
#   pciAddress: string
#   profileCountLimit: number | null
#   status: "unassigned" | "idle" | "inUse"
#   allocation: {
#     current: number
#     total: number
#   } | null
# }[]
gpu_device_list()
{
    local gpu_config="[]"

    if [ -f "$GPU_CONFIG_FILE_PATH" ]; then
        local raw
        raw=$(cat "$GPU_CONFIG_FILE_PATH" 2>/dev/null)
        if echo "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
            gpu_config="$raw"
        fi
    else
        log_error "gpu_device_list: $GPU_CONFIG_FILE_PATH does not exist"
        return 1
    fi

    local gpu_csv
    gpu_csv=$($NVIDIA_SMI --query-gpu=uuid,name,pci.bus_id --format=csv,noheader,nounits 2>/dev/null)
    if [ -z "$gpu_csv" ]; then
        jq -c -n '[]'
        return 0
    fi

    local output="[]"

    while IFS=',' read -r uuid name pci_bus_id; do
        uuid=$(echo "$uuid" | xargs)
        name=$(echo "$name" | xargs)
        pci_bus_id=$(echo "$pci_bus_id" | xargs)

        local vgpu_support_out
        vgpu_support_out=$($NVIDIA_SMI vgpu -s -v -i "$pci_bus_id" 2>/dev/null)

        local profile_names
        profile_names=$(echo "$vgpu_support_out" | grep "Name" | awk '{print $NF}')

        local support_types='["pgpu"]'
        # SR-IOV profiles are named "<board> XX-YY" (e.g. "... DC-2B" and "DC-12Q")
        if echo "$profile_names" | grep -qE "$SRIOV_PROFILE_NAME_REGEX"; then
            support_types=$(echo "$support_types" | jq -c '. + ["sriovVgpu"]')
        fi

        # MIG-backed profiles are named "<board> XX-YY-ZZ" (e.g. "... DC-1-2Q" and "DC-4-96A")
        if echo "$profile_names" | grep -qE "$MIG_PROFILE_NAME_REGEX"; then
            support_types=$(echo "$support_types" | jq -c '. + ["migBackedVgpu"]')
        fi

        local gpu_type
        gpu_type=$(echo "$gpu_config" | jq -r --arg id "$uuid" \
            'map(select(.id == $id)) | if length > 0 then .[0].type else "" end')

        if [ -z "$gpu_type" ] || [ "$gpu_type" = "null" ]; then
            output=$(echo "$output" | jq -c \
                --arg id "$uuid" \
                --arg name "$name" \
                --arg pciAddress "$pci_bus_id" \
                --argjson supportTypes "$support_types" \
                '. + [{ id: $id, name: $name, type:"unset", supportTypes: $supportTypes, pciAddress: $pciAddress, profileCountLimit: null, status: "unassigned", allocation: null }]')
            continue
        fi

        local status="idle"
        local allocation
        local profile_count_limit="null"

        if [ "$gpu_type" = "pgpu" ]; then
            local pci_bus pci_slot
            pci_bus=$(echo "$pci_bus_id" | awk -F: '{print tolower($2)}')
            pci_slot=$(echo "$pci_bus_id" | awk -F: '{print $3}' | awk -F. '{print tolower($1)}')

            local in_use=0
            for vm_id in $(virsh list --state-running --uuid 2>/dev/null); do
                if virsh dumpxml "$vm_id" 2>/dev/null | \
                    grep -q "bus='0x${pci_bus}'.*slot='0x${pci_slot}'"; then
                    in_use=1
                    break
                fi
            done

            if [ "$in_use" = "1" ]; then
                status="inUse"
                allocation='{"current":1,"total":1}'
            else
                allocation='{"current":0,"total":1}'
            fi

        else
            local vgpu_out
            vgpu_out=$($NVIDIA_SMI vgpu -q -i "$pci_bus_id" 2>/dev/null || true)
            local current
            current=$(echo "$vgpu_out" | grep -c "vGPU ID" || true)
            current=${current:-0}

            local total
            total=$(echo "$gpu_config" | jq --arg id "$uuid" \
                '[map(select(.id == $id)) | .[0].profiles // [] | .[].count] | add // 0')

            if [ "${current}" -gt 0 ]; then
                status="inUse"
            fi

            allocation=$(jq -c -n \
                --argjson current "$current" \
                --argjson total "$total" \
                '{ current: $current, total: $total }')

            if [ "$gpu_type" = "sriovVgpu" ]; then
                local pci_sysfs
                pci_sysfs=$(echo "$pci_bus_id" | tr '[:upper:]' '[:lower:]' | cut -c5-)
                local totalvfs
                totalvfs=$(cat "/sys/bus/pci/devices/${pci_sysfs}/sriov_totalvfs" 2>/dev/null | tr -d '[:space:]')
                if echo "$totalvfs" | grep -qE '^[0-9]+$'; then
                    profile_count_limit="$totalvfs"
                fi
            fi

        fi

        output=$(echo "$output" | jq -c \
            --arg id "$uuid" \
            --arg name "$name" \
            --arg type "$gpu_type" \
            --argjson supportTypes "$support_types" \
            --arg pciAddress "$pci_bus_id" \
            --argjson profileCountLimit "$profile_count_limit" \
            --arg status "$status" \
            --argjson allocation "$allocation" \
            '. + [{id:$id, name:$name, type:$type, supportTypes:$supportTypes, pciAddress:$pciAddress, profileCountLimit:$profileCountLimit, status:$status, allocation:$allocation}]')
    done <<< "$gpu_csv"

    echo "$output"
}

# Returns a stringified JSON object conforming to the following schema:
# {
#   sriov: Profile[] | null
#   migBacked: Profile[] | null
# }
#
# where Profile is:
# {
#   id: number
#   name: string
#   vramMiB: number
#   count: number
#   alias: string | null
#   vmCountLimit: number | null
# }
gpu_vgpu_profile_list()
{
    local gpu_id="$1"

    if [ -z "$gpu_id" ]; then
        echo "Error: gpuId is required" >&2
        return 1
    fi

    local gpu_config="[]"

    if [ -f "$GPU_CONFIG_FILE_PATH" ]; then
        local raw
        raw=$(cat "$GPU_CONFIG_FILE_PATH" 2>/dev/null)
        if echo "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
            gpu_config="$raw"
        fi
    else
        log_error "gpu_vgpu_profile_list: $GPU_CONFIG_FILE_PATH does not exist"
        return 1
    fi

    local config_profiles
    config_profiles=$(echo "$gpu_config" | jq -c --arg id "$gpu_id" \
        'map(select(.id == $id)) | if length > 0 then (.[0].profiles // []) else [] end')

    # SR-IOV vGPU profiles
    local sriov_profiles="[]"

    # Maps a MIG GPU Instance Profile ID -> MIG-backed vGPU type name ("XX-YY-ZZ"),
    # used below to name the corresponding mig -lgip profile.
    local mig_profile_name_map="{}"

    local vgpu_output
    vgpu_output=$($NVIDIA_SMI vgpu -s -v -i "$gpu_id" 2>/dev/null)

    local vgpu_type_id_hex
    for vgpu_type_id_hex in $(echo "$vgpu_output" | grep "vGPU Type ID" | awk '{print $NF}'); do
        # `vgpu_type_id_hex` is a number in hex format (e.g. 0x619).
        # Convert it to a decimal number and store it in `decimal_id`.
        local decimal_id
        decimal_id=$(awk -v v="$vgpu_type_id_hex" 'BEGIN{print strtonum(v)}')

        local block profile_name fb_memory_mib gpu_instance_profile_id
        block=$(echo "$vgpu_output" | grep -A 20 "vGPU Type ID *: $vgpu_type_id_hex\$")
        # `Name                              : NVIDIA RTX Pro 6000 Blackwell DC-1-24Q`
        profile_name=$(echo "$block" | grep "Name" | head -1 | awk '{print $NF}')
        # `FB Memory                         : 24576 MiB`
        fb_memory_mib=$(echo "$block" | grep "FB Memory" | head -1 | awk '{print $4}')
        # `GPU Instance Profile ID           : 47`
        # This column is present only for MIG-backed vGPUs and does not exist for SR-IOV vGPUs.
        gpu_instance_profile_id=$(echo "$block" | grep "GPU Instance Profile ID" | head -1 | awk '{print $NF}')

        # MIG-backed vGPU types (name "XX-YY-ZZ") are already covered by the `mig -lgip` command below.
        # Record their name for later use and skip.
        if echo "$profile_name" | grep -qE "$MIG_PROFILE_NAME_REGEX"; then
            if [ -n "$gpu_instance_profile_id" ]; then
                mig_profile_name_map=$(echo "$mig_profile_name_map" | jq -c \
                    --arg id "$gpu_instance_profile_id" \
                    --arg name "$profile_name" \
                    '. + {($id): $name}')
            fi
            continue
        fi
        if ! echo "$profile_name" | grep -qE "$SRIOV_PROFILE_NAME_REGEX"; then
            # Unknown/unhandled profile name format.
            continue
        fi

        sriov_profiles=$(echo "$sriov_profiles" | jq -c \
            --argjson id "$decimal_id" \
            --arg name "$profile_name" \
            --argjson vram_mib "$fb_memory_mib" \
            '. + [{ id: $id, name: $name, vramMiB: $vram_mib, vmCountLimit: null }]')
    done

    # MIG GPU instance profiles
    local mig_profiles="[]"
    local mig_output
    mig_output=$($NVIDIA_SMI mig -lgip -i "$gpu_id" 2>/dev/null)

    while read -r _gpu_idx _mig_text profile_name profile_id instances memory_gib _rest; do
        [ -z "$profile_id" ] && continue

        local instances_total
        instances_total=${instances#*/}

        local vram_mib
        vram_mib=$(awk -v g="$memory_gib" 'BEGIN{printf "%.2f", g * 1024}')

        local name
        name=$(echo "$mig_profile_name_map" | jq -r \
            --arg id "$profile_id" \
            --arg fallback "MIG $profile_name" \
            '.[$id] // $fallback')

        mig_profiles=$(echo "$mig_profiles" | jq -c \
            --argjson id "$profile_id" \
            --arg name "$name" \
            --argjson vram "$vram_mib" \
            --argjson vmCountLimit "$instances_total" \
            '. + [{ id: $id, name: $name, vramMiB: $vram, vmCountLimit: $vmCountLimit }]')
    done <<< "$(echo "$mig_output" | grep -E '^\|\s+[0-9]+\s+MIG\s+[0-9]+g\.' | tr -d '|')"

    jq -c -n \
        --argjson sriovProfiles "$sriov_profiles" \
        --argjson migProfiles "$mig_profiles" \
        --argjson configProfiles "$config_profiles" \
        '
        def withCountAndAlias:
            map(. as $profile
                | (($configProfiles | map(select(.id == $profile.id)) | .[0]) // {}) as $configProfile
                | $profile + { count: ($configProfile.count // 0), alias: ($configProfile.alias // null) });

        { sriov: ($sriovProfiles | withCountAndAlias), migBacked: ($migProfiles | withCountAndAlias) }
        '
}

gpu_pgpu_attached_instance_get()
{
    local pci_address="$1"

    if [ -z "$pci_address" ]; then
        echo "Error: pciAddress is required" >&2
        return 1
    fi

    local pci_bus pci_slot
    pci_bus=$(echo "$pci_address" | awk -F: '{print tolower($2)}')
    pci_slot=$(echo "$pci_address" | awk -F: '{print $3}' | awk -F. '{print tolower($1)}')

    for vm_id in $(virsh list --state-running --uuid 2>/dev/null); do
        if virsh dumpxml "$vm_id" 2>/dev/null | \
            grep -q "bus='0x${pci_bus}'.*slot='0x${pci_slot}'"; then
            local vm_name
            vm_name=$(openstack server show "$vm_id" -f value -c name 2>/dev/null)
            if [ -n "$vm_name" ]; then
                jq -c -n --arg id "$vm_id" --arg name "$vm_name" '{id:$id, name:$name}'
                return 0
            fi
        fi
    done

    echo "null"
}

gpu_host_stats()
{
    if ! gpu_is_installed; then
        return 0
    fi

    local pciid=$1
    local stats=$($NVIDIA_SMI -q)

    for p in $(echo "$stats" | grep "^GPU" | awk '{print $2}') ; do
        if [ -z "$p" ]; then
            continue
        elif [ -n "$pciid" -a "$pciid" != "$p" ]; then
            continue
        fi
        local gpu_stats=$(echo "$stats" | grep "GPU $p" -A 197)
        if [ "$FORMAT" == "line" ]; then
            local name=$(echo "$gpu_stats" | grep "Product Name" | cut -d' ' -f 33- | tr " " "-")
            local mem=$(echo "$gpu_stats" | grep "FB Memory Usage" -A 4)
            local mem_total=$(echo "$mem" | grep Total | awk '{print $3}')
            local mem_used=$(echo "$mem" | grep Used | awk '{print $3}')
            local mem_free=$(echo "$mem" | grep Free | awk '{print $3}')
            local b1m=$(echo "$gpu_stats" | grep "BAR1 Memory Usage" -A 3)
            local b1m_total=$(echo "$b1m" | grep Total | awk '{print $3}')
            local b1m_used=$(echo "$b1m" | grep Used | awk '{print $3}')
            local b1m_free=$(echo "$b1m" | grep Free | awk '{print $3}')
            local util=$(echo "$gpu_stats" | grep Utilization -A 4)
            local util_gpu=$(echo "$util" | grep Gpu | awk '{print $3}')
            local util_mem=$(echo "$util" | grep Memory | awk '{print $3}')
            local util_encoder=$(echo "$util" | grep Encoder | awk '{print $3}')
            local util_decoder=$(echo "$util" | grep Decoder | awk '{print $3}')
            local encode=$(echo "$gpu_stats" | grep "Encoder Stats" -A 3)
            local encode_sess=$(echo "$encode" | grep "Active Sessions" | awk '{print $4}')
            local encode_fps=$(echo "$encode" | grep "Average FPS" | awk '{print $4}')
            local encode_latency=$(echo "$encode" | grep "Average Latency" | awk '{print $4}')
            local fbc=$(echo "$gpu_stats" | grep "FBC Stats" -A 3)
            local fbc_sess=$(echo "$fbc" | grep "Active Sessions" | awk '{print $4}')
            local fbc_fps=$(echo "$fbc" | grep "Average FPS" | awk '{print $4}')
            local fbc_latency=$(echo "$fbc" | grep "Average Latency" | awk '{print $4}')
            printf \
                "gpu.host,host=%s,name=%s,pciid=%s \
mem_total=%s,mem_free=%s,mem_used=%s,\
b1m_total=%s,b1m_free=%s,b1m_used=%s,\
util_gpu=%s,util_mem=%s,util_encoder=%s,util_decoder=%s,\
encode_sess=%s,encode_fps=%s,encode_latency=%s,\
fbc_sess=%s,fbc_fps=%s,fbc_latency=%s\n" \
                "$HOSTNAME" "$name" "$p" \
                "$mem_total" "$mem_free" "$mem_used" \
                "$b1m_total" "$b1m_free" "$b1m_used" \
                "$util_gpu" "$util_mem" "$util_encoder" "$util_decoder" \
                "$encode_sess" "$encode_fps" "$encode_latency" \
                "$fbc_sess" "$fbc_fps" "$fbc_latency"
        else
            printf "%s\n" "$HOSTNAME"
            printf "%s\n\n" "$gpu_stats"
        fi
    done
}
