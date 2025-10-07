# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
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
    [ ! -e /etc/appliance/state/git_server_init ] || return 0

    local ipaddr=$(cubectl node list -j | jq -r ".[] | select(.hostname == \"$HOSTNAME\") | .ip.management")
    local cube_git_dir=$CEPHFS_BACKUP_DIR/cube.git
    local project=cube
    local branch=master
    local gitserverip=$($HEX_SDK -f json health_vip_report | jq -r .description | cut -d"/" -f1)
    if [ "$gitserverip" = "non-HA" ] ; then
        gitserverip=$ipaddr
    fi

    Quiet -n ceph_wait_for_status        # need cephfs be ready before git init and push
    cmd "$HEX_SDK -x ceph_mount_cephfs"
    if mountpoint -q -- $CEPHFS_STORE_DIR ; then
        if [ ! -e $cube_git_dir ] ; then
            mkdir -p $cube_git_dir
            GIT_DIR=$cube_git_dir $GIT init --bare -b $branch
            $GIT config --global user.email "${HOSTNAME}@${ipaddr}"
            git_ignore_file

            Quiet -n pushd /
            Quiet -n git init -b $branch
            Quiet -n git remote add $project ssh://root@${gitserverip}${cube_git_dir}
            if [ -e "/.gitignore" ] ; then
                Quiet -n git add -A
                Quiet -n git commit -m "$(hex_cli -c firmware list | grep ACTIVE | awk '{print $2}')" -a
                Quiet -n git push --set-upstream $project $branch && touch /etc/appliance/state/git_server_init
            else
                Error "failed to generate /.gitignore"
            fi
            Quiet -n popd
            $GIT -P log || Error "failed to initialize GIT server"
        fi
    else
        Error "no ceph mount point in $CEPHFS_STORE_DIR to initialize GIT server"
    fi
}

git_server_init()
{
    source $HEX_TUN $SETTINGS_TXT
    if [ "x$T_cubesys_control_hosts" = "x" ] ; then
        export master_control=$T_cubesys_controller
        [ -n "$master_control" ] || master_control=$T_net_hostname
    else
        export master_control=$(echo $T_cubesys_control_hosts | cut -d"," -f1)
    fi
    remote_run $master_control "$HEX_SDK _git_server_init"
}

git_client_init()
{
    [ ! -e /etc/appliance/state/git_client_init ] || return 0

    local ipaddr=$(cubectl node list -j | jq -r ".[] | select(.hostname == \"$HOSTNAME\") | .ip.management")
    local cube_git_dir=$CEPHFS_BACKUP_DIR/cube.git
    local project=cube
    local branch=master
    local gitserverip=$($HEX_SDK -f json health_vip_report | jq -r .description | sort -u | cut -d"/" -f1)
    if [ "$gitserverip" = "non-HA" ] ; then
        gitserverip=$ipaddr
    fi

    Quiet -n $GIT config --global user.email "${HOSTNAME}@${ipaddr}"
    Quiet -n git_ignore_file

    Quiet -n pushd /
    Quiet -n $GIT init -b $branch
    Quiet -n $GIT remote add $project ssh://root@${gitserverip}${cube_git_dir}
    if [ -e "/.gitignore" ] ; then
        if $GIT fetch ; then
            Quiet -n $GIT branch --track $branch $project/$branch
            Quiet -n $GIT add -A
            Quiet -n $GIT stash
            Quiet -n $GIT pull $project $branch --rebase
        else
            Error "git server (on VIP node) is not ready"
        fi
    else
        Error "failed to generate /.gitignore"
    fi
    Quiet -n popd
    Quiet -n $GIT -P log
    touch /etc/appliance/state/git_client_init
}

git_push()
{
    local msg="${@:-n/a}"
    cmd git_client_init
    ( $GIT commit -m "$msg" -a && $GIT push -q && cmd "$GIT stash ; $GIT pull" ) >/dev/null || Error "nothing is pushed"
    Quiet -n $GIT -P log -3
}

git_init()
{
    git_server_init
    if [ -e /etc/appliance/state/git_server_init ] ; then
        cmd "$HEX_SDK git_client_init"
    fi
}
