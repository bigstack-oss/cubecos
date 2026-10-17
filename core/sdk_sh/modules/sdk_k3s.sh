# HEX SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

k3s_take_leader()
{
    source hex_tuning $SETTINGS_TXT cubesys.control.addrs
    if [ -z "$T_cubesys_control_addrs" ] ; then
        exit 0
    fi

    local eps=$(sed -e 's/,/:2379&/g' -e 's/$/:2379&/g' <<< $T_cubesys_control_addrs)

    export ETCDCTL_CACERT='/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt'
    export ETCDCTL_CERT='/var/lib/rancher/k3s/server/tls/etcd/server-client.crt' 
    export ETCDCTL_KEY='/var/lib/rancher/k3s/server/tls/etcd/server-client.key'

    local member_id=$(etcdctl endpoint status -w json | jq '.[].Status.header.member_id' | xargs printf '%x')
    Quiet -n etcdctl --endpoints=$eps move-leader $member_id
}

k3s_reconfigure_mtu()
{
    # Delete dev flannel.1 and restart k3s 
    # so that flannel.1 can be recreated to honor new MTU
    Quiet -n ip link delete flannel.1
    Quiet -n systemctl restart k3s

    # Restart all pods on current node so that new pods will honor new MTU
    Quiet -n k3s kubectl delete pods -A --field-selector spec.nodeName=$HOSTNAME --force
}

# k3s upgrades one minor version at a time. The image ships the release it runs at
# K3S_FINAL_BIN and the releases between it and v1.26.6+k3s1, what every release before
# it shipped, at K3S_LADDER_DIR/<version>/k3s (core/k3s/Makefile, k3s.mk).
K3S_BIN=/usr/local/bin/k3s
K3S_FINAL_BIN=/opt/k3s/k3s
K3S_LADDER_DIR=/opt/k3s/ladder
# Read by cubectl's k3s commit (config_k3s.go) on the next migration boot. Under
# /var/lib/rancher/k3s, which CONFIG_MIGRATE carries to the new partition.
K3S_VERSION_FILE=/var/lib/rancher/k3s/cube-k3s-version
K3S_STEP_TIMEOUT=${K3S_STEP_TIMEOUT:-900}
K3S_STEP_POLL=${K3S_STEP_POLL:-10}

# v1.30.14+k3s2 -> 30
_k3s_minor()
{
    sed -nE 's/^v?1\.([0-9]+)\..*/\1/p' <<< "$1"
}

_k3s_bin_version()
{
    "$1" --version 2>/dev/null | awk 'NR==1{print $3}'
}

# The shipped release with the lowest minor above <minor>
_k3s_next_release()
{
    local minor=$1 v m best="" bestm=""
    for v in $(ls $K3S_LADDER_DIR 2>/dev/null) $(_k3s_bin_version $K3S_FINAL_BIN) ; do
        m=$(_k3s_minor $v)
        [ -n "$m" ] && [ "$m" -gt "$minor" ] || continue
        if [ -z "$bestm" ] || [ "$m" -lt "$bestm" ] ; then
            best=$v
            bestm=$m
        fi
    done
    echo $best
}

# Node <name> is Ready on <version>, the API server answers and every etcd member is
# healthy. Polls for up to K3S_STEP_TIMEOUT seconds.
_k3s_wait_settled()
{
    local node=$1 want=$2 waited=0
    while [ $waited -lt $K3S_STEP_TIMEOUT ] ; do
        if [ "$(k3s kubectl get node $node -o jsonpath='{.status.nodeInfo.kubeletVersion} {.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "$want True" ] &&
           k3s kubectl get --raw=/readyz >/dev/null 2>&1 &&
           ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
           ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
           ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
               etcdctl endpoint health --cluster >/dev/null 2>&1 ; then
            return 0
        fi
        sleep $K3S_STEP_POLL
        waited=$((waited + K3S_STEP_POLL))
    done
    return 1
}

# Run this node's k3s at <version>, one of the releases the image ships, and record it once
# the node is Ready on it.
k3s_step()
{
    local want=$1 bin self=$(hostname | tr '[:upper:]' '[:lower:]')
    if [ -x $K3S_LADDER_DIR/$want/k3s ] ; then
        bin=$K3S_LADDER_DIR/$want/k3s
    elif [ "$(_k3s_bin_version $K3S_FINAL_BIN)" = "$want" ] ; then
        bin=$K3S_FINAL_BIN
    else
        log_error "k3s_step: this image ships no k3s $want"
        return 1
    fi

    if [ "$(_k3s_bin_version $K3S_BIN)" != "$want" ] ; then
        cp -f $bin $K3S_BIN.new && mv -f $K3S_BIN.new $K3S_BIN || return 1
        # k3s.service waits for k3s without a limit; _k3s_wait_settled holds the deadline
        timeout ${K3S_STEP_TIMEOUT}s systemctl restart k3s
        if ! _k3s_wait_settled $self $want ; then
            log_error "k3s_step: $self not Ready on $want within ${K3S_STEP_TIMEOUT}s"
            return 1
        fi
    fi
    echo $want > $K3S_VERSION_FILE
}

# Bring every k3s server up to the release this image runs: one minor at a time, and one
# server at a time, so no two servers are ever more than one minor apart. A no-op once they
# all run it. On HA it runs on the VIP holder, called when a roll completes
# (power_roll_advance); each server's migration boot has taken the first step already. On a
# single node cubectl's k3s commit calls it with "nocommit" at the migration boot, and goes
# on to what `cubectl config commit k3s` would otherwise run here.
#
# Stops at the first server that does not settle in time and returns non-zero. The servers
# are then at most one minor apart, and running it again carries on from there.
k3s_upgrade_ladder()
{
    is_control_node || return 0
    source hex_tuning $SETTINGS_TXT cubesys.ha
    if [ "$T_cubesys_ha" = "true" ] ; then
        source hex_tuning $SETTINGS_TXT cubesys.control.vip
        local vip=$T_cubesys_control_vip
        [ -n "$vip" ] || return 1
        if ! ip -o addr show | grep -qF " $vip/" ; then
            ( remote_run $vip "$HEX_SDK k3s_upgrade_ladder $*" )
            return $?
        fi
    fi

    local final=$(_k3s_bin_version $K3S_FINAL_BIN)
    [ -n "$final" ] || { log_error "k3s_upgrade_ladder: no k3s at $K3S_FINAL_BIN" ; return 1 ; }

    local self=$(hostname | tr '[:upper:]' '[:lower:]')
    local servers oldest target tm node ver stepped=0
    while : ; do
        servers=$(k3s kubectl get nodes -l node-role.kubernetes.io/control-plane -o json 2>/dev/null |
                  jq -r '.items[] | .metadata.name + " " + .status.nodeInfo.kubeletVersion')
        [ -n "$servers" ] || { log_error "k3s_upgrade_ladder: cannot list the k3s servers" ; return 1 ; }
        awk -v f="$final" '$2 != f {behind=1} END {exit !behind}' <<< "$servers" || break

        oldest=$(awk '{split($2, v, "."); m = v[2] + 0; if (min == "" || m < min) min = m} END {print min}' <<< "$servers")
        target=$(_k3s_next_release $oldest)
        tm=$(_k3s_minor $target)
        if [ "$tm" != "$((oldest + 1))" ] ; then
            log_error "k3s_upgrade_ladder: the image ships no v1.$((oldest + 1)) to step up from v1.$oldest"
            return 1
        fi

        for node in $(awk -v t=$tm '{split($2, v, "."); if (v[2] + 0 < t) print $1}' <<< "$servers") ; do
            ver=$(awk -v n=$node '$1 == n {print $2}' <<< "$servers")
            log_info "k3s_upgrade_ladder: $node $ver -> $target"
            if [ "$node" = "$self" ] ; then
                k3s_step $target
            else
                ( remote_run $node "$HEX_SDK k3s_step $target" ) </dev/null
            fi || { log_error "k3s_upgrade_ladder: k3s_step $target failed on $node" ; return 1 ; }
            if ! _k3s_wait_settled $node $target ; then
                log_error "k3s_upgrade_ladder: $node not settled on $target within ${K3S_STEP_TIMEOUT}s"
                return 1
            fi
            stepped=1
        done
    done

    [ $stepped -eq 1 ] || return 0
    log_info "k3s_upgrade_ladder: every k3s server runs $final"
    [ "${1:-}" = "nocommit" ] || cubectl config commit k3s
}
