# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ]; then
    echo "Error: PROG not set" >&2
    exit 1
fi

support_backup_folder_init()
{
    local BAK_DIR=${1:-$CEPHFS_BACKUP_DIR}

    if [ ! -d $BAK_DIR ]; then
        mkdir -p $BAK_DIR
    fi
}

support_influxdb()
{
    local DSTDIR=${1:-$CEPHFS_BACKUP_DIR}
    local STRTIME=$(date --date="7 days ago" -u +"%Y-%m-%dT%H:%M:%SZ")

    /usr/bin/influxd backup -portable -start $STRTIME $DSTDIR/influxdb-$(hostname)-$(date +%Y%m%d-%H%M%S).7d
}

support_log_archive()
{
    local DSTDIR=${1:-$CEPHFS_BACKUP_DIR}
    find /var/log ! -path "*/qemu/*" ! -path "*/mysql/*" ! -path "*gc.log.*" ! -name "*.gz" ! -type s -depth -print 2>/dev/null | zip $DSTDIR/logs.zip -@
}

support_mysql_backup_list()
{
    if ! is_control_node; then
        return 0
    fi

    cd $CEPHFS_BACKUP_DIR && ls -1t mysql-*.sql.gz
}

support_mysql_backup_create()
{
    if ! is_control_node; then
        return 0
    fi

    local DSTDIR=${1:-$CEPHFS_BACKUP_DIR}

    support_backup_folder_init $DSTDIR

    /usr/bin/mysqldump -u root --all-databases | gzip > $DSTDIR/mysql-$(hostname)-$(date +%Y%m%d-%H%M%S).sql.gz
}

support_mysql_backup_apply()
{
    if ! is_control_node; then
        return 0
    fi

    local BAK_FILE=${1}

    if [ ! -f "$CEPHFS_BACKUP_DIR/$BAK_FILE" ]; then
        return 0
    fi

    zcat $CEPHFS_BACKUP_DIR/$BAK_FILE | /usr/bin/mysql -u root
}

support_mysql_backup_rotate()
{
    if ! is_control_node; then
        return 0
    fi

    local ROTATE=${1:-14}

    rm $(ls -t $CEPHFS_BACKUP_DIR/mysql-$(hostname)-* | awk -v rotate=$ROTATE 'NR>rotate') 2>/dev/null
}

support_mysql_backup_job()
{
    local ROTATE=${1:-14}

    support_mysql_backup_create
    support_mysql_backup_rotate $ROTATE
}

support_node_abort_autobootstrap()
{
    local PID=$(ps awwx | grep "[/]usr/sbin/bootstrap" | awk '{print $1}')
    if ps ${PID:-NOSUCHPID} >/dev/null 2>&1 ; then
        kill -9 $PID
        printf "\nAuto bootstrap is aborted by support" | tee -a $(GetKernelConsoleDevices) >/dev/null 2>&1 || true
    fi
}

support_cluster_abort_autobootstrap()
{
    cubectl node exec -pn "hex_sdk support_node_abort_autobootstrap"
}
