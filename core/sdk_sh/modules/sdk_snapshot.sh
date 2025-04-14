# HEX SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

snapshot_nfs_list()
{
    local nfs_path=$1

    [ -d $NFS_DIR ] || /bin/mkdir -p $NFS_DIR
    /bin/mount -t nfs -o nolock $nfs_path $NFS_DIR
    for snap in $(cd $NFS_DIR && ls *.snapshot | sort) ; do
        if [ "$VERBOSE" == "1" ] ; then
            local tmp_dir=$(mktemp -d -t snap-XXXXX)
            cd $tmp_dir && /usr/bin/unzip $NFS_DIR/$snap Comment >/dev/null 2>&1
            local comment=$(cat $tmp_dir/Comment | tr -d '\n')
            printf "%-48s %-60s\n" "($comment)" "$snap"
            rm -rf $tmp_dir
        else
            echo "$snap"
        fi
    done
    /bin/umount -l $NFS_DIR
}

snapshot_nfs_push()
{
    local snapshot_path=$1
    local nfs_path=$2

    [ -d $NFS_DIR ] || /bin/mkdir -p $NFS_DIR
    /bin/mount -t nfs -o nolock $nfs_path $NFS_DIR
    /usr/bin/rsync --progress $snapshot_path $NFS_DIR
    /bin/umount -l $NFS_DIR
}

snapshot_nfs_pull()
{
    local nfs_path=$1
    local snapshot=$2
    local local_dir=$3

    [ -d $NFS_DIR ] || /bin/mkdir -p $NFS_DIR
    /bin/mount -t nfs -o nolock $nfs_path $NFS_DIR
    /usr/bin/rsync --progress $NFS_DIR/$snapshot $local_dir
    /bin/umount -l $NFS_DIR
}

snapshot_load_network_config()
{
    local ignore=$(cd $POLICY_DIR && ls -l | grep -v "network\|total" | awk '{print $9}' | tr '\n' ',')

    cp -f $SETTINGS_TXT /tmp/settings.txt.before
    echo "snapshot.apply.action = load" >> $SETTINGS_TXT
    echo "snapshot.apply.policy.ignore = ${ignore::-1}" >> $SETTINGS_TXT

    if [ ! -f /etc/appliance/state/configured -o ! -f /etc/appliance/state/sla_accepted ] ; then
        touch /tmp/unconfigured
    fi
}

snapshot_load_network_undo()
{
    mv /tmp/settings.txt.before $SETTINGS_TXT

    if [ -f /tmp/unconfigured ] ; then
        rm -f /tmp/unconfigured /etc/appliance/state/configured /etc/appliance/state/sla_accepted
    fi
}
