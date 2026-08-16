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
    $HEX_SDK cube_node_ready || return 0
    local ipaddr=$(cubectl node list -j | jq -r ".[] | select(.hostname == \"$HOSTNAME\") | .ip.management")
    local cube_git_dir=$CEPHFS_BACKUP_DIR/cube.git
    local project=cube
    local branch=master

    Quiet -n $HEX_SDK ceph_wait_for_status        # need cephfs be ready before git init and push
    cmd "$HEX_SDK -x ceph_mount_cephfs"
    if mountpoint -q -- $CEPHFS_STORE_DIR ; then
        mkdir -p $cube_git_dir
        GIT_DIR=$cube_git_dir $GIT init --bare -b $branch
        $GIT config --global user.email "${HOSTNAME}@${ipaddr}"
        # Disable git auto-maintenance -- it hangs on the /-worktree repo. #1195
        $GIT config --global maintenance.auto false
        git_ignore_file

        Quiet -n pushd /
        Quiet -n git init -b $branch
        # local cephfs path, not ssh://VIP (stalls during set_ready reconfig). #1195
        Quiet -n $GIT remote add $project ${cube_git_dir}
        if [ -e "/.gitignore" ] ; then
            if ! git log -1 >/dev/null 2>&1 ; then
                Quiet -n git add -A
                Quiet -n git commit -m "$(hex_cli -c firmware list | grep ACTIVE | awk '{print $2}')" -a
            fi
            Quiet -n git push --set-upstream $project $branch
            git -P branch -r | grep -q "${project}/${branch}"
        else
            Error "failed to generate /.gitignore"
        fi
        Quiet -n popd
        $GIT -P log || Error "failed to initialize GIT server"
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

GIT_SUID_MODES=/run/git_suid_modes

_git_suid_save()
{
    # git tracks only the exec bit; snapshot setuid/setgid modes before any checkout
    find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -printf '%m %p\n' 2>/dev/null > $GIT_SUID_MODES
}

_git_suid_restore()
{
    local m p
    while read m p ; do
        [ -f "$p" ] && cmd chmod $m "$p"
    done < $GIT_SUID_MODES
}

_git_client_init()
{
    $HEX_SDK cube_node_ready || return 0
    ! git log -1 >/dev/null 2>&1 || return 0
    local ipaddr=$(cubectl node list -j | jq -r ".[] | select(.hostname == \"$HOSTNAME\") | .ip.management")
    local cube_git_dir=$CEPHFS_BACKUP_DIR/cube.git
    local project=cube
    local branch=master

    Quiet -n $GIT config --global user.email "${HOSTNAME}@${ipaddr}"
    # Disable git auto-maintenance -- it hangs on the /-worktree repo. #1195
    Quiet -n $GIT config --global maintenance.auto false
    Quiet -n git_ignore_file

    Quiet -n pushd /
    Quiet -n $GIT init -b $branch
    # local cephfs path, not ssh://VIP (stalls during set_ready reconfig). #1195
    Quiet -n $GIT remote add $project ${cube_git_dir}
    if [ -e "/.gitignore" ] ; then
        if $GIT fetch ; then
            _git_suid_save
            Quiet -n $GIT branch --track $branch $project/$branch
            Quiet -n $GIT add -A
            Quiet -n $GIT stash
            Quiet -n $GIT pull $project $branch --rebase
            _git_suid_restore
        else
            Error "git server (on VIP node) is not ready"
        fi
    else
        Error "failed to generate /.gitignore"
    fi
    Quiet -n popd
    Quiet -n $GIT -P log
}

git_client_init()
{
    cmd $HEX_SDK _git_client_init
}

git_init()
{
    git_server_init
    git_client_init
}

git_node_init()
{
    # Init only THIS node: the master creates the bare repo (and its own /
    # clone); peers clone from cephfs, failing harmlessly until it exists.
    source $HEX_TUN $SETTINGS_TXT
    local master
    if [ "x$T_cubesys_control_hosts" = "x" ] ; then
        master=$T_cubesys_controller
        [ -n "$master" ] || master=$T_net_hostname
    else
        master=$(echo $T_cubesys_control_hosts | cut -d"," -f1)
    fi
    if [ "x$T_net_hostname" = "x$master" ] ; then
        $HEX_SDK _git_server_init
    else
        $HEX_SDK _git_client_init
    fi
}

git_push()
{
    local msg="${@:-n/a}"

    if git -P status | grep -q modified ; then
        cmd $HEX_SDK git_client_init
        _git_suid_save
        ( $GIT commit -m "$msg" -a && $GIT push -q && cmd "$GIT stash ; $GIT pull" ) >/dev/null
        _git_suid_restore
        Quiet -n $GIT -P log -3
    else
        Error "nothing is pushed"
    fi
}
