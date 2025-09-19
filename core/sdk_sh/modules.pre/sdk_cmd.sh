# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

cmd()
{
    local _cmd_nodes=()
    local reverse="false"
    local dryrun="false"
    OPTIND=1
    while getopts "dvjriacpsn:" opt; do
        case $opt in
            d) dryrun="true" ;;
            v) verbose="true" ;;
            j) json="true" ;;
            r) reverse="true" ;;
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
    declare -A _cmd_nodes_pids=()
    declare -A _cmd_nodes_rets=()
    declare -A _cmd_nodes_logs=()
    for _cmd_node in "${_cmd_nodes[@]}" ; do
        _cmd_nodes_logs[$_cmd_node]="$(mktemp -u /tmp/cmd_${node}.XXXX)"
        if [ "x$dryrun" = "xfalse" ] ; then
            if is_sshable $_cmd_node ; then
                ssh -o LogLevel=quiet $_cmd_node "$(typeset -f ${1%% *} || echo true ); VERBOSE=$VERBOSE; $@" >${_cmd_nodes_logs[$_cmd_node]} 2>&1 &
            else
                false &
            fi
        else
            echo "ssh -o LogLevel=quiet $_cmd_node $@" &
        fi
        _cmd_nodes_pids[$_cmd_node]=$!
    done
    if [ "x$verbose" = "xtrue" -a "x$json" = "xtrue" ] ; then
        printf "[ "
    fi
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
    if [ "x$verbose" = "xtrue" -a "x$json" = "xtrue" ] ; then
        printf "]"
    fi
    local r=0
    for _cmd_node in "${_cmd_nodes[@]}" ; do
        [ "x${_cmd_nodes_rets[$_cmd_node]}" = "x0" ] || r=${_cmd_nodes_rets[$_cmd_node]}
    done

    return $r
}
