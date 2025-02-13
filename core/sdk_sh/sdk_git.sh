# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ]; then
    echo "Error: PROG not set" >&2
    exit 1
fi

git_ignore_file()
{
    cat >/.gitignore <<EOF
*.pyc
*.po
*.mo
*.dat
*.txt
/.kube
/boot
/dev
/etc
/mnt
/opt
/proc
/root
/run
/tmp
/usr/lib/locale
/usr/include
/usr/local/bin/openstack
/usr/share
/usr/tmp
/sys
/store
/var
EOF
}

_git_server_init()
{
    $GIT stash 2>/dev/null || true
    if $GIT pull 2>/dev/null ; then
        return 0
    fi

    local IPADDR=$(cubectl node list -j | jq -r ".[] | select(.hostname == \"$HOSTNAME\") | .ip.management")
    local CUBE_GIT_DIR=$CEPHFS_BACKUP_DIR/cube.git
    local PROJECT=cube
    local BRANCH=master
    local GITSERVERIP=$(hex_sdk health_vip_report | cut -d"/" -f1)
    if [ "$GITSERVERIP" = "non-HA" ]; then
        GITSERVERIP=$IPADDR
    fi

    ceph_wait_for_status        # need cephfs be ready before git init and push
    cubectl node exec -pn "/usr/sbin/hex_sdk ceph_mount_cephfs"
    if mountpoint -q -- $CEPHFS_STORE_DIR ; then
        if [ ! -e $CUBE_GIT_DIR ]; then
            mkdir -p $CUBE_GIT_DIR
            GIT_DIR=$CUBE_GIT_DIR $GIT init --bare -b $BRANCH
            $GIT config --global user.email "${HOSTNAME}@${IPADDR}"
            git_ignore_file

            Quiet pushd /
            git init -b $BRANCH
            git remote add $PROJECT ssh://root@${GITSERVERIP}${CUBE_GIT_DIR}
            if [ -e "/.gitignore" ] ; then
                git add -A
                git commit -m "$(hex_cli -c firmware list | grep ACTIVE | awk '{print $2}')" -a
                git push --set-upstream $PROJECT $BRANCH
            else
                Error "failed to generate /.gitignore"
            fi
            Quiet popd
            $GIT -P log || Error "failed to initialize GIT server"
        fi
    else
        Error "no ceph mount point in $CEPHFS_STORE_DIR to initialize GIT server"
    fi
}

git_server_init()
{
    source /usr/sbin/hex_tuning /etc/settings.txt
    if [ "x$T_cubesys_control_hosts" = "x" ]; then
        export MASTER_CONTROL=$T_cubesys_controller
        [ -n "$MASTER_CONTROL" ] || MASTER_CONTROL=$T_net_hostname
    else
        export MASTER_CONTROL=$(echo $T_cubesys_control_hosts | cut -d"," -f1)
    fi
    remote_run $MASTER_CONTROL "hex_sdk _git_server_init"
}

git_client_init()
{
    $GIT stash || true
    if timeout 300 git pull 2>/dev/null ; then
        return 0
    fi

    local IPADDR=$(cubectl node list -j | jq -r ".[] | select(.hostname == \"$HOSTNAME\") | .ip.management")
    local CUBE_GIT_DIR=$CEPHFS_BACKUP_DIR/cube.git
    local PROJECT=cube
    local BRANCH=master
    local GITSERVERIP=$(cubectl node exec -r control -pn "hex_sdk health_vip_report" | sort -u | cut -d"/" -f1)
    if [ "$GITSERVERIP" = "non-HA" ]; then
        GITSERVERIP=$IPADDR
    fi

    $GIT config --global user.email "${HOSTNAME}@${IPADDR}"
    git_ignore_file

    Quiet pushd /
    $GIT init -b $BRANCH 2>/dev/null
    $GIT remote add $PROJECT ssh://root@${GITSERVERIP}${CUBE_GIT_DIR} 2>/dev/null
    if [ -e "/.gitignore" ] ; then
        if $GIT fetch ; then
            $GIT branch --track $BRANCH $PROJECT/$BRANCH 2>/dev/null
            $GIT add -A
            $GIT stash
            $GIT pull $PROJECT $BRANCH --rebase
        else
            Error "git server (on VIP node) is not ready"
        fi
    else
        Error "failed to generate /.gitignore"
    fi
    Quiet popd
    $GIT -P log
}

git_push()
{
    local MSG="${@:-n/a}"
    ( $GIT commit -m "$MSG" -a && $GIT push -q && cubectl node exec "$GIT stash ; $GIT pull" ) >/dev/null || Error "nothing is pushed"
    $GIT -P log -3
}
