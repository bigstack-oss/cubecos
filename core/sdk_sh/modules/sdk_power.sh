# sdk_power.sh -- node/cluster power lifecycle: the rolling-restart machinery.
#
# Extracted from proj_functions + sdk_os.sh. Follows the hex_sdk module
# convention (sdk_power.sh <-> power_* functions), so `hex_sdk power_yyy`
# sources just this module; private helpers _power_* resolve via the
# all-modules fallback. Available in every roll context: the CLI, the
# control-node drain, remote_run, and each node's boot path (cube_cluster_start
# -> power_roll_advance).
# --- Rolling restart -------------------------------------------------------
# Operator-triggered, workload-preserving reboot of every node, one at a time.
# Built as a boot-relay: the job state lives on shared cephfs and is advanced
# from each node's boot path, so the chain survives the node it is rebooting --
# including the node the operator triggered it from and the master control node.
# Compute workloads are live-migrated off a node before it goes down. Because
# the state is shared, progress is readable from any node ("rolling_restart
# status"); it is also what cube-cos-api / cos-ui will drive later.

ROLLING_RESTART_DIR=/mnt/cephfs/rolling_restart
ROLLING_RESTART_JOB=$ROLLING_RESTART_DIR/job.json

# Locked read-modify-write of the shared job.json, retried across a cephfs/MDS
# failover window. Temp name expanded once per attempt (avoids lost updates).
_power_roll_write()
{
    local i t
    for i in $(seq 1 30) ; do
        t=$ROLLING_RESTART_JOB.tmp.$$.$i
        if ( flock -w 15 200 || exit 3
             jq "$@" $ROLLING_RESTART_JOB > "$t" && [ -s "$t" ] && mv "$t" $ROLLING_RESTART_JOB || { rm -f "$t" ; exit 4 ; }
           ) 200>$ROLLING_RESTART_DIR/.lock 2>/dev/null ; then
            return 0
        fi
        rm -f "$t" 2>/dev/null ; mkdir -p $ROLLING_RESTART_DIR 2>/dev/null ; sleep 2
    done
    return 1
}

_power_roll_set_str() { _power_roll_write --arg v "$2" ".$1=\$v" ; }

_power_roll_set_raw() { _power_roll_write --argjson v "$2" ".$1=\$v" ; }

# Set node status and stamp phase_ts[status]=now for per-phase durations.
_power_roll_set_node_status()
{
    _power_roll_write --arg h "$1" --arg s "$2" --argjson ts "$(date +%s)" \
        '(.nodes[]|select(.hostname==$h)) |= (.status=$s | .phase_ts=((.phase_ts//{}) + {($s):$ts}))'
}

# Stamp a phase timestamp without changing .status. No-op if no job exists.
_power_roll_set_phase_ts()
{
    [ -e "$ROLLING_RESTART_JOB" ] || return 0
    _power_roll_write --arg h "$1" --arg p "$2" --argjson ts "$(date +%s)" \
        '(.nodes[]|select(.hostname==$h)) |= (.phase_ts=((.phase_ts//{}) + {($p):$ts}))'
}

_power_roll_set_node_num() { _power_roll_write --arg h "$1" --argjson v "$3" "(.nodes[]|select(.hostname==\$h).$2)=\$v" ; }

_power_roll_pause()
{
    _power_roll_set_str reason "$1"
    _power_roll_set_str state paused
    echo "rolling restart paused: $1" >&2
    /usr/sbin/hex_log_event -e CLU00004W "interface=system,host=$HOSTNAME,category=cluster,sub=rolling_restart,action=pause,reason=$1"
}

_power_roll_drain_poll()
{
    # Background helper (runs on the control node driving the evacuation):
    # refresh the in-flight host's progress in the job state until the drain
    # finishes (sentinel removed). A VM is "handled" once it leaves ACTIVE on
    # this host -- live-migrating/migrated, or paused-in-place for a non-
    # migratable passthrough VM. vms_paused isolates the paused ones (they take
    # reboot downtime); migrated = vms_done - vms_paused. init_inactive is the
    # VMs already non-ACTIVE at start (e.g. SHUTOFF), excluded from "paused".
    local host=$1 total=$2 sentinel=$3 allstart=$4
    local init_inactive=$(( allstart - total ))
    [ $init_inactive -lt 0 ] && init_inactive=0
    while [ -e "$sentinel" ] ; do
        sleep 5
        local states
        states=$($OPENSTACK server list --host "$host" --all-projects -f value -c Status 2>/dev/null) || continue
        local hall=$(printf '%s\n' "$states" | grep -c .)
        local active=$(printf '%s\n' "$states" | grep -c '^ACTIVE$')
        local migrating=$(printf '%s\n' "$states" | grep -c '^MIGRATING$')
        local handled=$(( total - active ))
        [ $handled -lt 0 ] && handled=0
        local paused=$(( hall - active - init_inactive - migrating ))
        [ $paused -lt 0 ] && paused=0
        _power_roll_set_node_num "$host" vms_done $handled
        _power_roll_set_node_num "$host" vms_paused $paused
    done
}

_power_roll_kick()
{
    # Drain (if compute-bearing) and reboot one node. Pauses the job on any
    # gate failure so an operator can decide. Dispatches OpenStack work to the
    # master control node, which holds the credentials.
    local host=$1
    local role=$(jq -r --arg h "$host" '.nodes[]|select(.hostname==$h)|.role' $ROLLING_RESTART_JOB)
    local ip=$(jq -r --arg h "$host" '.nodes[]|select(.hostname==$h)|.ip' $ROLLING_RESTART_JOB)
    local master=$(cubectl node list | head -n1 | awk -F',' '{print $1}')

    # Never take a second node down while another is still away.
    if ! $HEX_SDK cube_cluster_ready ; then
        _power_roll_pause "cluster not ready before rolling $host"
        return 1
    fi
    for n in $(cubectl node list -j | jq -r '.[].ip.management') ; do
        [ "x$n" = "x$ip" ] && continue
        if ! is_sshable $n ; then
            _power_roll_pause "node $n is unreachable; will not take $host down too"
            return 1
        fi
    done

    _power_roll_set_str inflight "$host"
    _power_roll_set_node_num "$host" started $(date +%s)
    _power_roll_set_raw deadline $(( $(date +%s) + ${ROLLING_NODE_TIMEOUT:-3600} ))

    case "$role" in
        *compute*|control-converged|edge-core)
            _power_roll_set_node_status "$host" draining
            echo "evacuating workloads off $host"
            if ! remote_run $master "$HEX_SDK power_node_evacuate $host" ; then
                local stuck=""
                [ -s "$ROLLING_RESTART_DIR/.stuck.$host" ] && stuck=": $(tr '\n' ' ' < "$ROLLING_RESTART_DIR/.stuck.$host")"
                _power_roll_pause "could not live-migrate all workloads off $host${stuck} -- migrate or stop them, then run rolling_restart continue"
                return 1
            fi
            ;;
    esac

    if ! is_sshable $ip ; then
        _power_roll_pause "$host ($ip) is unreachable"
        return 1
    fi

    echo "rebooting $host"
    # Drop a local marker so the node's boot path waits for the cluster to be
    # ready (single-node ceph recovery can take ~20 min) before running the VM
    # restore + relay advance, instead of checking once early and skipping.
    ssh root@$ip "touch /etc/appliance/state/rolling_restart_recover ; echo YES | hex_cli -c reboot" >/dev/null 2>&1
    # Wait (bounded) for the node to drop off the network before flipping to
    # "rebooting", so the reachability-based "bootstrapping" inference can't misfire.
    local _i
    for _i in $(seq 1 120) ; do
        ping -c1 -W2 "$ip" >/dev/null 2>&1 || break
        sleep 2
    done
    _power_roll_set_node_status "$host" rebooting
    return 0
}

# Nova-DB helpers for the roll. Always-sourced (modules glob) so both the drain
# and the dry-run can reach them in any hex_sdk context.

# UUIDs of VMs that cannot live-migrate, in ONE nova DB query instead of a
# per-VM openstack call. PCI/GPU passthrough is the signal (allocated rows in
# pci_devices). Stable for a roll, so callers fetch it once and test membership.
_power_nonmigratable_vms()
{
    $MYSQL -u root -N -D nova -e \
        "SELECT DISTINCT instance_uuid FROM pci_devices WHERE instance_uuid IS NOT NULL" 2>/dev/null
}

# Per-host EFFECTIVE free RAM(MB) and vCPUs from the nova DB (one query). The
# allocation ratios come from compute_nodes, which nova derives from the cubecos
# overcommit tunings (nova.overcommit.cpu/ram.ratio) -- so this reflects the
# tuning without a hard-coded value. Applying them matters because CPU is
# typically overcommitted; a raw vcpus-vcpus_used would go negative and wrongly
# reject every VM. Output: "host ram vcpu".
_power_host_free_capacity()
{
    $MYSQL -u root -N -D nova -e \
        "SELECT hypervisor_hostname, memory_mb * ram_allocation_ratio - memory_mb_used, vcpus * cpu_allocation_ratio - vcpus_used FROM compute_nodes WHERE deleted = 0" 2>/dev/null
}

# Best-effort: could a VM of $ram MB / $vcpu cores fit on some host other than
# $exclude, given the current free-capacity snapshot ($cap)? Approximate --
# ignores cumulative fill during the roll and nova's NUMA/affinity weighing;
# used only for the --dry-run hint.
_power_capacity_fits_elsewhere()
{
    local cap=$1 exclude=$2 ram=$3 vcpu=$4
    echo "$cap" | awk -v ex="$exclude" -v r="$ram" -v c="$vcpu" \
        '$1 != ex && $2 >= r && $3 >= c { ok = 1 } END { exit !ok }'
}

power_roll_plan()
{
    # Dry run: print the roll plan -- node order and, per VM, what would happen
    # (live-migrate vs pause+restore) -- and change nothing. Mirrors the node
    # ordering in power_roll_start.
    local want="$*"
    local master=$(cubectl node list | head -n1 | awk -F',' '{print $1}')
    local ncompute=$(cubectl node -r compute list -j | jq -r '.[].hostname' | grep -c .)
    local nonmig=$(_power_nonmigratable_vms)       # one DB query: passthrough VMs
    local cap=$(_power_host_free_capacity)         # one DB query: per-host free ram/vcpu
    # All active VMs, one DB query: "uuid host ram_mb vcpu name" (no per-VM API).
    local allvms=$($MYSQL -u root -N -D nova -e \
        "SELECT uuid, host, memory_mb, vcpus, display_name FROM instances WHERE deleted = 0 AND vm_state = 'active'" 2>/dev/null)
    local order=$(cubectl node list -j | jq -r --arg want "$want" '
        ($want | split(" ") | map(select(length > 0))) as $sel
        | [ .[] | select(($sel|length)==0 or (.hostname as $h | $sel | index($h))) ]
        | sort_by(
            (if (.role|test("compute")) then 0 elif (.role|test("storage")) then 1 else 2 end))
        | .[] | .hostname + " " + .role')

    echo "Rolling restart plan (dry run) -- no changes will be made."
    echo "Order: compute -> storage -> control; master ($master) rolled last."
    echo
    local host role id vmhost ram vcpu name hostvms reason
    local interrupt=""   # cannot-migrate VMs, collected for the highlighted section
    while read -r host role ; do
        [ -z "$host" ] && continue
        echo "== $host ($role) =="
        hostvms=$(echo "$allvms" | awk -v h="$host" '$2 == h')
        [ -z "$hostvms" ] && { echo "  (no running VMs)" ; continue ; }
        while read -r id vmhost ram vcpu name ; do
            [ -z "$id" ] && continue
            reason=""
            if echo "$nonmig" | grep -qFx "$id" ; then
                reason="PCI/GPU passthrough"
            elif [ "$ncompute" -le 1 ] ; then
                reason="single hypervisor"
            elif ! _power_capacity_fits_elsewhere "$cap" "$host" "$ram" "$vcpu" ; then
                reason="may not fit on another host"
            fi
            if [ -n "$reason" ] ; then
                echo "  $name: cannot live-migrate ($reason)"
                interrupt="${interrupt}    $host / $name  ($reason)"$'\n'
            else
                echo "  $name: live-migrate (no downtime)"
            fi
        done <<< "$hostvms"
    done <<< "$order"
    echo
    if [ -n "$interrupt" ] ; then
        echo "!! ==================================================================="
        echo "!! WILL BE INTERRUPTED -- the following VMs cannot be live-migrated and"
        echo "!! will be SUSPENDED, then restored after their node reboots, incurring"
        echo "!! reboot downtime:"
        echo "!!"
        printf '%s' "$interrupt"
        echo "!!"
        echo "!! Confirming the rolling restart ACKNOWLEDGES this downtime."
        echo "!! ==================================================================="
        echo
    else
        echo "All running VMs can be live-migrated -- no workload downtime expected."
        echo
    fi
    echo "(Capacity is a current snapshot; will decides actual placement at run time.)"
}

# Exit 0 if a roll is currently running or paused. The CLI uses this to fail fast
# (reject a new roll before the dryrun+confirm); power_roll_start re-checks under
# a lock as the real mutex.
# ===================== cluster bootup status =====================
# Full cluster power-up has no driver and cephfs is down during boot, so each node
# self-records its boot phase to a local /run file; power_bootup_status aggregates.
# Phases: powering_up -> bootstrapping -> finalizing -> done (anchored to kernel boot).
BOOTUP_STATUS_FILE=/run/cube_bootup_status

# Record a boot-phase transition locally. Stamps kernel boot time once, then
# appends "<phase> <epoch>".
power_bootup_mark()
{
    local phase=$1
    [ -n "$phase" ] || return 0
    if [ ! -e "$BOOTUP_STATUS_FILE" ] ; then
        local btime=$(awk '/^btime/{print $2}' /proc/stat 2>/dev/null)
        [ -n "$btime" ] && echo "boot $btime" > "$BOOTUP_STATUS_FILE"
    fi
    echo "$phase $(date +%s)" >> "$BOOTUP_STATUS_FILE"
}

# Aggregate every node's local bootup record into a table. Unreachable nodes are
# still powering up (POST/early boot); flags the least-progressed node.
power_bootup_status()
{
    local now=$(date +%s)
    # Read nodes into an array (not a while-read pipe): ssh below eats stdin and
    # would drop every node after the first. </dev/null on the ssh calls too.
    local nodelines line ; mapfile -t nodelines < <(cubectl node list -j 2>/dev/null | jq -r '.[]|"\(.hostname)\t\(.role)\t\(.ip.management)"')
    local rows="" minidx=3 anyactive=0 h role ip
    for line in "${nodelines[@]}" ; do
        IFS=$'\t' read -r h role ip <<< "$line"
        [ -z "$h" ] && continue
        local content="" reach=0
        local committed=0
        if is_sshable "$ip" </dev/null >/dev/null 2>&1 ; then
            reach=1
            content=$(remote_run "$ip" "cat $BOOTUP_STATUS_FILE 2>/dev/null ; [ -e /run/cube_commit_done ] && echo __COMMITTED__" </dev/null)
            echo "$content" | grep -q __COMMITTED__ && committed=1
            content=$(printf '%s\n' "$content" | grep -v __COMMITTED__)
        fi
        local bt=$(echo "$content" | awk '$1=="boot"{print $2}' | tail -1)
        local bs=$(echo "$content" | awk '$1=="bootstrapping"{print $2}' | tail -1)
        local fn=$(echo "$content" | awk '$1=="finalizing"{print $2}' | tail -1)
        local dn=$(echo "$content" | awk '$1=="done"{print $2}' | tail -1)
        # Each phase's own duration, kept separately. Running phase shows now-<start>
        # with trailing '*'; -1 => not reached yet (printed as '-').
        local idx phase pu bsd fnd tot pu_p=0 bs_p=0 fn_p=0 tot_p=0
        if [ "$reach" = 0 ] ; then
            pu=-1 ; bsd=-1 ; fnd=-1 ; tot=-1 ; phase="powering_up" ; idx=0 ; anyactive=1
        else
            if   [ -n "$bs" ] ; then pu=$(( bs - ${bt:-$bs} ))
            elif [ -n "$bt" ] ; then pu=$(( now - bt )) ; pu_p=1
            else pu=-1 ; fi
            if   [ -n "$fn" ] ; then bsd=$(( fn - bs ))
            elif [ -n "$bs" ] ; then bsd=$(( now - bs )) ; bs_p=1
            else bsd=-1 ; fi
            if   [ -n "$dn" ] ; then fnd=$(( dn - fn ))
            elif [ -n "$fn" ] ; then fnd=$(( now - fn )) ; fn_p=1
            else fnd=-1 ; fi
            if   [ -n "$dn" ] ; then phase="done" ; idx=3 ; tot=$(( dn - ${bt:-$dn} ))
            elif [ -n "$fn" ] ; then phase="finalizing" ; idx=2 ; tot=$(( now - ${bt:-$fn} )) ; tot_p=1 ; anyactive=1
            elif [ -n "$bs" ] ; then phase="bootstrapping" ; idx=1 ; tot=$(( now - ${bt:-$bs} )) ; tot_p=1 ; anyactive=1
            elif [ -z "$bt" ] && [ "$committed" = 1 ] ; then phase="done" ; idx=3 ; tot=-1   # up, booted pre-instrumentation (no this-boot record)
            else phase="powering_up" ; idx=0 ; anyactive=1 ; [ -n "$bt" ] && { tot=$(( now - bt )) ; tot_p=1 ; } || tot=-1 ; fi
        fi
        [ "$idx" -lt "$minidx" ] && minidx=$idx
        rows="${rows}${h}\t${pu}\t${pu_p}\t${bsd}\t${bs_p}\t${fnd}\t${fn_p}\t${tot}\t${tot_p}\t${phase}\t${idx}\t${reach}\n"
    done

    local state="complete" ; [ "$anyactive" = 1 ] && state="in progress"
    echo "state:    $state   (* = phase still in progress)"
    echo ""
    printf " %-14s %-11s %-13s %-11s %-11s %-14s %s\n" "node" "powering_up" "bootstrapping" "finalizing" "total" "phase" "note"
    printf "%b" "$rows" | while IFS=$'\t' read -r h pu pup bsd bsp fnd fnp tot totp phase idx reach ; do
        [ -z "$h" ] && continue
        _c() { local s=$1 p=$2 ; [ "$s" -ge 0 ] 2>/dev/null || { echo "-" ; return ; } ; local o="$(( s/60 ))m$(printf %02d $(( s%60 )))s" ; [ "$p" = 1 ] && o="${o}*" ; echo "$o" ; }
        local note=""
        if [ "$reach" = 0 ] ; then note="<- unreachable (POST/early boot)"
        elif [ "$state" = "in progress" ] && [ "$idx" = "$minidx" ] && [ "$phase" != done ] ; then note="<- watch (slowest)"
        fi
        printf " %-14s %-11s %-13s %-11s %-11s %-14s %s\n" "$h" "$(_c "$pu" "$pup")" "$(_c "$bsd" "$bsp")" "$(_c "$fnd" "$fnp")" "$(_c "$tot" "$totp")" "$phase" "$note"
    done
}

power_roll_active()
{
    # A node mid-roll-recovery hasn't mounted cephfs yet, so the shared job.json
    # is unreadable there. The local roll-recover marker (dropped by the kick
    # before reboot, cleared at boot once the cluster is ready) covers that
    # window, so the running roll is detected even on the node being rebooted.
    # The shared job state covers every other node.
    [ -e /etc/appliance/state/rolling_restart_recover ] && return 0
    [ -e "$ROLLING_RESTART_JOB" ] || return 1
    case "$(jq -r .state "$ROLLING_RESTART_JOB" 2>/dev/null)" in
        running|paused) return 0 ;;
        *) return 1 ;;
    esac
}

power_roll_start()
{
    mkdir -p $ROLLING_RESTART_DIR

    # Serialize start across nodes: the check-and-claim must be atomic so two
    # operators triggering from different hosts can't both create a job. The
    # lock is held only over the critical section, then released before the
    # reboot kick; thereafter the job's own state="running" is the mutex.
    (
        flock -x -w 10 200 || { echo "could not acquire rolling-restart lock" >&2 ; exit 1 ; }

        local cur="none"
        [ -e "$ROLLING_RESTART_JOB" ] && cur=$(jq -r .state $ROLLING_RESTART_JOB 2>/dev/null)
        if [ "$cur" = "running" -o "$cur" = "paused" ] ; then
            echo "a rolling restart is already in progress (state: $cur)" >&2
            exit 1
        fi

        if ! $HEX_SDK cube_cluster_ready ; then
            echo "cluster is not ready; refusing to start a rolling restart" >&2
            exit 1
        fi

        # Optional explicit target list (positional args); empty = whole cluster.
        local want="$*"

        # Order: compute -> storage -> control, with the master control node last.
        local master=$(cubectl node list | head -n1 | awk -F',' '{print $1}')
        local nodes=$(cubectl node list -j | jq -c --arg m "$master" --arg want "$want" '
            ($want | split(" ") | map(select(length > 0))) as $sel
            | [ .[]
                | select(($sel | length) == 0 or (.hostname as $h | $sel | index($h)))
                | {hostname: .hostname, role: .role, ip: .ip.management, status: "pending", started: 0, finished: 0, vms_total: 0, vms_done: 0} ]
            | sort_by(
                (if (.role|test("compute")) then 0 elif (.role|test("storage")) then 1 else 2 end),
                (if .hostname==$m then 1 else 0 end))')

        # Reject any requested host that is not a real cluster node.
        if [ -n "$want" ] ; then
            local matched=$(echo "$nodes" | jq -r '.[].hostname')
            for w in $want ; do
                echo "$matched" | grep -qx "$w" || { echo "unknown node: $w" >&2 ; exit 1 ; }
            done
        fi

        jq -n --argjson nodes "$nodes" \
            '{state:"running", inflight:"", deadline:0, reason:"", decision:"", nodes:$nodes}' \
            > $ROLLING_RESTART_JOB.tmp && mv $ROLLING_RESTART_JOB.tmp $ROLLING_RESTART_JOB
    ) 200>"$ROLLING_RESTART_DIR/.lock"
    [ $? -eq 0 ] || return 1

    echo "rolling restart started across $(jq '.nodes|length' $ROLLING_RESTART_JOB) node(s)"
    # Only warn about a self-reboot if this node is actually in the roll; with an
    # explicit target list the operator's node may be excluded. State is shared
    # on cephfs, so progress is followable from any node either way.
    if jq -e --arg h "$HOSTNAME" 'any(.nodes[]; .hostname==$h)' $ROLLING_RESTART_JOB >/dev/null ; then
        echo "NOTE: $HOSTNAME will be rebooted as part of this roll; once it goes down,"
        echo "      run \"cluster rolling_restart status\" from another node to follow progress."
    else
        echo "follow progress with \"cluster rolling_restart status\"."
    fi
    power_roll_advance
}

power_roll_advance()
{
    # Called from each node's boot path. No-op unless a job is running.
    # Finalizes the node that just came back, then kicks the next one.
    local booted=${1:-$HOSTNAME}

    [ -e "$ROLLING_RESTART_JOB" ] || return 0
    [ "$(jq -r .state $ROLLING_RESTART_JOB 2>/dev/null)" = "running" ] || return 0

    local master=$(cubectl node list | head -n1 | awk -F',' '{print $1}')
    local inflight=$(jq -r '.inflight // ""' $ROLLING_RESTART_JOB)

    if [ -n "$inflight" ] && [ "x$inflight" = "x$booted" ] ; then
        # Restore the VMs this node suspended/stopped for its reboot (downtime
        # acknowledged at confirm time). Dispatch to the master (holds creds).
        local arun="$CEPHFS_NOVA_DIR/instances/active_running" vm disp
        if [ -s "$arun" ] ; then
            while read -r vm disp _ ; do
                [ -z "$vm" ] && continue
                Quiet -n remote_run $master "$HEX_SDK power_vm_restore $vm $disp"
            done < "$arun"
            : > "$arun"
        fi
        case "$(jq -r --arg h "$booted" '.nodes[]|select(.hostname==$h)|.role' $ROLLING_RESTART_JOB)" in
            *compute*|control-converged|edge-core)
                Quiet -n remote_run $master "$HEX_SDK power_node_resume $booted" ;;
        esac
        _power_roll_set_node_num "$booted" finished $(date +%s)
        _power_roll_set_node_status "$booted" done
        _power_roll_set_str inflight ""
    fi

    # Only advance once the in-flight node has been finalized. A spurious reboot
    # of any other node must not kick the next one.
    [ -z "$(jq -r '.inflight // ""' $ROLLING_RESTART_JOB)" ] || return 0

    local next=$(jq -r 'first(.nodes[]|select(.status=="pending")|.hostname) // ""' $ROLLING_RESTART_JOB)
    if [ -z "$next" ] ; then
        _power_roll_set_str state done
        echo "rolling restart complete"
        /usr/sbin/hex_log_event -e CLU00005I "interface=system,host=$HOSTNAME,category=cluster,sub=rolling_restart,action=complete"
        return 0
    fi

    _power_roll_kick "$next"
}

power_roll_status()
{
    if [ ! -e "$ROLLING_RESTART_JOB" ] ; then
        echo "no rolling restart job found"
        return 0
    fi

    local state=$(jq -r .state $ROLLING_RESTART_JOB)
    local inflight=$(jq -r '.inflight // ""' $ROLLING_RESTART_JOB)
    local reason=$(jq -r '.reason // ""' $ROLLING_RESTART_JOB)

    echo "state:    $state"
    [ -n "$inflight" ] && echo "inflight: $inflight"
    [ -n "$reason" ] && echo "reason:   $reason"
    if [ "$state" = "running" ] && [ -n "$inflight" ] ; then
        local deadline=$(jq -r '.deadline // 0' $ROLLING_RESTART_JOB)
        if [ "$(date +%s)" -gt "$deadline" ] ; then
            echo "warning:  $inflight has not returned within the expected window (stalled)"
        fi
    fi
    echo ""
    local now=$(date +%s)
    local window=${ROLLING_NODE_TIMEOUT:-3600}
    printf " %-20s %-18s %-9s %-10s %s\n" "node" "role" "status" "vms(m+p/tot)" "elapsed"
    jq -r '.nodes[]|"\(.hostname)\t\(.role)\t\(.status)\t\(.started // 0)\t\(.finished // 0)\t\(.vms_total // 0)\t\(.vms_done // 0)\t\(.vms_paused // 0)\t\(.ip // "")"' $ROLLING_RESTART_JOB | \
        while IFS=$'\t' read -r h r s st fin vt vd vp ip ; do
            # a "rebooting" node that is back on the network is bootstrapping
            [ "$s" = "rebooting" ] && [ -n "$ip" ] && ping -c1 -W1 "$ip" >/dev/null 2>&1 && s="bootstrapping"
            el="-"
            if [ "$st" -gt 0 ] ; then
                end=$fin
                [ "$end" -gt 0 ] || end=$now
                secs=$(( end - st ))
                el=$(printf '%dm%02ds' $(( secs / 60 )) $(( secs % 60 )))
                [ "$fin" -eq 0 ] && [ "$secs" -gt "$window" ] && el="$el (stalled)"
            fi
            vms="-"
            if [ "$s" = "draining" ] ; then
                mig=$(( vd - vp )) ; [ $mig -lt 0 ] && mig=0
                if [ "${vp:-0}" -gt 0 ] ; then vms="${mig}m+${vp}p/$vt" ; else vms="$mig/$vt" ; fi
            fi
            printf " %-20s %-18s %-9s %-10s %s\n" "$h" "$r" "$s" "$vms" "$el"
        done

    # Per-node phase breakdown, each phase's own duration kept separately.
    # '*' = still in progress, '-' = not reached.
    _rollphase() { local a=$1 b=$2 ; [ "${a:-0}" -gt 0 ] 2>/dev/null || { echo "-" ; return ; } ; local e=$b ip=0 ; [ "${b:-0}" -gt 0 ] 2>/dev/null || { e=$now ; ip=1 ; } ; local s=$(( e - a )) ; [ $s -lt 0 ] && s=0 ; local o=$(printf '%dm%02ds' $(( s/60 )) $(( s%60 ))) ; [ $ip = 1 ] && o="${o}*" ; echo "$o" ; }
    # A phase ends at the first later boundary that exists, so a lost intermediate
    # stamp folds into the prior phase and self-corrects instead of ticking '*' forever.
    _firstpos() { local x ; for x in "$@" ; do [ "${x:-0}" -gt 0 ] 2>/dev/null && { echo "$x" ; return ; } ; done ; echo 0 ; }
    echo ""
    printf " %-20s %-10s %-10s %-13s %-11s %-9s\n" "node" "draining" "rebooting" "bootstrapping" "finalizing" "total"
    jq -r '.nodes[]|"\(.hostname)\t\(.started//0)\t\(.finished//0)\t\(.phase_ts.draining//0)\t\(.phase_ts.rebooting//0)\t\(.phase_ts.bootstrapping//0)\t\(.phase_ts.finalizing//0)\t\(.phase_ts.done//0)"' $ROLLING_RESTART_JOB | \
        while IFS=$'\t' read -r h st fin dr rb bs fn dn ; do
            d_ts=$dr ; [ "$d_ts" = 0 ] && d_ts=$st
            e_ts=$dn ; [ "$e_ts" = 0 ] && e_ts=$fin
            printf " %-20s %-10s %-10s %-13s %-11s %-9s\n" "$h" \
                "$(_rollphase "$d_ts" "$(_firstpos "$rb" "$bs" "$fn" "$e_ts")")" \
                "$(_rollphase "$rb" "$(_firstpos "$bs" "$fn" "$e_ts")")" \
                "$(_rollphase "$bs" "$(_firstpos "$fn" "$e_ts")")" \
                "$(_rollphase "$fn" "$e_ts")" \
                "$(_rollphase "$d_ts" "$e_ts")"
        done
}

power_roll_status_json()
{
    # Machine-readable progress for API/UI integration. Projects the job state
    # into the same envelope cube-cos-api uses for firmware rolling upgrade
    # (firmwares.Upgrade / Progress / SystemUpdateProgress), so the Go layer can
    # unmarshal it directly and cos-ui can reuse its existing progress views.
    if [ ! -e "$ROLLING_RESTART_JOB" ] ; then
        echo '{"isRollingApplied":true,"state":"none","reason":"","progresses":[]}'
        return 0
    fi

    # "bootstrapping" is inferred, not stored: the inflight node is bootstrapping
    # once it's back on the network, before it writes "finalizing".
    local _inf _infip _boot=0
    _inf=$(jq -r '.inflight // ""' "$ROLLING_RESTART_JOB")
    if [ -n "$_inf" ] ; then
        _infip=$(jq -r --arg h "$_inf" '.nodes[]|select(.hostname==$h)|.ip // ""' "$ROLLING_RESTART_JOB")
        [ -n "$_infip" ] && ping -c1 -W1 "$_infip" >/dev/null 2>&1 && _boot=1
    fi

    jq --arg boot "$_boot" '
        (.inflight // "") as $inf
        | (.state // "") as $state
        | (.reason // "") as $reason
        | {
            isRollingApplied: true,
            state: $state,
            reason: $reason,
            progresses: [ .nodes[]
                | (($state == "paused") and (.hostname == $inf)) as $failed
                | (.vms_total // 0) as $vt
                | (.vms_done // 0) as $vd
                | (if .status == "draining" then "evacuting vms on host"
                   elif (.status == "rebooting" and .hostname == $inf and $boot == "1") then "bootstrapping"
                   elif .status == "rebooting" then "rebooting"
                   elif .status == "finalizing" then "finalizing"
                   elif .status == "done" then "succeeded"
                   else "pending" end) as $phase
                | {
                    host: .hostname,
                    phase: $phase,
                    status: {
                        current: (if $failed then "failed" else $phase end),
                        isProcessing: (((.status == "draining") or (.status == "rebooting") or (.status == "finalizing")) and ($failed | not)),
                        processPercent: (
                            if .status == "done" then 100
                            elif $failed then 0
                            elif .status == "finalizing" then 90
                            elif .status == "rebooting" then 75
                            elif .status == "draining" then (if $vt > 0 then (($vd / $vt) * 50 | floor) else 25 end)
                            else 0 end),
                        description: (if $failed then $reason else "" end),
                        vmsTotal: $vt,
                        vmsDone: $vd
                    }
                } ]
        }' $ROLLING_RESTART_JOB
}

power_roll_decision()
{
    [ -e "$ROLLING_RESTART_JOB" ] || { echo "no rolling restart in progress" >&2 ; return 1 ; }
    local cur=$(jq -r .state $ROLLING_RESTART_JOB 2>/dev/null)
    # "continue" only applies to a paused roll; "abort" also works on a "running"
    # roll (so a wedged/zombie roll whose driver died is still cleanable).
    if [ "$1" = "continue" ] && [ "$cur" != "paused" ] ; then
        echo "rolling restart is $cur, not paused -- \"continue\" applies only to a paused roll" >&2
        return 1
    fi
    if [ "$1" = "abort" ] && [ "$cur" != "paused" ] && [ "$cur" != "running" ] ; then
        echo "rolling restart is $cur -- nothing to abort" >&2
        return 1
    fi

    case "$1" in
        continue)
            # Reset the node that failed back to a clean pending so the resume
            # re-kicks it first (its status is draining/rebooting, not pending).
            local stuck=$(jq -r '.inflight // ""' $ROLLING_RESTART_JOB)
            if [ -n "$stuck" ] ; then
                _power_roll_set_node_status "$stuck" pending
                _power_roll_set_node_num "$stuck" started 0
                _power_roll_set_node_num "$stuck" vms_total 0
                _power_roll_set_node_num "$stuck" vms_done 0
            fi
            _power_roll_set_str inflight ""
            _power_roll_set_str reason ""
            _power_roll_set_str state running
            power_roll_advance
            ;;
        abort)
            # Re-enable the in-flight node's nova-compute (the drain may have left it
            # disabled) so scheduling resumes.
            local inflight=$(jq -r '.inflight // ""' $ROLLING_RESTART_JOB)
            [ -n "$inflight" ] && Quiet -n $OPENSTACK compute service set --enable "$inflight" nova-compute
            _power_roll_set_str inflight ""
            _power_roll_set_str state aborted
            echo "rolling restart aborted"
            ;;
        *)
            echo "usage: power_roll_decision continue|abort" >&2
            return 1
            ;;
    esac
}

# --- VM pause/restore + host drain/evacuate/resume for the roll -------------
# Pause a non-migratable VM ahead of its host's reboot so the boot path can
# restore it. Prefer state-preserving suspend; fall back to a graceful stop for
# passthrough VMs (libvirt managedsave fails on an assigned device). Echoes the
# disposition ("suspended"|"stopped") for the active_running record.
_power_vm_pause()
{
    local vm=$1 i st
    if $OPENSTACK server suspend "$vm" >/dev/null 2>&1 ; then
        for i in $(seq 1 6) ; do
            [ "$($OPENSTACK server show "$vm" -f value -c status 2>/dev/null)" = SUSPENDED ] && { echo suspended ; return 0 ; }
            sleep 3
        done
    fi
    # suspend did not take (e.g. passthrough) -> clear any ERROR, graceful stop
    st=$($OPENSTACK server show "$vm" -f value -c status 2>/dev/null)
    [ "x$st" = "xERROR" ] && os_nova_instance_reset "$vm"
    $OPENSTACK server stop "$vm" >/dev/null 2>&1
    for i in $(seq 1 12) ; do
        [ "$($OPENSTACK server show "$vm" -f value -c status 2>/dev/null)" = SHUTOFF ] && break
        sleep 3
    done
    echo stopped
}

# Restore a VM by the disposition recorded in active_running (run on host boot).
# Single-node "suspended" resume races cephfs cold-recovery, so recover it in a
# detached background job; multi-node resumes inline.
power_vm_restore()
{
    local vm=$1 disp=$2
    case "$disp" in
        suspended)
            if [ "$(cubectl node list 2>/dev/null | grep -c .)" -le 1 ] ; then
                setsid $HEX_SDK power_vm_resume_async "$vm" >/dev/null 2>&1 &
            else
                $OPENSTACK server resume "$vm" >/dev/null 2>&1
            fi
            ;;
        stopped)   $OPENSTACK server start  "$vm" >/dev/null 2>&1 ;;
        *)         os_nova_instance_reset "$vm" ; os_nova_instance_hardreboot "$vm" ;;
    esac
}

# Detached single-node resume recovery (see power_vm_restore): retry 5x/30s,
# resuming while SUSPENDED and reset+hard-reboot on ERROR.
power_vm_resume_async()
{
    local vm=$1 i st
    for i in $(seq 1 5) ; do
        st=$($OPENSTACK server show "$vm" -f value -c status 2>/dev/null)
        [ "$st" = ACTIVE ] && return 0
        case "$st" in
            SUSPENDED) $OPENSTACK server resume "$vm" >/dev/null 2>&1 ;;
            ERROR)     os_nova_instance_reset "$vm" ; os_nova_instance_hardreboot "$vm" ;;
        esac
        sleep 30
    done
}

power_drain_host()
{
    # Drain $from_host before a planned reboot. Migratable VMs are live-migrated
    # off, up to max_concurrent_live_migrations at a time. nova owns each
    # migration's convergence (auto-converge -> force_complete -> post-copy
    # guarantees completion); the drain never imposes its own deadline or aborts
    # a migration. VMs that cannot live-migrate (PCI/passthrough, etc.) are
    # suspended and recorded for restore on boot; that downtime is acknowledged
    # up front via the CLI dryrun+confirm. A *migratable* VM that nova reports
    # errored is an unacknowledged
    # surprise -> reported via a non-zero return so the caller pauses the roll for
    # an operator. Host-scoped analog of os_pre_failure_host_evacuation_sequential.
    local from_host=${1:-$HOSTNAME}
    local env=${2:-default}
    local server_list_array=( $($OPENSTACK server list --host "$from_host" --all-projects --status ACTIVE -f value -c ID) )
    local host_array=($(cubectl node -r compute list -j | jq -r .[].hostname | grep -v $from_host))
    local num_host=${#host_array[@]}

    if [ ${#server_list_array[@]} -gt 0 ] && [ $num_host -eq 0 ] ; then
        echo "no other compute host to receive workloads from $from_host" >&2
        return 1
    fi

    for i in 1 2 3 ; do
        if _os_pre_failure_host_evacuation $env ; then
            break
        else
            sleep 10
        fi
    done

    # Honor nova's concurrency cap. nova owns each migration's convergence
    # (completion_timeout -> force_complete -> post-copy guarantees completion),
    # so the drain never imposes its own deadline or aborts a migration -- it
    # reacts only to nova's verdict (landed, or nova-reported error).
    local maxconc=$(awk -F= '/^\[/{s=$0} s=="[DEFAULT]" && /^[ \t]*max_concurrent_live_migrations[ \t]*=/{gsub(/[ \t]/,"",$2);print $2;exit}' /etc/nova/nova.conf 2>/dev/null)
    # Default to 3 (config_nova's value) when nova.conf has none; nova enforces its own cap.
    [ -n "$maxconc" ] && [ "$maxconc" -ge 1 ] 2>/dev/null || maxconc=3

    local nonmig=$(_power_nonmigratable_vms)   # one DB query, reused for all VMs
    local tlog=${ROLLING_RESTART_DIR:-/tmp}/drain_timing.${from_host}.log
    : > "$tlog"

    local arun="$CEPHFS_NOVA_DIR/instances/active_running" disp
    mkdir -p "$(dirname "$arun")" ; : > "$arun"

    # Partition: non-migratable VMs are suspended + recorded for restore on boot
    # (downtime acknowledged at confirm time); migratable VMs queue for the pool.
    local sid st host
    local -a pending=() stuck=()
    for sid in ${server_list_array[@]} ; do
        if echo "$nonmig" | grep -qFx "$sid" ; then
            disp=$(_power_vm_pause "$sid")
            echo "$sid $disp" >> "$arun"
            echo "suspend+restore $sid ($disp)"
            echo "$(date +%s) suspend $sid" >> "$tlog"
        else
            pending+=("$sid")
        fi
    done

    # Concurrent pool: up to $maxconc migrations in flight. nova bounds each one's
    # duration (force_complete/post-copy); the drain waits for nova's outcome and
    # never stops a migration itself.
    local -A started=()
    while [ ${#pending[@]} -gt 0 ] || [ ${#started[@]} -gt 0 ] ; do
        while [ ${#started[@]} -lt "$maxconc" ] && [ ${#pending[@]} -gt 0 ] ; do
            sid=${pending[0]} ; pending=("${pending[@]:1}")
            if nova live-migration "$sid" 2>/dev/null ; then
                started[$sid]=$(date +%s)
                echo "${started[$sid]} start $sid (inflight ${#started[@]}/${maxconc})" >> "$tlog"
                echo "migrating $sid off $from_host"
            else
                stuck+=("$sid")   # request rejected (e.g. no valid host)
                echo "$(date +%s) reject $sid" >> "$tlog"
            fi
        done
        sleep 5
        for sid in "${!started[@]}" ; do
            host=$($MYSQL -u root -N -D nova -e "SELECT host FROM instances WHERE uuid='$sid'" 2>/dev/null)
            st=$($MYSQL -u root -N -D nova -e "SELECT status FROM migrations WHERE instance_uuid='$sid' ORDER BY id DESC LIMIT 1" 2>/dev/null)
            if [ -n "$host" ] && [ "$host" != "$from_host" ] ; then
                echo "$(date +%s) done $sid -> $host ($(( $(date +%s) - ${started[$sid]} ))s)" >> "$tlog"
                unset 'started[$sid]'
            elif [ "x$st" = "xerror" -o "x$st" = "xfailed" -o "x$st" = "xcancelled" ] ; then
                echo "$(date +%s) error $sid ($st)" >> "$tlog"
                stuck+=("$sid") ; unset 'started[$sid]'
            fi
            # otherwise still in flight -> nova converges/force-completes it; keep waiting.
        done
    done

    # A migratable VM that nova reports errored is an unacknowledged interruption.
    # Do NOT reboot under it: report so the caller pauses the roll for an operator.
    if [ ${#stuck[@]} -gt 0 ] ; then
        printf '%s\n' "${stuck[@]}" > "${ROLLING_RESTART_DIR:-/tmp}/.stuck.${from_host}"
        echo "could not live-migrate off $from_host (stuck/error, needs operator): ${stuck[*]}" >&2
        return 1
    fi
    rm -f "${ROLLING_RESTART_DIR:-/tmp}/.stuck.${from_host}"
    return 0
}

power_node_evacuate()
{
    # Disable scheduling on a compute host and live-migrate all of its
    # workloads off before a planned reboot. Run on a control node.
    local host=$1

    # No other compute host to receive VMs (e.g. single-node cluster): we
    # cannot live-migrate. Record the host's running VMs to active_running so
    # the boot path (bootstrap_cube_config) restarts them after the reboot,
    # then proceed. Workloads incur reboot downtime, unavoidable with one
    # hypervisor. Same record-then-restore-on-boot path that powercycle uses.
    local others=$(cubectl node -r compute list -j | jq -r '.[].hostname' | grep -v "^$host$" | grep -c .)
    if [ "$others" -eq 0 ] ; then
        mkdir -p $CEPHFS_NOVA_DIR/instances
        $OPENSTACK server list --host "$host" --all-projects --status ACTIVE -f value -c ID > $CEPHFS_NOVA_DIR/instances/active_running
        return 0
    fi

    $OPENSTACK compute service set --disable --disable-reason "rolling restart" $host nova-compute

    # Record the drainable VM count (ACTIVE only -- SHUTOFF/SUSPENDED VMs are not
    # live-migrated, so counting them would make the denominator unreachable) plus
    # the starting on-host total (lets the poll separate migrated from paused), and
    # poll drain progress into the job state.
    local total=$($OPENSTACK server list --host "$host" --all-projects --status ACTIVE -f value -c ID 2>/dev/null | grep -c .)
    local allstart=$($OPENSTACK server list --host "$host" --all-projects -f value -c ID 2>/dev/null | grep -c .)
    _power_roll_set_node_num "$host" vms_total $total
    _power_roll_set_node_num "$host" vms_done 0
    _power_roll_set_node_num "$host" vms_paused 0
    local sentinel=$ROLLING_RESTART_DIR/.draining.$host
    : > $sentinel
    _power_roll_drain_poll "$host" "$total" "$sentinel" "$allstart" &
    local poll_pid=$!

    power_drain_host $host upgrade
    local rc=$?
    rm -f $sentinel ; kill $poll_pid 2>/dev/null ; wait $poll_pid 2>/dev/null

    if [ $rc -ne 0 ] ; then
        $OPENSTACK compute service set --enable $host nova-compute
        return 1
    fi

    _power_roll_set_node_num "$host" vms_done $total
    return 0
}

power_node_resume()
{
    # Re-enable a compute host and clear its instance-HA maintenance flag
    # after a planned reboot. Run on a control node.
    local host=$1

    for u in $($OPENSTACK segment list -f value -c uuid) ; do
        for n in $($OPENSTACK segment host list $u -f value -c name) ; do
            if [ "x$n" = "x$host" ] ; then
                $OPENSTACK segment host update $u $host --on_maintenance False
            fi
        done
    done
    $OPENSTACK compute service set --enable $host nova-compute
}
