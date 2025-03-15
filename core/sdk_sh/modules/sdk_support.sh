# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

support_backup_folder_init()
{
    local bak_dir=${1:-$CEPHFS_BACKUP_DIR}

    if [ ! -d $bak_dir ] ; then
        mkdir -p $bak_dir
    fi
}

support_influxdb()
{
    local dstdir=${1:-$CEPHFS_BACKUP_DIR}
    local strtime=$(date --date="7 days ago" -u +"%Y-%m-%dT%H:%M:%SZ")

    /usr/bin/influxd backup -portable -start $strtime $dstdir/influxdb-$(hostname)-$(date +%Y%m%d-%H%M%S).7d
}

support_log_archive()
{
    local dstdir=${1:-$CEPHFS_BACKUP_DIR}
    find /var/log ! -path "*/qemu/*" ! -path "*/mysql/*" ! -path "*gc.log.*" ! -name "*.gz" ! -type s -depth -print 2>/dev/null | zip $dstdir/logs.zip -@
}

support_mysql_backup_list()
{
    if ! is_control_node ; then
        return 0
    fi

    cd $CEPHFS_BACKUP_DIR && ls -1t mysql-*.sql.gz
}

support_mysql_backup_create()
{
    if ! is_control_node ; then
        return 0
    fi

    local dstdir=${1:-$CEPHFS_BACKUP_DIR}

    support_backup_folder_init $dstdir

    /usr/bin/mysqldump -u root --all-databases | gzip > $dstdir/mysql-$(hostname)-$(date +%Y%m%d-%H%M%S).sql.gz
}

support_mysql_backup_apply()
{
    if ! is_control_node ; then
        return 0
    fi

    local bak_file=${1}

    if [ ! -f "$CEPHFS_BACKUP_DIR/$bak_file" ] ; then
        return 0
    fi

    zcat $CEPHFS_BACKUP_DIR/$bak_file | /usr/bin/mysql -u root
}

support_mysql_backup_rotate()
{
    if ! is_control_node ; then
        return 0
    fi

    local rotate=${1:-14}

    rm $(ls -t $CEPHFS_BACKUP_DIR/mysql-$(hostname)-* | awk -v rotate=$rotate 'NR>rotate') 2>/dev/null
}

support_mysql_backup_job()
{
    local rotate=${1:-14}

    support_mysql_backup_create
    support_mysql_backup_rotate $rotate
}

support_node_abort_autobootstrap()
{
    local pid=$(ps awwx | grep "[/]usr/sbin/bootstrap" | awk '{print $1}')
    if ps ${pid:-NOSUCHPID} >/dev/null 2>&1 ; then
        kill -9 $pid
        printf "\nAuto bootstrap is aborted by support" | tee -a $(GetKernelConsoleDevices) >/dev/null 2>&1 || true
    fi
}

support_cluster_abort_autobootstrap()
{
    cubectl node exec -pn "$HEX_SDK support_node_abort_autobootstrap"
}
