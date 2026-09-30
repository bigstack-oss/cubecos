# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

FIXPACK_STORE_DIR=${FIXPACK_STORE_DIR:-/var/fixpack}
FIXPACK_ROLLBACK_DIR=${FIXPACK_ROLLBACK_DIR:-/var/fixpack_rollback}

# Usage: $PROG fixpack_installed
# IDs installed on this node, from its own history (latest action wins).
fixpack_installed()
{
    /usr/sbin/hex_config fixpack_get_history 2>/dev/null | awk -F'|' '
        NF >= 7 { if (!($2 in act)) ids[++n] = $2 ; act[$2] = $5 }
        END { for (i = 1 ; i <= n ; i++) if (act[ids[i]] ~ /^Install/) print ids[i] }'
}

# Usage: $PROG fixpack_id <fixpack file>
fixpack_id()
{
    local file=$1
    local mnt id
    [ -f "$file" ] || Error "$file: file not found"
    mnt=$(mktemp -d /tmp/fixpack_id.XXXX)
    if mount -o ro,loop,noload "$file" $mnt >/dev/null 2>&1 ; then
        id=$(. $mnt/fixpack.info 2>/dev/null ; echo $FIXPACK_ID)
        umount $mnt
    fi
    rmdir $mnt
    [ -n "$id" ] || Error "$file: no FIXPACK_ID"
    echo $id
}

# Run a hex_sdk function on <node>; fails if the node can't be reached
_fixpack_on_node()
{
    local node=$1
    shift
    if [ "x$node" = "x$HOSTNAME" ] ; then
        $HEX_SDK "$@"
    else
        remote_run $node "$HEX_SDK $*"
    fi
}

# Usage: $PROG fixpack_missing_nodes <fixpack file>
# Nodes whose own history doesn't have the fixpack installed.
fixpack_missing_nodes()
{
    local id=$($HEX_SDK fixpack_id "$1")
    local node
    [ -n "$id" ] || return 1
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        _fixpack_on_node $node fixpack_installed | grep -qxF "$id" || echo $node
    done
}

# Usage: $PROG fixpack_status [fixpack id]
# Per node: <node>|<installed ids>|<ok|missing ...|unreachable>. Without an id,
# a node is checked against every id installed on any node.
fixpack_status()
{
    local want=${1:-}
    local node ids missing i r=0
    declare -A installed=()
    local all=
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        if ids=$(_fixpack_on_node $node fixpack_installed) ; then
            installed[$node]=$(echo $ids)
            all="$all $ids"
        else
            installed[$node]="?"
        fi
    done
    [ -n "$want" ] || want=$(printf '%s\n' $all | sort -u)
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        if [ "x${installed[$node]}" = "x?" ] ; then
            echo "$node|-|unreachable"
            r=1
            continue
        fi
        missing=
        for i in $want ; do
            echo " ${installed[$node]} " | grep -qF " $i " || missing="$missing $i"
        done
        if [ -n "$missing" ] ; then
            echo "$node|${installed[$node]:--}|missing$missing"
            r=1
        else
            echo "$node|${installed[$node]:--}|ok"
        fi
    done
    return $r
}

# Usage: $PROG fixpack_node_install <node> <fixpack file>
# Copy the fixpack to <node> and install it there; returns hex_config's exit code.
fixpack_node_install()
{
    local node=$1
    local file=$2
    local dst=$FIXPACK_STORE_DIR/$(basename "$file")
    remote_run $node "mkdir -p $FIXPACK_STORE_DIR" || Error "$node: failed to prepare $FIXPACK_STORE_DIR"
    rsync -a "$file" root@$node:$dst || Error "$node: failed to copy $file"
    remote_run $node "/usr/sbin/hex_config fixpack $dst"
}

# Usage: $PROG fixpack_rollback_top
# ID of this node's latest rollback point, the one `rollback` removes.
fixpack_rollback_top()
{
    local info=$FIXPACK_ROLLBACK_DIR/fixpack-0/fixpack.info
    [ -f $info ] || return 0
    ( . $info ; echo $FIXPACK_ID )
}

# Usage: $PROG fixpack_rollback_id
# This node's latest rollback point, else the first found on any node.
fixpack_rollback_id()
{
    local node id=$(fixpack_rollback_top)
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        [ -z "$id" ] || break
        id=$(_fixpack_on_node $node fixpack_rollback_top)
    done
    [ -z "$id" ] || echo $id
}

# Usage: $PROG fixpack_rollback_nodes <fixpack id>
# Nodes whose latest rollback point is <fixpack id>.
fixpack_rollback_nodes()
{
    local id=$1
    local node
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        [ "x$(_fixpack_on_node $node fixpack_rollback_top)" != "x$id" ] || echo $node
    done
}

# Usage: $PROG fixpack_node_rollback <node> <fixpack id>
# Roll back <node> only if its latest rollback point is <fixpack id>; returns
# hex_config's exit code.
fixpack_node_rollback()
{
    local node=$1
    local id=$2
    local top
    top=$(_fixpack_on_node $node fixpack_rollback_top) || Error "$node not reachable"
    [ "x$top" = "x$id" ] || Error "$node: latest fixpack is ${top:-none}, not $id"
    if [ "x$node" = "x$HOSTNAME" ] ; then
        /usr/sbin/hex_config fixpack_rollback
    else
        remote_run $node "/usr/sbin/hex_config fixpack_rollback"
    fi
}
