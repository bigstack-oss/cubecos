# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ]; then
    echo "Error: PROG not set" >&2
    exit 1
fi

GPU_CONFIG_FILE_PATH="/etc/cube/cos/gpu/config.json"
SRIOV_PROFILE_NAME_REGEX="^[A-Za-z0-9]+-[0-9]+[A-Za-z]+$"
MIG_PROFILE_NAME_REGEX="^[A-Za-z0-9]+-[0-9]+-[0-9]+[A-Za-z]+$"

# Static vGPU type table shipped with the NVIDIA vGPU host driver, keyed by PCI
# device id. It answers the same question `nvidia-smi vgpu -s -v` does, and is
# needed because a pgpu is bound to vfio-pci and therefore invisible to
# nvidia-smi while its PCI ids stay readable in sysfs. Absent when no vGPU host
# driver is installed - in which case the card genuinely cannot run vGPU and
# reporting pgpu-only is the correct answer.
VGPU_CONFIG_XML="/usr/share/nvidia/vgpu/vgpuConfig.xml"

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

# Slices `nvidia-smi -q` / `nvidia-smi vgpu -q` (on stdin) into whole records and
# prints those containing $2, for the human-readable (non-line) output format.
# A record runs from its header line to the next line at or above the header's
# indent, so unlike a fixed `grep -A <n>` window it is never truncated and never
# bleeds into the next record. Matching on the record body rather than on a
# parsed id keeps both callers' filters working: a pciid appears in the GPU
# header, a VM UUID inside the vGPU record.
#   $1  record header regex   $2  substring filter (empty = all)   $3  prefix line
gpu_stats_record()
{
    awk -v root_re="$1" -v want="$2" -v prefix="$3" '
    function emit(   ) {
        if (buf != "" && (want == "" || index(buf, want))) {
            if (prefix != "") printf "%s\n", prefix
            printf "%s\n\n", buf
        }
        buf = ""
    }
    $0 ~ root_re { emit(); root_ind = match($0, /[^ ]/) - 1; buf = $0; next }
    buf != "" {
        if ($0 !~ /^[ \t]*$/ && match($0, /[^ \t]/) - 1 <= root_ind) { emit(); next }
        buf = buf "\n" $0
    }
    END { emit() }'
}

# Turns `nvidia-smi -q` / `nvidia-smi vgpu -q` (on stdin) into InfluxDB line
# protocol, one line per GPU (mode "host") or per vGPU instance (mode "vm").
#
# nvidia-smi prints a human-readable tree, so every field has to be located by
# some anchor. Three are stacked here, each covering what the others cannot:
#
#   1. Record boundary - an unindented `GPU <pciid>` / a `vGPU ID` line. Every
#      record is parsed, validated and printed on its own, so a card whose data
#      is unusable can never take the other cards (or the whole batch) down with
#      it. Telegraf's parser aborts the *entire* exec output on the first bad
#      line, which is how one MIG-enabled card used to blank out a node's GPU
#      panels completely (confirmed on cn13, 2026-08-07).
#
#   2. Path tail match, shallowest wins. Leaf names repeat all over the output
#      (`Total`, `Used`, `Free`, `Active Sessions`), and whole sections repeat
#      too: a MIG-enabled card carries a nested `MIG Device/FB Memory Usage`
#      whose Total is the GPU instance's framebuffer, not the card's. Matching
#      the path tail (`FB Memory Usage/Total`) finds the field even if nvidia-smi
#      wraps the tree in another level, and preferring the shallowest match keeps
#      the nested MIG copy from winning. Paths come from a running indent stack,
#      so no indent width (4/8/12) is assumed anywhere.
#
#   3. Unit check. Memory must read MiB, utilization %, counters no unit at all.
#      Without this a future nvidia-smi switching to GiB would be recorded as if
#      it were MiB - a silently wrong value, which is worse than a missing one.
#
# Anything that fails a check is dropped as a single field (never written as
# `key=N/A`, which is not valid line protocol) and reported on stderr naming the
# exact path, so a format change shows up in the telegraf log instead of as a
# blank dashboard.
#   $1  mode: host|vm      $2  id filter (empty = all)
gpu_stats_parse()
{
    local mode=$1
    local want=$2
    local spec order root_re

    # nvidia-smi has printed the utilization leaf both ways: the collector was
    # originally written against "Gpu" and lost util_gpu entirely once a driver
    # started printing "GPU" (c85db777). Both spellings map to the same field so
    # that neither generation of the output silently drops the metric.
    if [ "$mode" = "host" ]; then
        root_re='^GPU [0-9A-Fa-f]'
        order='mem_total,mem_free,mem_used,b1m_total,b1m_free,b1m_used,util_gpu,util_mem,util_encoder,util_decoder,encode_sess,encode_fps,encode_latency,fbc_sess,fbc_fps,fbc_latency'
        spec='FB Memory Usage/Total|mem_total|MiB
FB Memory Usage/Free|mem_free|MiB
FB Memory Usage/Used|mem_used|MiB
BAR1 Memory Usage/Total|b1m_total|MiB
BAR1 Memory Usage/Free|b1m_free|MiB
BAR1 Memory Usage/Used|b1m_used|MiB
Utilization/GPU|util_gpu|%
Utilization/Gpu|util_gpu|%
Utilization/Memory|util_mem|%
Utilization/Encoder|util_encoder|%
Utilization/Decoder|util_decoder|%
Encoder Stats/Active Sessions|encode_sess|
Encoder Stats/Average FPS|encode_fps|
Encoder Stats/Average Latency|encode_latency|
FBC Stats/Active Sessions|fbc_sess|
FBC Stats/Average FPS|fbc_fps|
FBC Stats/Average Latency|fbc_latency|'
    else
        root_re='^[ \t]*vGPU ID[ \t]+:'
        order='mem_total,mem_free,mem_used,util_gpu,util_mem,util_encoder,util_decoder,encode_sess,encode_fps,encode_latency,fbc_sess,fbc_fps,fbc_latency'
        spec='FB Memory Usage/Total|mem_total|MiB
FB Memory Usage/Free|mem_free|MiB
FB Memory Usage/Used|mem_used|MiB
Utilization/GPU|util_gpu|%
Utilization/Gpu|util_gpu|%
Utilization/Memory|util_mem|%
Utilization/Encoder|util_encoder|%
Utilization/Decoder|util_decoder|%
Encoder Stats/Active Sessions|encode_sess|
Encoder Stats/Average FPS|encode_fps|
Encoder Stats/Average Latency|encode_latency|
FBC Stats/Active Sessions|fbc_sess|
FBC Stats/Average FPS|fbc_fps|
FBC Stats/Average Latency|fbc_latency|'
    fi

    awk -v host="$HOSTNAME" -v mode="$mode" -v want="$want" \
        -v root_re="$root_re" -v spec="$spec" -v order="$order" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function warn(m) { print (mode == "host" ? "gpu_host_stats" : "gpu_vm_stats") ": " m > "/dev/stderr" }

    # Longest-suffix lookup: "MIG Device/FB Memory Usage/Total" and
    # "FB Memory Usage/Total" both resolve to the same field, and the caller
    # keeps whichever came from the shallower path.
    function match_field(path,   k, plen, klen) {
        if (path in want_field) return path
        plen = length(path)
        for (k in want_field) {
            klen = length(k)
            if (plen > klen && substr(path, plen - klen + 1) == k &&
                substr(path, plen - klen, 1) == "/") return k
        }
        return ""
    }
    function tail_is(path, label,   plen, llen) {
        if (path == label) return 1
        plen = length(path); llen = length(label)
        return (plen > llen && substr(path, plen - llen + 1) == label &&
                substr(path, plen - llen, 1) == "/")
    }
    function record(path, raw,   n, tok, key, field, unit, depth) {
        key = match_field(path)
        if (key == "") return
        field = want_field[key]; unit = want_unit[key]
        depth = split(path, tok, "/")
        if (field in vals_depth && vals_depth[field] <= depth) return
        n = split(raw, tok, /[ \t]+/)
        if (tok[1] !~ /^[0-9]+(\.[0-9]+)?$/) {
            warn(id ": " path " is not a number (" raw "), field dropped"); return
        }
        if (unit == "" && n > 1) {
            warn(id ": " path " has an unexpected unit " tok[2] ", field dropped"); return
        }
        if (unit != "" && tok[2] != unit) {
            warn(id ": " path " is in " (n > 1 ? tok[2] : "no unit") " but MiB/% was expected, field dropped"); return
        }
        vals[field] = tok[1]; vals_depth[field] = depth
    }
    function flush(   i, n, ord, f, line, missing, parts) {
        if (id != "" && (want == "" || id == want)) {
            n = split(order, ord, ",")
            f = ""; missing = ""
            for (i = 1; i <= n; i++) {
                if (ord[i] in vals) f = f (f == "" ? "" : ",") ord[i] "=" vals[ord[i]]
                else missing = missing (missing == "" ? "" : " ") ord[i]
            }
            if (missing != "") warn(id ": missing field(s): " missing)
            if (f == "") warn(id ": no usable field, record dropped")
            else if (mode == "vm" && uuid == "") warn(id ": no VM UUID, record dropped")
            else {
                gsub(/ /, "-", name)
                if (mode == "host") line = "gpu.host,host=" host ",name=" name ",pciid=" id " " f
                else                line = "gpu.vm,gid=" id ",name=" name ",vm_uuid=" uuid " " f
                # Line protocol separates tags from fields with exactly one
                # space; anything else means a value carried a space through and
                # telegraf would reject the whole batch.
                if (split(line, parts, / /) == 2) print line
                else warn(id ": malformed line protocol, record dropped")
            }
        }
        id = ""; name = ""; uuid = ""; top = 0
        delete vals; delete vals_depth; delete stack_ind; delete stack_lbl
    }

    BEGIN {
        n = split(spec, rows, "\n")
        for (i = 1; i <= n; i++) {
            split(rows[i], c, "|")
            want_field[c[1]] = c[2]; want_unit[c[1]] = c[3]
        }
    }

    $0 ~ root_re {
        flush()
        if (mode == "host") id = $2
        else { id = $0; sub(/^[^:]*:[ \t]*/, "", id); id = trim(id) }
        root_ind = match($0, /[^ ]/) - 1
        next
    }
    id == "" { next }
    /^[ \t]*$/ { next }

    {
        ind = match($0, /[^ \t]/) - 1
        if (ind <= root_ind) { flush(); next }
        body = substr($0, ind + 1)
        if (index(body, " : ")) {
            key = trim(substr(body, 1, index(body, " : ") - 1))
            raw = trim(substr(body, index(body, " : ") + 3))
        } else {
            key = trim(body); raw = ""
        }

        while (top > 0 && stack_ind[top] >= ind) top--
        top++; stack_ind[top] = ind; stack_lbl[top] = key
        path = stack_lbl[1]
        for (i = 2; i <= top; i++) path = path "/" stack_lbl[i]

        if (raw == "") next
        if (mode == "host" && tail_is(path, "Product Name")) { if (name == "") name = raw; next }
        if (mode == "vm") {
            if (tail_is(path, "VM UUID"))   { if (uuid == "") uuid = raw; next }
            if (tail_is(path, "vGPU Name")) { if (name == "") name = raw; next }
        }
        record(path, raw)
    }

    END { flush() }'
}

gpu_vm_stats()
{
    if ! gpu_is_installed; then
        return 0
    fi

    local vid=$1

    if [ "$FORMAT" == "line" ]; then
        # A vGPU record is keyed by vGPU ID, so the caller's VM UUID filter is
        # applied to the parsed output rather than by slicing the text first.
        $NVIDIA_SMI vgpu -q | gpu_stats_parse vm | \
            awk -v vid="$vid" 'vid == "" || index($0, "vm_uuid=" vid)'
    else
        $NVIDIA_SMI vgpu -q | gpu_stats_record '^[ \t]*vGPU ID[ \t]+:' "$vid"
    fi
}

# What to put in a log line about a failed nvidia-smi probe. nvidia-smi prints
# "No devices were found" on stdout and leaves stderr empty (measured on cn13:
# a nonexistent GPU is exit 6, empty stderr), so a message built from stderr
# alone says nothing. Prefer stderr, fall back to stdout, both flattened to one
# line for the journal.
gpu_probe_diagnosis()
{
    local err_file="$1" std_out="$2"

    local text
    text=$(tr '\n' ' ' < "$err_file" 2>/dev/null | sed 's/[[:space:]]*$//')
    [ -n "$text" ] || text=$(echo "$std_out" | tr '\n' ' ' | sed 's/[[:space:]]*$//')

    echo "${text:-(no output)}"
}

# Returns a stringified JSON array conforming to the following schema:
# {
#   id: string
#   name: string
#   type: "unset" | "pgpu" | "sriovVgpu" | "migBackedVgpu"
#   supportTypes: ("pgpu" | "sriovVgpu" | "migBackedVgpu")[]
#   pciAddress: string
#   sriovVgpuProfileCountLimit: number | null
#   status: "unassigned" | "idle" | "inUse"
#   allocation: {
#     current: number
#     total: number
#   } | null
# }[]
# Emits one TSV record per vGPU type the card's model supports:
#   <typeId>\t<shortProfileName>\t<framebufferMiB>
# Takes an nvidia-smi style bus id ("00000001:C8:00.0"). Silent (exit 0, no
# output) when the table or the device is missing - callers treat that the same
# way they treat an empty nvidia-smi probe.
gpu_vgpu_types_from_xml()
{
    local pci_bus_id="$1"

    [ -n "$pci_bus_id" ] || return 0
    [ -r "$VGPU_CONFIG_XML" ] || return 0

    # nvidia-smi prints an 8-digit domain in upper case; sysfs uses 4 digits in
    # lower case. Same trimming as gpu_bind_vfio_pci.
    local sysfs_pci_addr
    sysfs_pci_addr=$(echo "$pci_bus_id" | sed 's/^[0-9a-fA-F]\{4\}//' | tr '[:upper:]' '[:lower:]')

    local device_id
    device_id=$(cat "/sys/bus/pci/devices/${sysfs_pci_addr}/device" 2>/dev/null)
    [ -n "$device_id" ] || return 0

    # sysfs prints 0x2bb5, the table spells it 0x2BB5
    device_id="0x$(echo "${device_id#0x}" | tr '[:lower:]' '[:upper:]')"

    awk -v want="$device_id" '
        /<vgpuType / {
            id = ""; name = ""; dev = ""; size = ""
            if (match($0, /id="[0-9]+"/))
                id = substr($0, RSTART + 4, RLENGTH - 5)
            if (match($0, /name="[^"]*"/))
                name = substr($0, RSTART + 6, RLENGTH - 7)
        }
        /<devId / {
            if (match($0, /deviceId="[^"]*"/))
                dev = substr($0, RSTART + 10, RLENGTH - 11)
        }
        /<profileSize>/ {
            if (match($0, />0[xX][0-9a-fA-F]+</))
                size = substr($0, RSTART + 1, RLENGTH - 2)
        }
        /<\/vgpuType>/ {
            # The profile name callers match on is the last token of the full
            # board name ("NVIDIA RTX Pro 6000 Blackwell DC-12Q" -> "DC-12Q"),
            # the same slice nvidia-smi parsing takes with $NF.
            if (dev == want && id != "" && name != "" && size != "") {
                n = split(name, parts, " ")
                printf "%s\t%s\t%d\n", id, parts[n], strtonum(size) / 1048576
            }
        }
    ' "$VGPU_CONFIG_XML"
}

# supportTypes for a card nvidia-smi cannot enumerate. A pgpu is bound to
# vfio-pci, so every probe-based answer collapses to ["pgpu"] - which is what
# the card currently is, not what it can be. supportTypes is capability data,
# so derive it from the static table instead.
gpu_support_types_from_xml()
{
    local pci_bus_id="$1"

    local support_types='["pgpu"]'
    local profile_names
    profile_names=$(gpu_vgpu_types_from_xml "$pci_bus_id" | awk -F'\t' '{print $2}')

    if echo "$profile_names" | grep -qE "$SRIOV_PROFILE_NAME_REGEX"; then
        support_types=$(echo "$support_types" | jq -c '. + ["sriovVgpu"]')
    fi

    if echo "$profile_names" | grep -qE "$MIG_PROFILE_NAME_REGEX"; then
        support_types=$(echo "$support_types" | jq -c '. + ["migBackedVgpu"]')
    fi

    echo "$support_types"
}

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

    local output="[]"

    while IFS=',' read -r uuid name pci_bus_id; do
        [ -z "$uuid" ] && continue

        uuid=$(echo "$uuid" | xargs)
        name=$(echo "$name" | xargs)
        pci_bus_id=$(echo "$pci_bus_id" | xargs)

        # Keep the probe's exit status instead of dropping it. On failure
        # support_types stays at its hardcoded ["pgpu"] below, so a
        # vGPU-capable card reports as passthrough-only; without this the node
        # carries no trace of why. One card's failed probe must not fail the
        # node, so the list is still built - the reason is just on the record.
        local vgpu_support_out vgpu_support_rc vgpu_support_err vgpu_support_err_file
        vgpu_support_err_file=$(mktemp)
        vgpu_support_out=$($NVIDIA_SMI vgpu -s -v -i "$pci_bus_id" 2>"$vgpu_support_err_file")
        vgpu_support_rc=$?
        vgpu_support_err=$(gpu_probe_diagnosis "$vgpu_support_err_file" "$vgpu_support_out")
        rm -f "$vgpu_support_err_file"

        if [ "$vgpu_support_rc" -ne 0 ]; then
            log_error "gpu_device_list: nvidia-smi vgpu -s -v -i $pci_bus_id exited $vgpu_support_rc: $vgpu_support_err; supportTypes for this card falls back to [\"pgpu\"]"
        fi

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
                '. + [{ id: $id, name: $name, type:"unset", supportTypes: $supportTypes, pciAddress: $pciAddress, sriovVgpuProfileCountLimit: null, status: "unassigned", allocation: null }]')
            continue
        fi

        local status="idle"
        local allocation
        # Must match the name used below and in the jq call at the end of this
        # loop. It was declared as profile_count_limit while the sriovVgpu
        # branch assigned (and the jq call read) sriov_vgpu_profile_count_limit,
        # so on any other type the latter was an unset, non-local variable:
        # --argjson got an empty string and the whole gpu_device_list jq failed.
        # Being non-local also let one card's limit leak into the next.
        local sriov_vgpu_profile_count_limit="null"

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
                local sriov_totalvfs 
                sriov_totalvfs=$(cat "/sys/bus/pci/devices/${pci_sysfs}/sriov_totalvfs" 2>/dev/null | tr -d '[:space:]')
                if echo "$sriov_totalvfs" | grep -qE '^[0-9]+$'; then
                    sriov_vgpu_profile_count_limit="$sriov_totalvfs"
                fi
            fi

        fi

        output=$(echo "$output" | jq -c \
            --arg id "$uuid" \
            --arg name "$name" \
            --arg type "$gpu_type" \
            --argjson supportTypes "$support_types" \
            --arg pciAddress "$pci_bus_id" \
            --argjson sriovVgpuProfileCountLimit "${sriov_vgpu_profile_count_limit:-null}" \
            --arg status "$status" \
            --argjson allocation "$allocation" \
            '. + [{id:$id, name:$name, type:$type, supportTypes:$supportTypes, pciAddress:$pciAddress, sriovVgpuProfileCountLimit:$sriovVgpuProfileCountLimit, status:$status, allocation:$allocation}]')
    done <<< "$gpu_csv"

    # GPUs already bound to vfio-pci (type "pgpu") are no longer enumerable
    # by nvidia-smi, so they're missing from $output above. Union them back
    # in using the properties recorded in the config file.
    local recorded_gpu_ids
    recorded_gpu_ids=$(echo "$output" | jq -c '[.[].id]')

    local pgpu_ids
    pgpu_ids=$(echo "$gpu_config" | jq -c --argjson targetIds "$recorded_gpu_ids" \
        '[.[] | select((.id as $id | $targetIds | index($id)) == null)]')

    while IFS= read -r entry; do
        [ -z "$entry" ] || [ "$entry" = "null" ] && continue

        local uuid name gpu_type pci_address
        uuid=$(echo "$entry" | jq -r '.id')
        name=$(echo "$entry" | jq -r '.name // "unknown"')
        gpu_type=$(echo "$entry" | jq -r '.type')
        pci_address=$(echo "$entry" | jq -r '.pciAddress // ""')

        local status="idle"
        local allocation='{"current":0,"total":1}'

        if [ "$gpu_type" = "pgpu" ] && [ -n "$pci_address" ]; then
            local pci_bus pci_slot
            pci_bus=$(echo "$pci_address" | awk -F: '{print tolower($2)}')
            pci_slot=$(echo "$pci_address" | awk -F: '{print $3}' | awk -F. '{print tolower($1)}')

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
            fi
        fi

        local support_types
        support_types=$(gpu_support_types_from_xml "$pci_address")

        output=$(echo "$output" | jq -c \
            --arg id "$uuid" \
            --arg name "$name" \
            --arg type "$gpu_type" \
            --arg pciAddress "$pci_address" \
            --arg status "$status" \
            --argjson supportTypes "$support_types" \
            --argjson allocation "$allocation" \
            '. + [{id:$id, name:$name, type:$type, supportTypes:$supportTypes, pciAddress:$pciAddress, profileCountLimit:null, status:$status, allocation:$allocation}]')
    done <<< "$(echo "$pgpu_ids" | jq -c '.[]' 2>/dev/null)"

    # The union above only catches vfio-pci-bound GPUs that config.json
    # already knows about. A GPU can be bound to vfio-pci without a
    # matching config record (e.g. bound outside of gpu_resource_set, or
    # after the config file is lost/reset), and such a GPU is invisible to
    # both nvidia-smi and the config-file union, so it would never be
    # enumerated. Close that gap by searching the PCI bus directly (by
    # NVIDIA vendor ID 10de) for devices actually held by vfio-pci.
    local sysfs_addr
    for sysfs_addr in $(lspci -Dnn -d 10de: 2>/dev/null | awk '{print $1}'); do
        local driver_path="/sys/bus/pci/devices/${sysfs_addr}/driver"
        [ -e "$driver_path" ] || continue
        [ "$(basename "$(readlink -f "$driver_path")")" = "vfio-pci" ] || continue

        # config.json/nvidia-smi use an 8-char PCI domain (00000000:bb:ss.f);
        # lspci -D / sysfs use a 4-char domain (0000:bb:ss.f).
        local already_listed
        already_listed=$(echo "$output" | jq -r --arg addr "$sysfs_addr" \
            '[.[] | select((.pciAddress // "" | ascii_downcase | .[4:]) == $addr)] | length')
        [ "$already_listed" != "0" ] && continue

        local entry
        entry=$(echo "$gpu_config" | jq -c --arg addr "$sysfs_addr" \
            '[.[] | select((.pciAddress // "" | ascii_downcase | .[4:]) == $addr)] | .[0] // empty')

        local uuid name pci_address
        if [ -n "$entry" ]; then
            uuid=$(echo "$entry" | jq -r '.id')
            name=$(echo "$entry" | jq -r '.name // "unknown"')
            pci_address=$(echo "$entry" | jq -r '.pciAddress')
        else
            uuid="$sysfs_addr"
            name=$(lspci -s "$sysfs_addr" | sed -E 's/^[0-9a-f:.]+ [^:]+: //')
            [ -z "$name" ] && name="unknown"
            pci_address="0000${sysfs_addr}"
        fi

        local pci_bus pci_slot
        pci_bus=$(echo "$sysfs_addr" | awk -F: '{print tolower($2)}')
        pci_slot=$(echo "$sysfs_addr" | awk -F: '{print $3}' | awk -F. '{print tolower($1)}')

        local in_use=0
        for vm_id in $(virsh list --state-running --uuid 2>/dev/null); do
            if virsh dumpxml "$vm_id" 2>/dev/null | \
                grep -q "bus='0x${pci_bus}'.*slot='0x${pci_slot}'"; then
                in_use=1
                break
            fi
        done

        local status="idle"
        local allocation='{"current":0,"total":1}'
        if [ "$in_use" = "1" ]; then
            status="inUse"
            allocation='{"current":1,"total":1}'
        fi

        local support_types
        support_types=$(gpu_support_types_from_xml "$pci_address")

        output=$(echo "$output" | jq -c \
            --arg id "$uuid" \
            --arg name "$name" \
            --arg pciAddress "$pci_address" \
            --arg status "$status" \
            --argjson supportTypes "$support_types" \
            --argjson allocation "$allocation" \
            '. + [{id:$id, name:$name, type:"pgpu", supportTypes:$supportTypes, pciAddress:$pciAddress, profileCountLimit:null, status:$status, allocation:$allocation}]')
    done

    # Every step above rebuilds $output through jq, so a single failed jq call
    # (e.g. --argjson handed an empty variable) collapses it to an empty string
    # and the accumulated devices are gone. Emitting that as-is with exit 0
    # tells the caller "this node has no GPUs", which is indistinguishable from
    # the truth and silently wrong - cube-cos-api would drop every card.
    if ! echo "$output" | jq -e 'type == "array"' >/dev/null 2>&1; then
        echo "Error: gpu_device_list: built a malformed device list; refusing to report it as an empty one" >&2
        return 1
    fi

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

    # MIG-backed vGPU profiles - one entry per vGPU *type*, not per GPU instance
    # profile. Both lists are therefore built from the same `vgpu -s -v` output
    # and mean the same thing field for field.
    #
    # This list used to be built from `mig -lgip` and keyed by GPU Instance
    # Profile ID, which cannot express what the operator actually picks: one GI
    # profile exposes many vGPU types (47 exposes 19 on cn13's RTX PRO 6000
    # Blackwell, DC-1-2Q through DC-1-24C), so a single id left the type - and
    # with it the framebuffer size and the Q/A/B/C mode - undetermined, and the
    # code picked one on the operator's behalf. `mig -lgip` also lists partition
    # shapes that have no MIG-backed vGPU type at all (8 of the 11 it reports on
    # that card), so the list offered choices that could never be applied.
    # Verified on cn13 2026-08-04; see spec.md §2c/§5b (#905).
    local mig_profiles="[]"

    # Keep the probe's exit status and its diagnosis. Dropping both -
    # 2>/dev/null and no test of $? - is what let a failed probe reach the
    # caller as exit 0 with empty lists, indistinguishable from "this card has
    # no vGPU types".
    local vgpu_output vgpu_probe_rc vgpu_probe_err vgpu_probe_err_file
    vgpu_probe_err_file=$(mktemp)
    vgpu_output=$($NVIDIA_SMI vgpu -s -v -i "$gpu_id" 2>"$vgpu_probe_err_file")
    vgpu_probe_rc=$?
    vgpu_probe_err=$(gpu_probe_diagnosis "$vgpu_probe_err_file" "$vgpu_output")
    rm -f "$vgpu_probe_err_file"

    # Same vfio-pci blindness as in gpu_device_list: a pgpu reports no profiles
    # at all, which reads as "this card cannot do vGPU" and leaves a client with
    # nothing to request. Rebuild the capability half from the static table.
    #
    # vmCountLimit stays null here. The table carries a per-GI limit only, and
    # the card-wide count depends on how the card is partitioned - undefined
    # while it is still a passthrough card. It comes back on its own once the
    # card actually runs vGPU and nvidia-smi answers again.
    # Keyed on the absence of parsable records, not an empty string: nvidia-smi
    # prints "No devices were found" to stdout, so the probe output is never
    # actually empty for a card it cannot see.
    if ! echo "$vgpu_output" | grep -q "vGPU Type ID"; then
        local pci_address
        pci_address=$(echo "$gpu_config" | jq -r --arg id "$gpu_id" \
            'map(select(.id == $id)) | if length > 0 then (.[0].pciAddress // "") else "" end')

        local xml_id xml_name xml_vram
        while IFS="$(printf '\t')" read -r xml_id xml_name xml_vram; do
            [ -z "$xml_id" ] && continue

            if echo "$xml_name" | grep -qE "$MIG_PROFILE_NAME_REGEX"; then
                mig_profiles=$(echo "$mig_profiles" | jq -c \
                    --argjson id "$xml_id" --arg name "$xml_name" --argjson vram_mib "$xml_vram" \
                    '. + [{ id: $id, name: $name, vramMiB: $vram_mib, vmCountLimit: null }]')
            elif echo "$xml_name" | grep -qE "$SRIOV_PROFILE_NAME_REGEX"; then
                sriov_profiles=$(echo "$sriov_profiles" | jq -c \
                    --argjson id "$xml_id" --arg name "$xml_name" --argjson vram_mib "$xml_vram" \
                    '. + [{ id: $id, name: $name, vramMiB: $vram_mib, vmCountLimit: null }]')
            fi
        done <<EOF
$(gpu_vgpu_types_from_xml "$pci_address")
EOF
    fi

    # A failed probe is only fatal once nothing else has answered. A pgpu bound
    # to vfio-pci fails the probe exactly the way a nonexistent GPU does - both
    # are "No devices were found", exit 6 - and for that card the static table
    # above is the intended answer, so keying on the exit status alone would
    # undo the vfio-pci fallback and turn every poll of a healthy pgpu into an
    # error. What must never happen is empty lists with exit 0 when no source
    # answered at all: the caller reads that as "this card has no vGPU types"
    # and offers the operator nothing to pick.
    if [ "$vgpu_probe_rc" -ne 0 ]; then
        if [ "$sriov_profiles" = "[]" ] && [ "$mig_profiles" = "[]" ]; then
            echo "Error: gpu_vgpu_profile_list: no profile source answered for $gpu_id" >&2
            log_error "gpu_vgpu_profile_list: nvidia-smi vgpu -s -v -i $gpu_id exited $vgpu_probe_rc: $vgpu_probe_err; $VGPU_CONFIG_XML listed no type either, refusing to report empty profile lists as a healthy answer"
            return 1
        fi
        log_debug "gpu_vgpu_profile_list: nvidia-smi vgpu -s -v -i $gpu_id exited $vgpu_probe_rc: $vgpu_probe_err; answered from $VGPU_CONFIG_XML instead"
    fi

    local vgpu_type_id_hex
    for vgpu_type_id_hex in $(echo "$vgpu_output" | grep "vGPU Type ID" | awk '{print $NF}'); do
        # `vgpu_type_id_hex` is a number in hex format (e.g. 0x619).
        # Convert it to a decimal number and store it in `decimal_id`.
        local decimal_id
        decimal_id=$(awk -v v="$vgpu_type_id_hex" 'BEGIN{print strtonum(v)}')

        local block profile_name fb_memory_mib max_instances
        block=$(echo "$vgpu_output" | grep -A 20 "vGPU Type ID *: $vgpu_type_id_hex\$")
        # `Name                              : NVIDIA RTX Pro 6000 Blackwell DC-1-24Q`
        profile_name=$(echo "$block" | grep "Name" | head -1 | awk '{print $NF}')
        # `FB Memory                         : 24576 MiB`
        fb_memory_mib=$(echo "$block" | grep "FB Memory" | head -1 | awk '{print $4}')
        # `Max Instances                     : 4` - how many of this type the
        # whole card can host. Anchored on the colon so it cannot match
        # `Max Instances Per VM` or `Max Instances Per GI`, which both contain
        # this string. Absent on SR-IOV types, which carry no such limit.
        max_instances=$(echo "$block" | \
            grep -E "^[[:space:]]*Max Instances[[:space:]]*:" | head -1 | awk '{print $NF}')
        [ -z "$max_instances" ] && max_instances="null"

        # MIG-backed type names carry a slice count ("DC-1-3Q"); SR-IOV
        # time-sliced ones do not ("DC-3Q").
        if echo "$profile_name" | grep -qE "$MIG_PROFILE_NAME_REGEX"; then
            mig_profiles=$(echo "$mig_profiles" | jq -c \
                --argjson id "$decimal_id" \
                --arg name "$profile_name" \
                --argjson vram_mib "$fb_memory_mib" \
                --argjson vmCountLimit "$max_instances" \
                '. + [{ id: $id, name: $name, vramMiB: $vram_mib, vmCountLimit: $vmCountLimit }]')
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

# Full validation for gpu_resource_set: gpu_id, new_type, profiles required-ness
# for the given type, GPU existence, and in-use status.
gpu_resource_set_check()
{
    local gpu_id="$1"
    local new_type="$2"
    local profiles="$3"

    if [ -z "$gpu_id" ]; then
        echo "Error: gpu_id is required" >&2
        return 1
    fi

    if [ -z "$new_type" ]; then
        echo "Error: new_type is required" >&2
        return 1
    fi

    case "$new_type" in
        pgpu|sriovVgpu|migBackedVgpu) ;;
        *)
            echo "Error: invalid type '$new_type'. Must be one of: pgpu, sriovVgpu, migBackedVgpu" >&2
            return 1
            ;;
    esac

    # The profiles argument (format, profile-id existence, capacity) is
    # validated by `hex_config gpu_resource_set` (config_gpu.cpp), which owns
    # the gpu_resource_set business logic.

    local device
    device=$(gpu_device_list | jq -c --arg id "$gpu_id" 'map(select(.id == $id)) | .[0] // null')

    if [ "$device" = "null" ]; then
        echo "Error: GPU UUID $gpu_id not found" >&2
        return 1
    fi

    if [ "$(echo "$device" | jq -r '.status')" = "inUse" ]; then
        echo "Error: GPU $gpu_id is in-use" >&2
        return 1
    fi
}

# Unsets whatever vGPU mode the GPU is currently configured for,
# according to the config file, so it is free to be reconfigured.
# This function does nothing if the target GPU is currently configured
# as pGPU.
# Releases one PF's SR-IOV VFs through sriov-manage, retrying briefly on
# unbindLock contention. Returns 0 on success, 1 on failure.
#
# Zeroing sriov_numvfs by writing to the sysfs file directly (even with each
# VF's vGPU type pre-cleared) is rejected by the driver - confirmed on cn13
# hardware: "write error: No such file or directory" every time, regardless of
# VF state. Disabling VFs requires going through sriov-manage, which requests
# the driver's unbindLock (temporarily detaches/reattaches the PF's own driver
# binding) before touching sriov_numvfs - a raw sysfs write skips that
# handshake and the driver refuses it. sriov-manage -d also clears each VF's
# vGPU type internally, so no separate cleanup loop is needed.
#
# sriov-manage can transiently fail to obtain that unbindLock if another NVML
# client (e.g. cube-cos-api's GPU status API) holds the device open at that
# exact moment - retry briefly to absorb that race. A failure that isn't this
# specific message is not retried and fails immediately.
#
# Unlike gpu_vf_disable() near the top of this file, this touches only the
# given PF: it never rebinds anything to vfio-pci and never writes
# modprobe.d persistence.
gpu_sriov_disable_vfs()
{
    local pci_addr="$1"

    local attempt output rc
    for attempt in 1 2 3 4 5; do
        output=$($NVIDIA_SRIOV -d "$pci_addr" 2>&1)
        rc=$?
        if [ $rc -eq 0 ]; then
            return 0
        fi
        if ! echo "$output" | grep -q "Cannot obtain unbindLock"; then
            echo "Error: failed to disable SR-IOV VFs on $pci_addr: $output" >&2
            return 1
        fi
        if [ "$attempt" = "5" ]; then
            echo "Error: failed to disable SR-IOV VFs on $pci_addr: unbindLock still busy after 5 attempts" >&2
            return 1
        fi
        echo "Warning: unbindLock busy for $pci_addr, retrying ($attempt/5)" >&2
        sleep 1
    done

    return 1
}

# Renders the sysfs form of a GPU's PCI address: nvidia-smi reports an 8-char
# domain in uppercase hex (00000000:BB:SS.F) but the sysfs directory name uses
# a 4-char lowercase one (0000:bb:ss.f).
gpu_sysfs_pci_addr()
{
    local gpu_id="$1"

    $NVIDIA_SMI --query-gpu=pci.bus_id -i "$gpu_id" --format=csv,noheader,nounits 2>/dev/null \
        | sed 's/^[0-9a-fA-F]\{4\}//' | tr '[:upper:]' '[:lower:]'
}

gpu_unset_current_type()
{
    local gpu_id="$1"

    local current_type
    current_type=$(jq -r --arg id "$gpu_id" \
        'map(select(.id == $id)) | if length > 0 then .[0].type else "" end' \
        "$GPU_CONFIG_FILE_PATH" 2>/dev/null)

    if [ "$current_type" = "sriovVgpu" ]; then
        local pci_addr
        pci_addr=$(gpu_sysfs_pci_addr "$gpu_id")

        if ! gpu_sriov_disable_vfs "$pci_addr"; then
            exit 1
        fi
    elif [ "$current_type" = "migBackedVgpu" ]; then
        # A MIG-backed card carries the same VF/current_vgpu_type shape as an
        # SR-IOV one, so its VFs are released the same way - and they must be
        # released *first*. With VFs still enabled the driver refuses to turn
        # MIG mode off ("Unable to disable MIG Mode for GPU ...: In use by
        # another client", confirmed on cn13 2026-08-04), which left a
        # MIG-backed card permanently stuck on its first configuration: no
        # re-carve, no switch back to pgpu/sriovVgpu.
        #
        # sriov-manage -d rebinds the driver, and that also destroys every GPU
        # instance on the card, so no explicit -dci/-dgi pass is needed before
        # -mig 0.
        local mig_pci_addr
        mig_pci_addr=$(gpu_sysfs_pci_addr "$gpu_id")

        if [ -z "$mig_pci_addr" ]; then
            echo "Error: GPU $gpu_id has type migBackedVgpu but nvidia-smi reported no PCI address" >&2
            exit 1
        fi

        if ! gpu_sriov_disable_vfs "$mig_pci_addr"; then
            exit 1
        fi

        if ! $NVIDIA_SMI -i "$gpu_id" -mig 0; then
            echo "Error: failed to disable MIG mode for GPU $gpu_id" >&2
            exit 1
        fi
    elif [ "$current_type" = "pgpu" ]; then
        # Hand the card back from vfio-pci to the nvidia driver. Without this
        # the card stays bound to vfio-pci (and keeps its sticky
        # driver_override), so switching it to sriovVgpu/migBackedVgpu next
        # fails: nvidia-smi cannot see a vfio-bound device.
        #
        # The address comes from config.json, not nvidia-smi: a pgpu is bound
        # to vfio-pci and therefore invisible to nvidia-smi, so the
        # --query-gpu lookup used for sriovVgpu above would return nothing here.
        local pgpu_pci_address
        pgpu_pci_address=$(jq -r --arg id "$gpu_id" \
            'map(select(.id == $id)) | if length > 0 then (.[0].pciAddress // "") else "" end' \
            "$GPU_CONFIG_FILE_PATH" 2>/dev/null)

        if [ -z "$pgpu_pci_address" ]; then
            echo "Error: GPU $gpu_id has type pgpu but no recorded pciAddress; cannot release it from vfio-pci" >&2
            exit 1
        fi

        if ! gpu_unbind_vfio_pci "$pgpu_pci_address"; then
            exit 1
        fi
    fi
}

# Binds the PCI device identified by PCI address to vfio-pci for PCI passthrough.
# Pure sysfs operation - does not depend on nvidia-smi being able to see the
# device, so it is safe to call during hex_config Commit() re-apply, after the
# device is no longer enumerable by nvidia-smi.
#
# driver_override is what makes the bind work at all: vfio-pci carries no id
# table entry matching an NVIDIA display device, so writing the address to
# vfio-pci/bind is refused (confirmed on cn13: the device's driver_override was
# (null) and /sys/bus/pci/drivers/vfio-pci/ held zero device ids). The unbind
# ahead of it still succeeded, so the card was left bound to *no* driver, and
# because both writes discarded stderr the caller only saw a bare exit 1.
# Setting driver_override first tells the PCI core which driver the device must
# use; drivers_probe then binds it. If the bind still fails, roll the device
# back to the driver it had rather than leaving it stranded.
gpu_bind_vfio_pci()
{
    # nvidia-smi uses 8-char domain (00000000:bb:ss.f); sysfs uses 4-char (0000:bb:ss.f)
    local sysfs_pci_addr
    sysfs_pci_addr=$(echo "$1" | sed 's/^[0-9a-fA-F]\{4\}//' | tr '[:upper:]' '[:lower:]')

    local device_path="/sys/bus/pci/devices/${sysfs_pci_addr}"
    if [ ! -d "$device_path" ]; then
        echo "Error: gpu_bind_vfio_pci: no PCI device at $sysfs_pci_addr" >&2
        return 1
    fi

    if ! modprobe vfio-pci; then
        echo "Error: gpu_bind_vfio_pci: failed to load the vfio-pci module" >&2
        return 1
    fi

    local driver_path="${device_path}/driver"
    local previous_driver=""
    if [ -e "$driver_path" ]; then
        previous_driver=$(basename "$(readlink -f "$driver_path")")
        # Already where we want it - nothing to do. Keeps Commit() re-apply
        # idempotent instead of pointlessly cycling a live passthrough device.
        if [ "$previous_driver" = "vfio-pci" ]; then
            return 0
        fi
    fi

    if ! echo "vfio-pci" > "${device_path}/driver_override"; then
        echo "Error: gpu_bind_vfio_pci: failed to set driver_override on $sysfs_pci_addr" >&2
        return 1
    fi

    if [ -n "$previous_driver" ]; then
        if ! echo "$sysfs_pci_addr" > "/sys/bus/pci/drivers/${previous_driver}/unbind"; then
            echo "Error: gpu_bind_vfio_pci: failed to unbind $sysfs_pci_addr from $previous_driver" >&2
            echo "" > "${device_path}/driver_override"
            return 1
        fi
    fi

    echo "$sysfs_pci_addr" > /sys/bus/pci/drivers_probe

    if [ "$(basename "$(readlink -f "$driver_path" 2>/dev/null)" 2>/dev/null)" = "vfio-pci" ]; then
        return 0
    fi

    # Bind failed and the device is now driverless. Put it back rather than
    # leaving the GPU stranded (which is what used to happen, silently).
    echo "Error: gpu_bind_vfio_pci: $sysfs_pci_addr did not bind to vfio-pci; restoring ${previous_driver:-its original driver}" >&2
    echo "" > "${device_path}/driver_override"
    echo "$sysfs_pci_addr" > /sys/bus/pci/drivers_probe

    local restored
    restored=$(basename "$(readlink -f "$driver_path" 2>/dev/null)" 2>/dev/null)
    if [ -z "$restored" ] || [ "$restored" = "driver" ]; then
        echo "Error: gpu_bind_vfio_pci: $sysfs_pci_addr is left with no driver bound; recover with: echo $sysfs_pci_addr > /sys/bus/pci/drivers_probe" >&2
    fi

    return 1
}

# Releases a PCI device from vfio-pci and lets its native driver claim it again.
# The driver_override set by gpu_bind_vfio_pci is sticky: without clearing it the
# device re-binds to vfio-pci on every probe, so a card switched away from pgpu
# would never come back to the nvidia driver.
gpu_unbind_vfio_pci()
{
    local sysfs_pci_addr
    sysfs_pci_addr=$(echo "$1" | sed 's/^[0-9a-fA-F]\{4\}//' | tr '[:upper:]' '[:lower:]')

    local device_path="/sys/bus/pci/devices/${sysfs_pci_addr}"
    if [ ! -d "$device_path" ]; then
        echo "Error: gpu_unbind_vfio_pci: no PCI device at $sysfs_pci_addr" >&2
        return 1
    fi

    local driver_path="${device_path}/driver"
    local current_driver=""
    if [ -e "$driver_path" ]; then
        current_driver=$(basename "$(readlink -f "$driver_path")")
    fi

    if [ -e "${device_path}/driver_override" ]; then
        echo "" > "${device_path}/driver_override"
    fi

    if [ "$current_driver" = "vfio-pci" ]; then
        if ! echo "$sysfs_pci_addr" > /sys/bus/pci/drivers/vfio-pci/unbind; then
            echo "Error: gpu_unbind_vfio_pci: failed to unbind $sysfs_pci_addr from vfio-pci" >&2
            return 1
        fi
    fi

    echo "$sysfs_pci_addr" > /sys/bus/pci/drivers_probe

    local bound
    bound=$(basename "$(readlink -f "$driver_path" 2>/dev/null)" 2>/dev/null)
    if [ -z "$bound" ] || [ "$bound" = "driver" ] || [ "$bound" = "vfio-pci" ]; then
        echo "Error: gpu_unbind_vfio_pci: $sysfs_pci_addr did not return to its native driver (now: ${bound:-none})" >&2
        return 1
    fi

    return 0
}

gpu_host_stats()
{
    if ! gpu_is_installed; then
        return 0
    fi

    local pciid=$1

    if [ "$FORMAT" == "line" ]; then
        $NVIDIA_SMI -q | gpu_stats_parse host "$pciid"
    else
        $NVIDIA_SMI -q | gpu_stats_record '^GPU [0-9A-Fa-f]' "$pciid" "$HOSTNAME"
    fi
}
