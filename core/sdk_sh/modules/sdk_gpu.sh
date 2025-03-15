# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ]; then
    echo "Error: PROG not set" >&2
    exit 1
fi

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

    health_cyborg_report

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
