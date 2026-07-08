# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

cmd()
{
    local _cmd_nodes=()
    local verbose="false"
    local reverse="false"
    local onebyone="false"
    local dryrun="false"
    local r=0
    OPTIND=1
    while getopts "dvjroiacpsn:" opt; do
        case $opt in
            d) dryrun="true" ;;
            v) verbose="true" ;;
            j) json="true" ;;
            r) reverse="true" ;;
            o) onebyone="true" ;;
            q) qend=">/dev/null 2>&1" ;;
            a)                  # all nodes
                _cmd_nodes=( "${CUBE_NODE_LIST_HOSTNAMES[@]}" ) ;;
            c)                  # control nodes
                for c in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
                    exist=false
                    for n in "${_cmd_nodes[@]}" ; do
                        if [ "x$n" = "x$c" ] ; then
                            echo "[ x$n = x$c ]"
                            exist=true
                        fi
                    done
                    [ "x$exist" = "xtrue" ] || _cmd_nodes+=("$c")
                done
                ;;
            p)                  # compute nodes
                for c in "${CUBE_NODE_COMPUTE_HOSTNAMES[@]}" ; do
                    exist=false
                    for n in "${_cmd_nodes[@]}" ; do
                        if [ "x$n" = "x$c" ] ; then
                            exist=true
                        fi
                    done
                    [ "x$exist" = "xtrue" ] || _cmd_nodes+=("$c")
                done
                ;;
            s)                  # storage nodes
                for c in "${CUBE_NODE_STORAGE_HOSTNAMES[@]}" ; do
                    exist=false
                    for n in "${_cmd_nodes[@]}" ; do
                        if [ "x$n" = "x$c" ] ; then
                            exist=true
                        fi
                    done
                    [ "x$exist" = "xtrue" ] || _cmd_nodes+=("$c")
                done
                ;;
            n)                  # individual node(s)
                for c in $OPTARG ; do
                    exist=false
                    for n in "${_cmd_nodes[@]}" ; do
                        if [ "x$n" = "x$c" ] ; then
                            exist=true
                        fi
                    done
                    [ "x$exist" = "xtrue" ] || _cmd_nodes+=("$c")
                done
                ;;
            \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))
    [ ${#_cmd_nodes[@]} -ne 0 ] || _cmd_nodes=( "${CUBE_NODE_LIST_HOSTNAMES[@]}" )

    [ "x$reverse" = "xfalse" ] || _cmd_nodes=( $(printf '%s\n' "${_cmd_nodes[@]}" | tac | tr '\n' ' ') )
    # bound connect + liveness so a wedged remote can't block cmd() (timeout wrapper caps total).
    local _ssh_opts="-o LogLevel=quiet -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4"
    local _ssh_to="${CMD_SSH_TIMEOUT:-600}"
    declare -A _cmd_nodes_pids=()
    declare -A _cmd_nodes_rets=()
    declare -A _cmd_nodes_logs=()
    if [ "x$verbose" = "xtrue" -a "x$json" = "xtrue" ] ; then
        printf "[ "
    fi
    if [ "x$onebyone" = "xfalse" ] ; then
        for _cmd_node in "${_cmd_nodes[@]}" ; do
            # Minor fix: changed ${node} to ${_cmd_node} to correctly map the loop variable
            _cmd_nodes_logs[$_cmd_node]="$(mktemp -u /tmp/cmd_${_cmd_node}.XXXX)"

            if [ "x$dryrun" = "xfalse" ] ; then
                # Wrapping is_sshable into the backgrounded execution block
                {
                    if is_sshable $_cmd_node ; then
                        timeout $_ssh_to ssh $_ssh_opts $_cmd_node "$(typeset -f ${1%% *} || echo true ); VERBOSE=$VERBOSE; $@"
                    else
                        false
                    fi
                } >"${_cmd_nodes_logs[$_cmd_node]}" 2>&1 &
            else
                echo "ssh -o LogLevel=quiet $_cmd_node $@" &
            fi
            _cmd_nodes_pids[$_cmd_node]=$!
        done
        for  _cmd_node in "${_cmd_nodes[@]}" ; do
            wait ${_cmd_nodes_pids[$_cmd_node]}
            _cmd_nodes_rets[$_cmd_node]=$?
            if [ "x$verbose" = "xtrue" ] ; then
                if [ "x$json" = "xtrue" ] ; then
                    if [ ${#_cmd_nodes_rets[@]} -gt 1 ] ; then
                        printf ","
                    fi
                    echo -n "{ \"node\" : \"$_cmd_node\",\"return\" : \"${_cmd_nodes_rets[$_cmd_node]}\", \"stdout\" : \"$(cat ${_cmd_nodes_logs[$_cmd_node]} 2>/dev/null)\" }"
                else
                    printf "%s|%s|%s\n" "$_cmd_node" "${_cmd_nodes_rets[$_cmd_node]}" "$(cat ${_cmd_nodes_logs[$_cmd_node]} 2>/dev/null)"
                fi
            fi
            rm -f ${_cmd_nodes_logs[$_cmd_node]}
        done
        for _cmd_node in "${_cmd_nodes[@]}" ; do
            [ "x${_cmd_nodes_rets[$_cmd_node]}" = "x0" ] || r=${_cmd_nodes_rets[$_cmd_node]}
        done
    else
        local cnt=0
        for _cmd_node in "${_cmd_nodes[@]}" ; do
            ((cnt++))
            # Minor fix here as well for onebyone mode
            local _cmd_node_log="$(mktemp -u /tmp/cmd_${_cmd_node}.XXXX)"
            if [ "x$dryrun" = "xfalse" ] ; then
                if is_sshable $_cmd_node ; then
                    timeout $_ssh_to ssh $_ssh_opts $_cmd_node "$(typeset -f ${1%% *} || echo true ); VERBOSE=$VERBOSE; $@" >$_cmd_node_log 2>&1
                    _cmd_node_ret=$?
                else
                    _cmd_node_ret=1
                fi
                if [ "x$verbose" = "xtrue" ] ; then
                    if [ "x$json" = "xtrue" ] ; then
                        echo -n "{ \"node\" : \"$_cmd_node\",\"return\" : \"$_cmd_node_ret\", \"stdout\" : \"$(cat $_cmd_node_log 2>/dev/null)\" }"
                        if [ ${#_cmd_nodes[@]} -gt $cnt ] ; then
                            printf ","
                        fi
                    else
                        printf "%s|%s|%s\n" "$_cmd_node" "$_cmd_node_ret" "$(cat $_cmd_node_log 2>/dev/null)"
                    fi
                fi
            else
                echo "ssh -o LogLevel=quiet $_cmd_node $@"
            fi
            [ "x$_cmd_node_ret" = "x0" ] || r=$_cmd_node_ret
        done
    fi
    if [ "x$verbose" = "xtrue" -a "x$json" = "xtrue" ] ; then
        printf "]"
    fi
    return $r
}
