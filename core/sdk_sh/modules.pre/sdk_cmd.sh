# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

cmd()
{
    local nodes=()
    local reverse="false"
    local dryrun="false"
    OPTIND=1
    while getopts "dvriacpsn:" opt; do
        case $opt in
            d) dryrun="true" ;;
            v) verbose="true" ;;
            r) reverse="true" ;;
            q) qend=">/dev/null 2>&1" ;;
            a)                  # all nodes
                nodes=( "${CUBE_NODE_LIST_HOSTNAMES[@]}" ) ;;
            c)                  # control nodes
                for c in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
                    exist=false
                    for n in "${nodes[@]}" ; do
                        if [ "x$n" = "x$c" ] ; then
                            echo "[ x$n = x$c ]"
                            exist=true
                        fi
                    done
                    [ "x$exist" = "xtrue" ] || nodes+=("$c")
                done
                ;;
            p)                  # compute nodes
                for c in "${CUBE_NODE_COMPUTE_HOSTNAMES[@]}" ; do
                    exist=false
                    for n in "${nodes[@]}" ; do
                        if [ "x$n" = "x$c" ] ; then
                            exist=true
                        fi
                    done
                    [ "x$exist" = "xtrue" ] || nodes+=("$c")
                done
                ;;
            s)                  # storage nodes
                for c in "${CUBE_NODE_STORAGE_HOSTNAMES[@]}" ; do
                    exist=false
                    for n in "${nodes[@]}" ; do
                        if [ "x$n" = "x$c" ] ; then
                            exist=true
                        fi
                    done
                    [ "x$exist" = "xtrue" ] || nodes+=("$c")
                done
                ;;
            n)                  # individual node(s)
                for c in $OPTARG ; do
                    exist=false
                    for n in "${nodes[@]}" ; do
                        if [ "x$n" = "x$c" ] ; then
                            exist=true
                        fi
                    done
                    [ "x$exist" = "xtrue" ] || nodes+=("$c")
                done
                ;;
            \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))
    [ ${#nodes[@]} -ne 0 ] || nodes=( "${CUBE_NODE_LIST_HOSTNAMES[@]}" )

    [ "x$reverse" = "xfalse" ] || nodes=( $(printf '%s\n' "${nodes[@]}" | tac | tr '\n' ' ') )
    declare -A nodes_pids=()
    declare -A nodes_rets=()
    declare -A nodes_logs=()
    for node in "${nodes[@]}" ; do
        nodes_logs[$node]="$(mktemp -u /tmp/cmd_${node}.XXXX)"
        if [ "x$dryrun" = "xfalse" ] ; then
            ssh -o LogLevel=quiet $node "$(typeset -f $1 || echo true ); VERBOSE=$VERBOSE; $@" >${nodes_logs[$node]} 2>&1 &
        else
            echo "ssh -o LogLevel=quiet $node $@"
        fi
        nodes_pids[$node]=$!
    done
    for node in "${nodes[@]}" ; do
        wait ${nodes_pids[$node]}
        nodes_rets[$node]=$?
        [ "x$verbose" != "xtrue" ] || printf "%s | %s | %s\n" "$node" "${nodes_rets[$node]}" "$(cat ${nodes_logs[$node]} 2>/dev/null)"
        rm -f ${nodes_logs[$node]}
    done
    local r=0
    for node in "${nodes[@]}" ; do
        [ "x${nodes_rets[$node]}" = "x0" ] || r=${nodes_rets[$node]}
    done

    return $r
}
