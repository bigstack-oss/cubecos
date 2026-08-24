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

ROLLING_DIR=/mnt/cephfs/rolling
ROLLING_JOB=$ROLLING_DIR/job.json
# local roll marker on /store: / is the A/B slot (invisible after an upgrade
# boots the other slot) and cephfs is not readable this early
ROLLING_RECOVER_MARKER=${ROLLING_RECOVER_MARKER:-/store/rolling_recover}

# Locked read-modify-write of the shared job.json, retried across a cephfs/MDS
# failover window. Temp name expanded once per attempt (avoids lost updates).
_power_roll_write()
{
    # every write stamps .heartbeat -- the watchdog's liveness signal
    local i t filter="${@: -1}"
    set -- "${@:1:$(($#-1))}"
    for i in $(seq 1 30) ; do
        t=$ROLLING_JOB.tmp.$$.$i
        if ( flock -w 15 200 || exit 3
             jq "$@" --argjson __hb "$(date +%s)" "($filter) | .heartbeat=\$__hb" $ROLLING_JOB > "$t" && [ -s "$t" ] && mv "$t" $ROLLING_JOB || { rm -f "$t" ; exit 4 ; }
           ) 200>$ROLLING_DIR/.lock 2>/dev/null ; then
            return 0
        fi
        rm -f "$t" 2>/dev/null ; mkdir -p $ROLLING_DIR 2>/dev/null ; sleep 2
    done
    return 1
}

_power_roll_set_str() { _power_roll_write --arg v "$2" ".$1=\$v" ; }

_power_roll_set_raw() { _power_roll_write --argjson v "$2" ".$1=\$v" ; }

# Set node status and stamp phase_ts[status]=now for per-phase durations.
# Kind of the roll currently described by job.json ("restart"/"upgrade"), for
# shared log lines and events that must name the right operation.
_power_roll_kind() { jq -r '.kind // "restart"' $ROLLING_JOB 2>/dev/null || echo restart ; }

# CLI verb for a roll kind. The state machine says "upgrade"; the shipped command
# is `cluster rolling_update`. Operator-facing text only -- log/event tags keep
# the kind verbatim so existing queries still match.
_power_roll_cli_verb()
{
    local k=${1:-$(_power_roll_kind)}
    if [ "x$k" = "xupgrade" ] ; then echo update ; else echo restart ; fi
}

# resolve the dispatch node via the cluster VIP: a static first-node pick keeps
# addressing exactly the host an upgrade reboots first
_power_roll_master()
{
    local _vip _h=""

    source hex_tuning $SETTINGS_TXT cubesys.control.vip
    _vip=$T_cubesys_control_vip
    if [ "x$_vip" = "x" ] ; then
        # non-HA: no VIP, the controller is the only control node
        source hex_tuning $SETTINGS_TXT cubesys.controller.ip
        _vip=$T_cubesys_controller_ip
    fi

    [ -n "$_vip" ] && _h=$(remote_run "$_vip" "hostname" </dev/null 2>/dev/null | tr -d ' \r\n')
    [ -n "$_h" ] && { echo "$_h" ; return 0 ; }
    cubectl node list | head -n1 | awk -F',' '{print $1}'
}

_power_roll_set_node_status()
{
    _power_roll_write --arg h "$1" --arg s "$2" --argjson ts "$(date +%s)" \
        '(.nodes[]|select(.hostname==$h)) |= (.status=$s | .phase_ts=((.phase_ts//{}) + {($s):$ts}))'
    log_info "rolling_$(_power_roll_kind): node $1 -> $2"
    /usr/sbin/hex_log_event -e CLU00009I "interface=system,host=$1,category=cluster,sub=rolling_$(_power_roll_kind),action=phase,phase=$2"
}

# The raw phase_ts write. Also the entry point a peer or a spool-replay uses:
# `hex_sdk _power_roll_write_phase_ts <host> <phase> <epoch>`.
_power_roll_write_phase_ts()
{
    [ -e "$ROLLING_JOB" ] || return 1
    _power_roll_write --arg h "$1" --arg p "$2" --argjson ts "$3" \
        '(.nodes[]|select(.hostname==$h)) |= (.phase_ts=((.phase_ts//{}) + {($p):$ts}))'
}

# Replay locally-buffered stamps to job.json once cephfs is reachable.
_power_roll_flush_phase_ts_spool()
{
    local spool=$1 bh bp bts
    [ -e "$spool" ] || return 0
    while read -r bh bp bts ; do
        [ -n "$bh" ] && _power_roll_write_phase_ts "$bh" "$bp" "$bts"
    done < "$spool"
    rm -f "$spool"
}

# First reachable control peer (not self) -- it has cephfs, so it can stamp for us.
_power_roll_ts_peer()
{
    local self=$(hostname) n
    for n in ${MASTER_CONTROL:-} $(cubectl node list -r control -j 2>/dev/null | jq -r '.[].hostname' 2>/dev/null) ; do
        [ "$n" = "$self" ] && continue
        is_sshable "$n" 2>/dev/null && { echo "$n" ; return 0 ; }
    done
}

# Stamp a phase timestamp without changing .status. job.json lives on cephfs, which
# isn't mounted early in a node's own boot -- so capture the real ts now, then write
# it directly (cephfs up), else delegate to an up peer that has cephfs, else spool
# locally and flush on a later cephfs-up call. Never fatal: the delegate runs in a
# subshell so a peer that Errors/exits (remote_run) can't kill the boot script.
_power_roll_set_phase_ts()
{
    local h=$1 p=$2 ts=$(date +%s)
    local spool=${_POWER_ROLL_TS_SPOOL:-/run/roll_phase_ts.spool}
    if [ -e "$ROLLING_JOB" ] ; then
        _power_roll_flush_phase_ts_spool "$spool"
        _power_roll_write_phase_ts "$h" "$p" "$ts"
        return 0
    fi
    local peer=$(_power_roll_ts_peer)
    if [ -n "$peer" ] ; then
        ( remote_run "$peer" "hex_sdk _power_roll_write_phase_ts $h $p $ts" ) >/dev/null 2>&1 && return 0
    fi
    echo "$h $p $ts" >> "$spool" 2>/dev/null
    return 0
}

_power_roll_set_node_num() { _power_roll_write --arg h "$1" --argjson v "$3" "(.nodes[]|select(.hostname==\$h).$2)=\$v" ; }

_power_roll_pause()
{
    _power_roll_set_str reason "$1"
    _power_roll_set_str state paused
    # release the roll's cluster guards; "continue" re-takes them
    Quiet -n $HEX_SDK ceph_leave_rolling
    echo "rolling $(_power_roll_kind) paused: $1" >&2
    # strip commas/newlines: attrs are comma-separated k=v (as CLU00006W does)
    /usr/sbin/hex_log_event -e CLU00004W "interface=system,host=$HOSTNAME,category=cluster,sub=rolling_$(_power_roll_kind),action=pause,reason=${1//[,$'\n']/ }"
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

_power_roll_api_ready()
{
    # Every control node must actually SERVE the APIs the drain calls, not just
    # listen: neutron/nova bind their port early in startup and drop requests
    # until their workers are up, while haproxy re-enables the rejoined backend
    # after two passing checks. A live-migration pre-check balanced onto one of
    # those marks the instance ERROR (no retry in nova's pre-check path), so
    # gate the next drain on a real response from every node.
    local deadline=$(( $(date +%s) + ${ROLLING_API_READY_TIMEOUT:-600} ))
    local bad
    while : ; do
        bad=""
        for n in $(cubectl node list -j | jq -r '.[].ip.management') ; do
            for p in 9696 8774 ; do
                Quiet timeout 5 curl -s -o /dev/null http://$n:$p/ || bad="$bad $n:$p"
            done
        done
        [ -z "$bad" ] && return 0
        [ $(date +%s) -ge $deadline ] && break
        sleep 10
    done
    echo "api endpoints not serving:$bad"
    return 1
}

_power_roll_kick()
{
    # Drain (if compute-bearing) and reboot one node. Pauses the job on any
    # gate failure so an operator can decide. Dispatches OpenStack work to the
    # master control node, which holds the credentials.
    local host=$1
    local role=$(jq -r --arg h "$host" '.nodes[]|select(.hostname==$h)|.role' $ROLLING_JOB)
    local ip=$(jq -r --arg h "$host" '.nodes[]|select(.hostname==$h)|.ip' $ROLLING_JOB)
    local master=$(_power_roll_master)

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
    local apierr=$(_power_roll_api_ready)
    if [ -n "$apierr" ] ; then
        _power_roll_pause "$apierr -- a rejoined node is still starting; wait, then run rolling_$(_power_roll_cli_verb) continue"
        return 1
    fi

    _power_roll_set_str inflight "$host"
    _power_roll_set_node_num "$host" started $(date +%s)

    # node deadline scales with the VMs to drain (virsh on the target -- no
    # OpenStack on the kick path); ROLLING_NODE_TIMEOUT is the floor
    local _budget=${ROLLING_NODE_TIMEOUT:-2700}
    case "$role" in
        *compute*|control-converged|edge-core)
            local _nvms=$(remote_run $host "virsh list --uuid --state-running 2>/dev/null | grep -c ." </dev/null 2>/dev/null | tr -dc 0-9)
            if [ -n "$_nvms" ] && [ "$_nvms" -gt 0 ] && [ $(( 1500 + _nvms * 120 )) -gt $_budget ] ; then
                _budget=$(( 1500 + _nvms * 120 ))
            fi
            ;;
    esac
    _power_roll_set_raw deadline $(( $(date +%s) + _budget ))

    case "$role" in
        *compute*|control-converged|edge-core)
            _power_roll_set_node_status "$host" draining
            echo "evacuating workloads off $host"
            if ! remote_run $master "$HEX_SDK power_node_evacuate $host" ; then
                local stuck=""
                [ -s "$ROLLING_DIR/.stuck.$host" ] && stuck=": $(tr '\n' ' ' < "$ROLLING_DIR/.stuck.$host")"
                _power_roll_pause "could not live-migrate all workloads off $host${stuck} -- migrate or stop them, then run rolling_$(_power_roll_cli_verb) continue"
                return 1
            fi
            ;;
    esac

    # Hand off the active ceph-mgr before taking its node down: the dashboard
    # wedges on mgr failover, and auto-repair stands down while rolling, so
    # the roll fails it over and verifies/bounces the dashboard itself.
    # UI-only, so a failure is logged, not a pause.
    echo "handing off ceph-mgr/dashboard if active on $host"
    remote_run $master "$HEX_SDK ceph_mgr_dashboard_ensure $host" </dev/null || \
        echo "ceph-mgr dashboard not verified healthy; continuing (cluster check will flag it)"

    if ! is_sshable $ip ; then
        _power_roll_pause "$host ($ip) is unreachable"
        return 1
    fi

    echo "rebooting $host"
    # write "rebooting" BEFORE the reboot for every host: losing the
    # orchestrator after a late write wedges the job on "draining"
    _power_roll_set_node_status "$host" rebooting
    # Drop a local marker so the node's boot path waits for the cluster to be
    # ready (single-node ceph recovery can take ~20 min) before running the VM
    # restore + relay advance, instead of checking once early and skipping.
    ssh root@$ip "touch $ROLLING_RECOVER_MARKER ; echo YES | hex_cli -c reboot" >/dev/null 2>&1
    # Bounded wait for the node to drop off the network. Status is already
    # "rebooting"; this only paces the relay so the reachability-based
    # "bootstrapping" inference can't misfire while the node is still answering.
    local _i
    for _i in $(seq 1 120) ; do
        ping -c1 -W2 "$ip" >/dev/null 2>&1 || break
        sleep 2
    done
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
    # dry run: print node order + per-VM action, change nothing; takes the kind
    # so the plan mirrors power_roll_start's ordering exactly
    local kind=${1:-restart} ; shift 2>/dev/null
    local want="$*"
    local master=$(_power_roll_master)
    local ncompute=$(cubectl node -r compute list -j | jq -r '.[].hostname' | grep -c .)
    local nonmig=$(_power_nonmigratable_vms)       # one DB query: passthrough VMs
    local cap=$(_power_host_free_capacity)         # one DB query: per-host free ram/vcpu
    # All active VMs, one DB query: "uuid host ram_mb vcpu name" (no per-VM API).
    local allvms=$($MYSQL -u root -N -D nova -e \
        "SELECT uuid, host, memory_mb, vcpus, display_name FROM instances WHERE deleted = 0 AND vm_state = 'active'" 2>/dev/null)
    local order=$(cubectl node list -j | jq -r --arg want "$want" --arg m "$master" --arg kind "$kind" '
        ($want | split(" ") | map(select(length > 0))) as $sel
        | [ .[] | select(($sel|length)==0 or (.hostname as $h | $sel | index($h))) ]
        | if $kind == "upgrade" then
              sort_by((if .hostname==$m then 0 else 1 end),
                      (if (.role|test("control")) then 0 elif (.role|test("storage")) then 1 else 2 end))
          else
              sort_by((if (.role|test("compute")) then 0 elif (.role|test("storage")) then 1 else 2 end),
                      (if .hostname==$m then 1 else 0 end))
          end
        | .[] | .hostname + " " + .role')

    if [ "$kind" = upgrade ] ; then
        echo "Rolling update plan (dry run) -- no changes will be made."
        echo "Order: master ($master) first -> control -> storage -> compute."
    else
        echo "Rolling restart plan (dry run) -- no changes will be made."
        echo "Order: compute -> storage -> control; master ($master) rolled last."
    fi
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
    log_info "cluster bootup: $HOSTNAME -> $phase"
    /usr/sbin/hex_log_event -e CLU00009I "interface=system,host=$HOSTNAME,category=cluster,sub=cluster_bootup,action=phase,phase=$phase"
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
            if   [ -n "$fn" ] ; then bsd=$(( fn - ${bs:-$fn} ))
            elif [ -n "$bs" ] ; then bsd=$(( now - bs )) ; bs_p=1
            else bsd=-1 ; fi
            if   [ -n "$dn" ] ; then fnd=$(( dn - ${fn:-$dn} ))
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
    [ -e $ROLLING_RECOVER_MARKER ] && return 0
    [ -e "$ROLLING_JOB" ] || return 1
    case "$(jq -r .state "$ROLLING_JOB" 2>/dev/null)" in
        running|paused) return 0 ;;
        *) return 1 ;;
    esac
}

# Resolve a requested version/filename to a .pkg under /var/update (shared cephfs).
_power_roll_resolve_pkg()
{
    local want=$1 hit
    if [ -z "$want" ] ; then
        echo "usage: rolling_update <version|package.pkg>" >&2 ; return 1
    fi
    [ -f "$want" ] && { echo "$want" ; return 0 ; }
    hit=$(ls -1 /var/update/*.pkg 2>/dev/null | grep -F "$want" | head -1)
    [ -n "$hit" ] || { echo "no package under /var/update matching '$want'" >&2 ; return 1 ; }
    echo "$hit"
}

# Stage the package into every node's inactive slot. hex_install sets next_entry
# to that slot, so each node's ordinary reboot in the roll boots the new build.
# All-or-nothing: a node that fails to stage must not be rebooted.
_power_roll_stage_all()
{
    local pkg=$1 h rc=0
    local -A _pids=()
    # Preflight: verify each node can read the pkg from cephfs, self-heal once via
    # ceph_mount_cephfs, and pause before staging if it still can't -- a wedged
    # cephfs client would otherwise fail its stage mid-flight.
    for h in $(jq -r '.nodes[].hostname' $ROLLING_JOB 2>/dev/null) ; do
        if ! remote_run "$h" "mountpoint -q /mnt/cephfs && test -r $pkg" </dev/null >/dev/null 2>&1 ; then
            log_warning "stage preflight: cephfs/pkg not readable on $h, running ceph_mount_cephfs"
            remote_run "$h" "$HEX_SDK ceph_mount_cephfs" </dev/null >/dev/null 2>&1
            if ! remote_run "$h" "mountpoint -q /mnt/cephfs && test -r $pkg" </dev/null >/dev/null 2>&1 ; then
                _power_roll_pause "cephfs not mounted or $(basename $pkg) not readable on $h; nothing was staged"
                return 1
            fi
        fi
    done
    # Stage every node at once. Each writes its own inactive slot from a
    # read-only package on shared cephfs, so there is nothing to serialize --
    # doing them in turn just multiplies the wait before the roll can start.
    for h in $(jq -r '.nodes[].hostname' $ROLLING_JOB 2>/dev/null) ; do
        echo "staging $(basename $pkg) on $h"
        _power_roll_set_node_status "$h" staging
        remote_run "$h" "hex_install -v update $pkg" >/dev/null 2>&1 &
        _pids[$h]=$!
    done
    for h in "${!_pids[@]}" ; do
        if wait "${_pids[$h]}" ; then
            _power_roll_set_node_status "$h" pending
        else
            log_error "rolling_upgrade: staging $pkg failed on $h"
            _power_roll_set_node_status "$h" stage_failed
            rc=1
        fi
    done
    return $rc
}

# power_roll_start <kind> [<host>... | <pkg>]
#   restart : reboot each node into the SAME slot (optional host targets)
#   upgrade : stage <pkg> into every inactive slot, then the identical roll --
#             staging is the only step an upgrade adds
power_roll_start()
{
    local kind=${1:-restart} ; shift 2>/dev/null
    case "$kind" in
        restart|upgrade) : ;;
        *) echo "power_roll_start: unknown kind '$kind' (restart|upgrade)" >&2 ; return 1 ;;
    esac

    # For an upgrade the package must resolve before anything is claimed.
    local _version=""
    if [ "$kind" = upgrade ] ; then
        _version=$(_power_roll_resolve_pkg "$1") || return 1
        set --                                   # targets are all nodes for an upgrade
    fi

    mkdir -p $ROLLING_DIR
    # The roll owns service state while it runs; background auto-repair must not
    # restart services on a node being drained/rebooted.
    cluster_rolling_marker_set
    # Keep rebooting nodes' OSDs from being marked out for the whole roll.
    Quiet -n $HEX_SDK ceph_enter_rolling

    # Serialize start across nodes: the check-and-claim must be atomic so two
    # operators triggering from different hosts can't both create a job. The
    # lock is held only over the critical section, then released before the
    # reboot kick; thereafter the job's own state="running" is the mutex.
    (
        flock -x -w 10 200 || { echo "could not acquire rolling-restart lock" >&2 ; exit 1 ; }

        local cur="none"
        [ -e "$ROLLING_JOB" ] && cur=$(jq -r .state $ROLLING_JOB 2>/dev/null)
        if [ "$cur" = "running" -o "$cur" = "paused" ] ; then
            echo "a rolling $(jq -r '.kind // "restart"' $ROLLING_JOB 2>/dev/null) is already in progress (state: $cur)" >&2
            exit 1
        fi

        if ! $HEX_SDK cube_cluster_ready ; then
            echo "cluster is not ready; refusing to start a rolling $kind" >&2
            exit 1
        fi

        # Optional explicit target list (positional args); empty = whole cluster.
        local want="$*"

        # Order: compute -> storage -> control, with the master control node last.
        local master=$(_power_roll_master)
        # order differs by kind: restart = compute->storage->control, master
        # LAST (control plane up longest); upgrade = master FIRST (shortest
        # mixed-version window)
        local nodes=$(cubectl node list -j | jq -c --arg m "$master" --arg want "$want" --arg kind "$kind" '
            ($want | split(" ") | map(select(length > 0))) as $sel
            | [ .[]
                | select(($sel | length) == 0 or (.hostname as $h | $sel | index($h)))
                | {hostname: .hostname, role: .role, ip: .ip.management, status: "pending", started: 0, finished: 0, vms_total: 0, vms_done: 0} ]
            | if $kind == "upgrade" then
                  sort_by(
                    (if .hostname==$m then 0 else 1 end),
                    (if (.role|test("control")) then 0 elif (.role|test("storage")) then 1 else 2 end))
              else
                  sort_by(
                    (if (.role|test("compute")) then 0 elif (.role|test("storage")) then 1 else 2 end),
                    (if .hostname==$m then 1 else 0 end))
              end')

        # Reject any requested host that is not a real cluster node.
        if [ -n "$want" ] ; then
            local matched=$(echo "$nodes" | jq -r '.[].hostname')
            for w in $want ; do
                echo "$matched" | grep -qx "$w" || { echo "unknown node: $w" >&2 ; exit 1 ; }
            done
        fi

        jq -n --argjson nodes "$nodes" --arg kind "$kind" --arg version "$_version" \
            '{kind:$kind, version:$version, state:"running", inflight:"", deadline:0, reason:"", decision:"", nodes:$nodes}' \
            > $ROLLING_JOB.tmp && mv $ROLLING_JOB.tmp $ROLLING_JOB
    ) 200>"$ROLLING_DIR/.lock"
    [ $? -eq 0 ] || return 1

    if [ "$kind" = upgrade ] ; then
        if ! _power_roll_stage_all "$_version" ; then
            _power_roll_pause "staging $_version failed; no node was rebooted"
            return 1
        fi
    fi

    echo "rolling $kind started across $(jq '.nodes|length' $ROLLING_JOB) node(s)"
    # Only warn about a self-reboot if this node is actually in the roll; with an
    # explicit target list the operator's node may be excluded. State is shared
    # on cephfs, so progress is followable from any node either way.
    if jq -e --arg h "$HOSTNAME" 'any(.nodes[]; .hostname==$h)' $ROLLING_JOB >/dev/null ; then
        echo "NOTE: $HOSTNAME will be rebooted as part of this roll; once it goes down,"
        echo "      run \"cluster rolling_$(_power_roll_cli_verb $kind) status_watch\" from another node to follow progress."
    else
        echo "follow progress with \"cluster rolling_$(_power_roll_cli_verb $kind) status_watch\"."
    fi
    # arm only now that the job exists (a tick seeing no job self-stops)
    _power_roll_watchdog_arm
    power_roll_advance
}

# Arm/disarm the stall watchdog on control-capable nodes (the only possible
# VIP holders). Runtime start/stop only; the boot path re-arms mid-roll.
_power_roll_watchdog_arm()
{
    local _h
    for _h in $(cubectl node list -r control -j 2>/dev/null | jq -r '.[].hostname' 2>/dev/null) ; do
        ( remote_run "$_h" "systemctl start hex-roll-watchdog.timer" ) >/dev/null 2>&1
    done
}

_power_roll_watchdog_disarm()
{
    local _h
    for _h in $(cubectl node list -r control -j 2>/dev/null | jq -r '.[].hostname' 2>/dev/null) ; do
        ( remote_run "$_h" "systemctl stop hex-roll-watchdog.timer" ) >/dev/null 2>&1
    done
}

# Kind of the roll this node is currently part of, or empty. The boot path uses
# this instead of local markers: job.json is cluster-wide and survives the
# reboot, whereas /run and the A/B root partition do not.
power_roll_kind_active()
{
    # cephfs may not be mounted this early; fall back to the local kick marker
    # -- guessing "no roll" would run the full cluster check on a settling MDS
    if [ ! -r "$ROLLING_JOB" ] ; then
        [ -e $ROLLING_RECOVER_MARKER ] && echo restart
        return 0
    fi
    [ "$(jq -r .state $ROLLING_JOB 2>/dev/null)" = "running" ] || return 0
    jq -e --arg h "$HOSTNAME" 'any(.nodes[]; .hostname==$h)' $ROLLING_JOB >/dev/null 2>&1 || return 0
    _power_roll_kind
}

power_roll_advance()
{
    # Called from each node's boot path. No-op unless a job is running.
    # Finalizes the node that just came back, then kicks the next one.
    local booted=${1:-$HOSTNAME}

    [ -e "$ROLLING_JOB" ] || return 0
    [ "$(jq -r .state $ROLLING_JOB 2>/dev/null)" = "running" ] || return 0

    # a control node booting mid-roll re-arms its own timer
    is_control_node && Quiet -n systemctl start hex-roll-watchdog.timer

    local master=$(_power_roll_master)
    local inflight=$(jq -r '.inflight // ""' $ROLLING_JOB)

    if [ -n "$inflight" ] && [ "x$inflight" = "x$booted" ] ; then
        # Restore the VMs this node suspended/stopped for its reboot (downtime
        # acknowledged at confirm time). Dispatch to the master (holds creds).
        local arun="$CLUSTER_ACTIVE_RUNNING" vm disp
        if [ -s "$arun" ] ; then
            while read -r vm disp _ ; do
                [ -z "$vm" ] && continue
                Quiet -n remote_run $master "$HEX_SDK power_vm_restore $vm $disp"
            done < "$arun"
            : > "$arun"
        fi
        case "$(jq -r --arg h "$booted" '.nodes[]|select(.hostname==$h)|.role' $ROLLING_JOB)" in
            *compute*|control-converged|edge-core)
                Quiet -n remote_run $master "$HEX_SDK power_node_resume $booted" ;;
        esac
        _power_roll_set_node_num "$booted" finished $(date +%s)
        _power_roll_set_node_status "$booted" done
        # reconcile as each node lands (a drain that lost its orchestrator never
        # reaches roll end); only VMs with a running domain are reset
        Quiet -n $HEX_SDK power_vm_reconcile_error_state "$booted"
        # Consume the local kick marker. It is what the early boot path (before
        # cephfs is up) uses to know this boot belongs to a roll; left behind it
        # would make every later boot look like one.
        rm -f $ROLLING_RECOVER_MARKER
        # Same reasoning for the drain record: stale, it would scope the next
        # roll's reconcile against VMs this roll moved.
        rm -f "${ROLLING_DIR:-/tmp}/.drained.${booted}"
        _power_roll_set_str inflight ""
    fi

    # Only advance once the in-flight node has been finalized. A spurious reboot
    # of any other node must not kick the next one.
    [ -z "$(jq -r '.inflight // ""' $ROLLING_JOB)" ] || return 0

    local next=$(jq -r 'first(.nodes[]|select(.status=="pending")|.hostname) // ""' $ROLLING_JOB)
    if [ -z "$next" ] ; then
        _power_roll_set_str state done
        cluster_rolling_marker_clear
        Quiet -n $HEX_SDK ceph_leave_rolling
        _power_roll_watchdog_disarm
        # The full check_repair pass belongs here -- when the ROLL is done --
        # not when a single node's boot is done. Running it mid-roll evaluates a
        # cluster with a node deliberately down and tries to "repair" it.
        Quiet -n $HEX_SDK cluster_check_repair_async
        echo "rolling $(_power_roll_kind) complete"
        /usr/sbin/hex_log_event -e CLU00005I "interface=system,host=$HOSTNAME,category=cluster,sub=rolling_$(_power_roll_kind),action=complete"
        return 0
    fi

    _power_roll_kick "$next"
}

power_roll_status()
{
    if [ ! -e "$ROLLING_JOB" ] ; then
        echo "no rolling job found"
        return 0
    fi

    local state=$(jq -r .state $ROLLING_JOB)
    local inflight=$(jq -r '.inflight // ""' $ROLLING_JOB)
    local reason=$(jq -r '.reason // ""' $ROLLING_JOB)

    echo "state:    $state"
    [ -n "$inflight" ] && echo "inflight: $inflight"
    [ -n "$reason" ] && echo "reason:   $reason"
    if [ "$state" = "running" ] && [ -n "$inflight" ] ; then
        local deadline=$(jq -r '.deadline // 0' $ROLLING_JOB)
        if [ "$(date +%s)" -gt "$deadline" ] ; then
            echo "warning:  $inflight has not returned within the expected window (stalled)"
        fi
    fi
    echo ""
    local now=$(date +%s)
    local window=${ROLLING_NODE_TIMEOUT:-2700}
    printf " %-20s %-18s %-9s %-10s %s\n" "node" "role" "status" "vms(m+p/tot)" "elapsed"
    jq -r '.nodes[]|"\(.hostname)\t\(.role)\t\(.status)\t\(.started // 0)\t\(.finished // 0)\t\(.vms_total // 0)\t\(.vms_done // 0)\t\(.vms_paused // 0)\t\(.ip // "")"' $ROLLING_JOB | \
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
    jq -r '.nodes[]|"\(.hostname)\t\(.started//0)\t\(.finished//0)\t\(.phase_ts.draining//0)\t\(.phase_ts.rebooting//0)\t\(.phase_ts.bootstrapping//0)\t\(.phase_ts.finalizing//0)\t\(.phase_ts.done//0)"' $ROLLING_JOB | \
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
    if [ ! -e "$ROLLING_JOB" ] ; then
        echo '{"isRollingApplied":true,"state":"none","reason":"","progresses":[]}'
        return 0
    fi

    # "bootstrapping" is inferred, not stored: the inflight node is bootstrapping
    # once it's back on the network, before it writes "finalizing".
    local _inf _infip _boot=0
    _inf=$(jq -r '.inflight // ""' "$ROLLING_JOB")
    if [ -n "$_inf" ] ; then
        _infip=$(jq -r --arg h "$_inf" '.nodes[]|select(.hostname==$h)|.ip // ""' "$ROLLING_JOB")
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
                # $phase is what the UI displays -- keep it identical to the CLI
                # status words ("bootstrapping" is inferred the same way)
                | (if (.status == "rebooting" and .hostname == $inf and $boot == "1") then "bootstrapping"
                   else (.status // "pending") end) as $phase
                # $current keeps the vocabulary the API itself uses -- the UI
                # completion logic keys off "succeeded"/"failed", so it is NOT
                # the label. Note: no apostrophes in this program -- it is a
                # single-quoted shell string, so one would end it early.
                | (if $failed then "failed"
                   elif .status == "done" then "succeeded"
                   elif .status == "stage_failed" then "failed"
                   else $phase end) as $current
                | {
                    host: .hostname,
                    phase: $phase,
                    status: {
                        current: $current,
                        isProcessing: (((.status == "staging") or (.status == "draining") or (.status == "rebooting") or (.status == "finalizing")) and ($failed | not)),
                        processPercent: (
                            if .status == "done" then 100
                            elif $failed or .status == "stage_failed" then 0
                            elif .status == "staging" then 10
                            elif .status == "finalizing" then 90
                            elif .status == "rebooting" then 75
                            elif .status == "draining" then (if $vt > 0 then (($vd / $vt) * 50 | floor) else 25 end)
                            else 0 end),
                        description: (if $failed then $reason else "" end),
                        vmsTotal: $vt,
                        vmsDone: $vd
                    }
                } ]
        }' $ROLLING_JOB
}

# 0 if node $1's ACTIVE firmware already matches the roll target (commit in
# .version) -- it upgraded before/during a pause. Unreachable/mismatch => 1.
_power_roll_node_on_target()
{
    local node=$1 target
    target=$(jq -r '.version // ""' $ROLLING_JOB 2>/dev/null | grep -oE '[0-9a-f]{7,}' | tail -1)
    [ -n "$target" ] || return 1
    is_sshable "$node" || return 1
    remote_run "$node" "hex_cli -c firmware list 2>/dev/null | grep -i active" </dev/null 2>/dev/null | grep -q "$target"
}

power_roll_decision()
{
    [ -e "$ROLLING_JOB" ] || { echo "no rolling job in progress" >&2 ; return 1 ; }
    local cur=$(jq -r .state $ROLLING_JOB 2>/dev/null)
    # "continue" only applies to a paused roll; "abort" also works on a "running"
    # roll (so a wedged/zombie roll whose driver died is still cleanable).
    if [ "$1" = "continue" ] && [ "$cur" != "paused" ] ; then
        echo "rolling $(_power_roll_kind) is $cur, not paused -- \"continue\" applies only to a paused roll" >&2
        return 1
    fi
    if [ "$1" = "abort" ] && [ "$cur" != "paused" ] && [ "$cur" != "running" ] ; then
        echo "rolling $(_power_roll_kind) is $cur -- nothing to abort" >&2
        return 1
    fi

    case "$1" in
        continue)
            local stuck=$(jq -r '.inflight // ""' $ROLLING_JOB)
            if [ -n "$stuck" ] ; then
                if _power_roll_node_on_target "$stuck" ; then
                    # already on target -- record done, don't re-drain+reboot it.
                    log_info "continue: $stuck already on target firmware -- marking done"
                    _power_roll_set_node_status "$stuck" done
                    _power_roll_set_node_num "$stuck" finished $(date +%s)
                else
                    # unfinished: reset to pending so the resume re-kicks it first.
                    _power_roll_set_node_status "$stuck" pending
                    _power_roll_set_node_num "$stuck" started 0
                    _power_roll_set_node_num "$stuck" vms_total 0
                    _power_roll_set_node_num "$stuck" vms_done 0
                fi
            fi
            _power_roll_set_str inflight ""
            _power_roll_set_str reason ""
            # Zero the stale deadline before state=running so a watchdog tick can't
            # re-pause on it (watchdog skips deadline=0; next _kick sets a fresh one).
            _power_roll_set_raw deadline 0
            _power_roll_set_str state running
            # re-take the guards the pause released; disarm the stale watchdog
            # timer before re-arming so it can't fire on old state.
            Quiet -n $HEX_SDK ceph_enter_rolling
            _power_roll_watchdog_disarm
            _power_roll_watchdog_arm
            power_roll_advance
            ;;
        abort)
            # Re-enable the in-flight node's nova-compute (the drain may have left it
            # disabled) so scheduling resumes.
            local inflight=$(jq -r '.inflight // ""' $ROLLING_JOB)
            [ -n "$inflight" ] && Quiet -n $OPENSTACK compute service set --enable "$inflight" nova-compute
            _power_roll_set_str inflight ""
            _power_roll_set_str state aborted
            # release the guards the roll took (auto-repair standdown marker,
            # mon_osd_down_out_interval) -- neither should outlive the roll
            cluster_rolling_marker_clear
            Quiet -n $HEX_SDK ceph_leave_rolling
            _power_roll_watchdog_disarm
            echo "rolling $(_power_roll_kind) aborted"
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

# reset nova-ERROR VMs whose domain is actually running on the recorded host
# (stale records from a killed orchestrator); anything else is logged for a human
power_vm_reconcile_error_state()
{
    local scope_host=${1:-} dryrun=${2:-} _id _host _running _state _reset=0 _real=0 _skip=0

    local _errs=$($OPENSTACK server list --all-projects --status ERROR \
                    -f value -c ID -c Host 2>/dev/null)
    [ -z "$_errs" ] && return 0

    # Scope to the VMs the named host's drain actually moved. Without a drain
    # record there is nothing attributable to this node, so do nothing rather
    # than fall back to touching every ERROR VM in the cluster.
    if [ -n "$scope_host" ] ; then
        local _drained="${ROLLING_DIR:-/tmp}/.drained.${scope_host}"
        if [ ! -s "$_drained" ] ; then
            log_info "vm_reconcile: no drain record for $scope_host, nothing to reconcile"
            return 0
        fi
        _errs=$(echo "$_errs" | grep -Ff <(cut -d' ' -f1 "$_drained") - 2>/dev/null)
        [ -z "$_errs" ] && return 0
    fi

    # uuid<space>host for every running domain, gathered once per compute node
    _running=$(for _h in $(cubectl node list -r compute -j 2>/dev/null | jq -r '.[].hostname' 2>/dev/null) ; do
                   remote_run "$_h" "virsh list --uuid --state-running 2>/dev/null" </dev/null \
                     | grep -oE '[0-9a-f-]{36}' | sed "s/\$/ $_h/"
               done)

    while read -r _id _host ; do
        [ -z "$_id" ] && continue
        _state=$(echo "$_running" | awk -v i="$_id" '$1==i{print $2}')
        if [ -z "$_state" ] ; then
            log_warning "vm_reconcile: $_id ERROR and no running domain -- real failure, left alone"
            _real=$((_real+1))
        elif [ "x$_state" != "x$_host" ] ; then
            log_warning "vm_reconcile: $_id running on $_state but nova says $_host -- left alone"
            _skip=$((_skip+1))
        elif [ -n "$dryrun" ] ; then
            log_info "vm_reconcile: would reset $_id (running on $_state, stale ERROR)"
            _reset=$((_reset+1))
        else
            if Quiet -n $OPENSTACK server set --state active "$_id" ; then
                log_info "vm_reconcile: reset $_id to active (domain running on $_state)"
                hex_log_event -e BSP00012I "interface=system,host=$HOSTNAME,service=power,vm=$_id"
                _reset=$((_reset+1))
            else
                log_warning "vm_reconcile: reset failed for $_id"
            fi
        fi
    done <<< "$_errs"

    log_info "vm_reconcile: $_reset stale, $_real real failure(s), $_skip host-mismatch"
    return 0
}

# Roll stall enforcement (hex-roll-watchdog.timer, armed only during a roll):
# pause past the node deadline, or on heartbeat silence in write-constant
# phases (reboot/boot phases are deadline-only). Only the VIP holder acts;
# a trip also runs the per-node stale-ERROR reconcile.
power_roll_watchdog()
{
    is_control_node || return 0

    # Every ticking node stops its own timer when its roll is gone (paused
    # stays armed; "continue" re-arms). Only the VIP holder acts below.
    local _state=""
    [ -e "$ROLLING_JOB" ] && _state=$(jq -r '.state // ""' $ROLLING_JOB 2>/dev/null)
    [ "$_state" = "paused" ] && return 0
    [ "$_state" != "running" ] && Quiet -n systemctl stop hex-roll-watchdog.timer

    # Everything past here is a single actor's job: only the VIP holder acts.
    local _vip
    source hex_tuning $SETTINGS_TXT cubesys.control.vip
    _vip=$T_cubesys_control_vip
    [ -n "$_vip" ] || return 0                        # non-HA: boot paths own recovery
    ip -o addr show 2>/dev/null | grep -qw "$_vip" || return 0

    if [ "$_state" != "running" ] ; then
        # sweep the roll's stale osd-out pin (an admin's own value is left alone)
        if timeout 20 ceph config dump 2>/dev/null | grep -qE 'mon_osd_down_out_interval[[:space:]]+3600\b' ; then
            log_warning "roll_watchdog: stale mon_osd_down_out_interval=3600 with no active roll -- clearing"
            Quiet -n $HEX_SDK ceph_leave_rolling
        fi
        return 0
    fi

    local now=$(date +%s)
    local deadline=$(jq -r '.deadline // 0' $ROLLING_JOB)
    local hb=$(jq -r '.heartbeat // 0' $ROLLING_JOB)
    local inflight=$(jq -r '.inflight // ""' $ROLLING_JOB)
    local phase=""
    [ -n "$inflight" ] && phase=$(jq -r --arg h "$inflight" '.nodes[]|select(.hostname==$h)|.status // ""' $ROLLING_JOB)

    if [ "$deadline" -gt 0 ] && [ "$now" -gt "$deadline" ] ; then
        log_warning "roll_watchdog: $inflight over deadline by $(( now - deadline ))s (phase: ${phase:-unknown})"
        _power_roll_pause "watchdog: $inflight exceeded its ${ROLLING_NODE_TIMEOUT:-2700}s node deadline (phase: ${phase:-unknown})"
        [ -n "$inflight" ] && Quiet -n $HEX_SDK power_vm_reconcile_error_state "$inflight"
        return 0
    fi

    local quiet=0
    case "$phase" in
        draining) quiet=600 ;;
        staging)  quiet=900 ;;
        *)        return 0 ;;
    esac
    if [ "$hb" -gt 0 ] && [ $(( now - hb )) -gt $quiet ] ; then
        log_warning "roll_watchdog: heartbeat silent $(( now - hb ))s while $inflight is $phase"
        _power_roll_pause "watchdog: no orchestrator heartbeat for $(( now - hb ))s while $inflight is $phase"
        Quiet -n $HEX_SDK power_vm_reconcile_error_state "$inflight"
    fi
}

# Shared cephfs record of VMs running before a cluster poweroff/powercycle, written
# up front by power_record_running_vms so the master can read it at boot-end.
# Lives with the roll job, not under nova/instances -- instances_path is local now.
CLUSTER_ACTIVE_RUNNING=$ROLLING_DIR/active_running

# Record the running VMs for boot-end restore, up front and before any teardown --
# where the API is healthy and reliably lists every VM. Recording reactively inside
# the per-host cube_cluster_stop (during shutdown, under API load) let the nova query
# blip empty and silently skip the record, leaving power_restore_recorded_vms nothing
# to restore. Retry the query and write atomically so a transient miss can't lose it.
power_record_running_vms()
{
    is_control_node || return 0
    mountpoint -q /mnt/cephfs || return 0
    local _active _try _vm
    for _try in 1 2 3 4 5 ; do
        _active=$($HEX_SDK os_nova_list id status powerstate 2>/dev/null | grep -i 'active running' | cut -d' ' -f1)
        [ -n "$_active" ] && break
        sleep 3
    done
    [ -n "$_active" ] || return 0
    mkdir -p "$CEPHFS_NOVA_DIR/instances"
    : > "$CLUSTER_ACTIVE_RUNNING.tmp"
    for _vm in $_active ; do echo "$_vm stopped" >> "$CLUSTER_ACTIVE_RUNNING.tmp" ; done
    mv -f "$CLUSTER_ACTIVE_RUNNING.tmp" "$CLUSTER_ACTIVE_RUNNING"
    log_info "cluster power: recorded $(printf '%s\n' $_active | grep -c .) running VMs for boot-end restore"
}

# Restore recorded VMs to their prior running state. Must run from the boot-end
# check_repair (after nova/cinder/ceph and cephfs have recovered). Idempotent: skips
# already-ACTIVE VMs, resets+re-drives the rest; clears the record once all are back.
power_restore_recorded_vms()
{
    is_control_node || return 0
    [ -s "$CLUSTER_ACTIVE_RUNNING" ] || return 0
    local i disp st _pending=0 _total=0 _restarted=0
    while read -r i disp _ ; do
        [ -z "$i" ] && continue
        _total=$((_total+1))
        st=$($OPENSTACK server show "$i" -f value -c status 2>/dev/null)
        [ "$st" = ACTIVE ] && continue
        [ "$st" = ERROR ] && os_nova_instance_reset "$i"
        log_info "cluster bootup: restoring VM $i (disposition=${disp:-hardreboot}, was status=${st:-unknown})"
        power_vm_restore "$i" "$disp"
        _restarted=$((_restarted+1))
        _pending=1
    done < "$CLUSTER_ACTIVE_RUNNING"
    [ $_total -gt 0 ] && {
        log_info "cluster bootup: VM restore -- $_restarted restarted, $((_total-_restarted)) already active, of $_total recorded"
        /usr/sbin/hex_log_event -e CLU00010I "interface=system,host=$HOSTNAME,category=cluster,sub=cluster_bootup,action=vm_restore,recorded=$_total,restarted=$_restarted,already_active=$((_total-_restarted))"
    }
    [ $_pending -eq 0 ] && rm -f "$CLUSTER_ACTIVE_RUNNING"
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
    local server_list_array=( $($OPENSTACK server list --host "$from_host" --all-projects --status ACTIVE -f value -c ID) )
    local host_array=($(cubectl node -r compute list -j | jq -r .[].hostname | grep -v $from_host))
    local num_host=${#host_array[@]}

    if [ ${#server_list_array[@]} -gt 0 ] && [ $num_host -eq 0 ] ; then
        echo "no other compute host to receive workloads from $from_host" >&2
        return 1
    fi

    # repair+verify the live-migration path. This is the only gate covering
    # the FIRST drain of a roll (no boot has happened yet) and drains released
    # by a compute-node boot (the boot-path gate is an is_control_node no-op
    # there); it runs on the master via power_node_evacuate, so it always
    # gates. Best-effort -- the drain proceeds regardless and reacts only to
    # nova's per-migration verdicts.
    Quiet -n $HEX_SDK live_migration_gate 120 "$from_host" repair

    # Hand off the active cephfs MDS before this host reboots (symmetric with VM
    # evacuation): the co-located mon dying defers failover ~60s, stalling cephfs.
    # Via $HEX_SDK so the sub-invocation sources sdk_ceph (this module runs under
    # MOD=power, which does not source sdk_ceph -- a bare call is undefined).
    Quiet -n $HEX_SDK ceph_mds_evacuate_host "$from_host"
    # Same for the OVN SB master (see ovn_sb_evacuate_host).
    Quiet -n $HEX_SDK ovn_sb_evacuate_host "$from_host"

    # Honor nova's concurrency cap. nova owns each migration's convergence
    # (completion_timeout -> force_complete -> post-copy guarantees completion),
    # so the drain never imposes its own deadline or aborts a migration -- it
    # reacts only to nova's verdict (landed, or nova-reported error).
    local maxconc=$(awk -F= '/^\[/{s=$0} s=="[DEFAULT]" && /^[ \t]*max_concurrent_live_migrations[ \t]*=/{gsub(/[ \t]/,"",$2);print $2;exit}' /etc/nova/nova.conf 2>/dev/null)
    # Default to 3 (config_nova's value) when nova.conf has none; nova enforces its own cap.
    [ -n "$maxconc" ] && [ "$maxconc" -ge 1 ] 2>/dev/null || maxconc=3

    local nonmig=$(_power_nonmigratable_vms)   # one DB query, reused for all VMs
    local tlog=${ROLLING_DIR:-/tmp}/drain_timing.${from_host}.log
    : > "$tlog"

    local arun="$CLUSTER_ACTIVE_RUNNING" disp
    mkdir -p "$(dirname "$arun")" ; : > "$arun"

    # Partition: non-migratable VMs are suspended + recorded for restore on boot
    # (downtime acknowledged at confirm time); migratable VMs queue for the pool.
    # Suspending a VM is tenant downtime. A restart confirms that downtime up
    # front, so it may suspend+restore what cannot migrate. An upgrade never has:
    # it pauses the roll and leaves the VM running for the operator to decide.
    local _kind=$(_power_roll_kind)
    local sid st host
    local -a pending=() stuck=() nomove=()
    for sid in ${server_list_array[@]} ; do
        if echo "$nonmig" | grep -qFx "$sid" ; then
            if [ "$_kind" = upgrade ] ; then
                nomove+=("$sid")
                continue
            fi
            disp=$(_power_vm_pause "$sid")
            echo "$sid $disp" >> "$arun"
            echo "suspend+restore $sid ($disp)"
            echo "$(date +%s) suspend $sid" >> "$tlog"
        else
            pending+=("$sid")
        fi
    done

    # Upgrade: refuse to take the host down rather than interrupt a VM that
    # cannot live-migrate.
    if [ ${#nomove[@]} -gt 0 ] ; then
        printf '%s\n' "${nomove[@]}" > "${ROLLING_DIR:-/tmp}/.stuck.${from_host}"
        log_error "rolling_upgrade drain: $from_host has ${#nomove[@]} VM(s) that cannot live-migrate (${nomove[*]}); refusing to suspend them"
        /usr/sbin/hex_log_event -e CLU00006W "interface=system,host=$from_host,category=cluster,sub=rolling_upgrade,action=migrate_rejected,phase=nonmigratable,count=${#nomove[@]}"
        echo "cannot live-migrate off $from_host (needs operator): ${nomove[*]}" >&2
        return 1
    fi

    # Event marks the step; the per-VM log_info/log_error lines below carry the detail.
    # The VMs this drain touches. Recorded up front so the post-boot reconcile can
    # scope itself to them instead of every ERROR VM in the cluster.
    [ ${#server_list_array[@]} -gt 0 ] && printf '%s\n' "${server_list_array[@]}" > "${ROLLING_DIR:-/tmp}/.drained.${from_host}"
    local _t0=$(date +%s) _nmig=$(( ${#server_list_array[@]} - ${#pending[@]} )) _migrated=0
    log_info "rolling_$_kind drain: starting on $from_host (${#server_list_array[@]} VMs: ${#pending[@]} migratable, $_nmig suspend+restore, maxconc=$maxconc)"
    /usr/sbin/hex_log_event -e CLU00007I "interface=system,host=$from_host,category=cluster,sub=rolling_$_kind,action=drain_start,total=${#server_list_array[@]},migratable=${#pending[@]},nonmigratable=$_nmig"

    # Concurrent pool: up to $maxconc migrations in flight. nova bounds each one's
    # duration (force_complete/post-copy); the drain waits for nova's outcome and
    # never stops a migration itself.
    local -A started=()
    while [ ${#pending[@]} -gt 0 ] || [ ${#started[@]} -gt 0 ] ; do
        while [ ${#started[@]} -lt "$maxconc" ] && [ ${#pending[@]} -gt 0 ] ; do
            sid=${pending[0]} ; pending=("${pending[@]:1}")
            # Capture task_state (fast DB read, no API load) so a rejection's cause is
            # visible in the log: a non-None task_state points at a re-migrated-too-soon race.
            local _tsb=$($MYSQL -u root -N -D nova -e "SELECT task_state FROM instances WHERE uuid='$sid'" 2>/dev/null)
            # Retry a rejected request (transient "no valid host" is common under
            # burst); capture the error to the log instead of swallowing it.
            local _mtry _merr _mok=0
            # A VM that is still finishing an INBOUND migration -- one the
            # previous node's drain just moved here -- is rejected with 409
            # "task_state migrating". That is transient by definition and only
            # needs waiting out, unlike a real rejection (no valid host, etc).
            # Give it a longer, more patient budget so a node that received VMs
            # moments ago can still be drained.
            for _mtry in $(seq 1 12) ; do
                if _merr=$(nova live-migration "$sid" 2>&1) ; then _mok=1 ; break ; fi
                echo "$(date +%s) migrate-retry $sid attempt=$_mtry: ${_merr//$'\n'/ }" >> "$tlog"
                log_warning "rolling_$_kind drain: live-migration of $sid off $from_host attempt=$_mtry rejected (task_state=${_tsb:-None}): ${_merr//$'\n'/ }"
                case "$_merr" in
                    *"task_state migrating"*|*"task_state"*"migrat"*)
                        sleep 15 ;;   # inbound migration settling; wait it out
                    *)
                        [ $_mtry -ge 3 ] && break   # a real rejection: fail fast
                        sleep 5 ;;
                esac
            done
            if [ "$_mok" = 1 ] ; then
                started[$sid]=$(date +%s)
                echo "${started[$sid]} start $sid (inflight ${#started[@]}/${maxconc})" >> "$tlog"
                echo "migrating $sid off $from_host"
                log_info "rolling_restart drain: migrating $sid off $from_host (task_state_before=${_tsb:-None}, inflight ${#started[@]}/${maxconc})"
            else
                stuck+=("$sid")   # rejected after retries -- reason logged above
                echo "$(date +%s) reject $sid (after 3 attempts): ${_merr//$'\n'/ }" >> "$tlog"
                log_error "rolling_restart drain: live-migration of $sid off $from_host REJECTED after 3 attempts (task_state=${_tsb:-None}): ${_merr//$'\n'/ }"
                /usr/sbin/hex_log_event -e CLU00006W "interface=system,host=$from_host,category=cluster,sub=rolling_restart,action=migrate_rejected,vm=$sid,phase=request,task_state=${_tsb:-None},inflight=${#started[@]},reason=${_merr//[,$'\n']/ }"
            fi
        done
        sleep 5
        for sid in "${!started[@]}" ; do
            host=$($MYSQL -u root -N -D nova -e "SELECT host FROM instances WHERE uuid='$sid'" 2>/dev/null)
            st=$($MYSQL -u root -N -D nova -e "SELECT status FROM migrations WHERE instance_uuid='$sid' ORDER BY id DESC LIMIT 1" 2>/dev/null)
            if [ -n "$host" ] && [ "$host" != "$from_host" ] ; then
                echo "$(date +%s) done $sid -> $host ($(( $(date +%s) - ${started[$sid]} ))s)" >> "$tlog"
                log_info "rolling_restart drain: $sid migrated $from_host -> $host in $(( $(date +%s) - ${started[$sid]} ))s"
                _migrated=$((_migrated+1)) ; unset 'started[$sid]'
            elif [ "x$st" = "xerror" -o "x$st" = "xfailed" -o "x$st" = "xcancelled" ] ; then
                echo "$(date +%s) error $sid ($st)" >> "$tlog"
                log_error "rolling_restart drain: nova reported migration of $sid off $from_host as '$st' (convergence)"
                /usr/sbin/hex_log_event -e CLU00006W "interface=system,host=$from_host,category=cluster,sub=rolling_restart,action=migrate_rejected,vm=$sid,phase=convergence,nova_status=$st"
                stuck+=("$sid") ; unset 'started[$sid]'
            fi
            # otherwise still in flight -> nova converges/force-completes it; keep waiting.
        done
    done

    # A migratable VM that nova reports errored is an unacknowledged interruption.
    # Do NOT reboot under it: report so the caller pauses the roll for an operator.
    if [ ${#stuck[@]} -gt 0 ] ; then
        printf '%s\n' "${stuck[@]}" > "${ROLLING_DIR:-/tmp}/.stuck.${from_host}"
        echo "could not live-migrate off $from_host (stuck/error, needs operator): ${stuck[*]}" >&2
        log_error "rolling_restart drain: $from_host NOT drained after $(( $(date +%s) - _t0 ))s -- migrated=$_migrated stuck=${#stuck[@]} (${stuck[*]})"
        /usr/sbin/hex_log_event -e CLU00008I "interface=system,host=$from_host,category=cluster,sub=rolling_restart,action=drain_done,result=incomplete,migrated=$_migrated,stuck=${#stuck[@]},elapsed=$(( $(date +%s) - _t0 ))"
        return 1
    fi
    rm -f "${ROLLING_DIR:-/tmp}/.stuck.${from_host}"
    log_info "rolling_restart drain: $from_host drained in $(( $(date +%s) - _t0 ))s (migrated=$_migrated, suspended=$_nmig)"
    /usr/sbin/hex_log_event -e CLU00008I "interface=system,host=$from_host,category=cluster,sub=rolling_restart,action=drain_done,result=ok,migrated=$_migrated,suspended=$_nmig,elapsed=$(( $(date +%s) - _t0 ))"
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
        $OPENSTACK server list --host "$host" --all-projects --status ACTIVE -f value -c ID > $CLUSTER_ACTIVE_RUNNING
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
    local sentinel=$ROLLING_DIR/.draining.$host
    : > $sentinel
    _power_roll_drain_poll "$host" "$total" "$sentinel" "$allstart" &
    local poll_pid=$!

    power_drain_host $host
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
