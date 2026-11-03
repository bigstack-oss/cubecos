# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

# Paths named, not inlined: the tests point them somewhere writable.
CUBE_GITIGNORE=${CUBE_GITIGNORE:-/.gitignore}
CUBE_GIT_WORKTREE=${CUBE_GIT_WORKTREE:-/}
CUBE_GIT_ROOT_CONFIG=${CUBE_GIT_ROOT_CONFIG:-/root/.gitconfig}

# The commit identity of this node, kept in the repository's own config (/.git/config). Run it
# with the worktree as the current directory. It must not live only in ~/.gitconfig: hex_cli is
# setuid root but keeps the caller's HOME, and the admin login's HOME is /tmp. A fixpack installed
# from an admin session then never sees /root/.gitconfig, its commit fails with "unable to
# auto-detect email address (got 'root@<host>.(none)')", and the change is left uncommitted.
_git_identity()
{
    local email
    email=$($GIT config --local user.email 2>/dev/null)
    if [ -z "$email" ] ; then
        email=$($GIT config --file $CUBE_GIT_ROOT_CONFIG user.email 2>/dev/null)
        if [ -z "$email" ] ; then
            local ipaddr=$(cubectl node list -j | jq -r ".[] | select(.hostname == \"$HOSTNAME\") | .ip.management")
            # never invent one: "@" or "host@" would pass git and hide the problem
            [ -n "$HOSTNAME" ] && [ -n "$ipaddr" ] && [ "$ipaddr" != null ] || return 1
            email="${HOSTNAME}@${ipaddr}"
        fi
        $GIT config --local user.email "$email" || return 1
    fi
    $GIT config --local user.name >/dev/null 2>&1 || $GIT config --local user.name root
}

git_ignore_file()
{
    cat >$CUBE_GITIGNORE <<EOF
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
        Quiet -n _git_identity
        # local cephfs path, not ssh://VIP (stalls during set_ready reconfig). #1195
        Quiet -n $GIT remote add $project ${cube_git_dir}
        if [ -e "$CUBE_GITIGNORE" ] ; then
            if ! git log -1 >/dev/null 2>&1 ; then
                Quiet -n git add -A
                Quiet -n git commit -m "$(hex_cli -c firmware list | grep ACTIVE | awk '{print $2}')" -a
            fi
            Quiet -n git push --set-upstream $project $branch
            git -P branch -r | grep -q "${project}/${branch}"
        else
            Error "failed to generate $CUBE_GITIGNORE"
        fi
        Quiet -n popd
        $GIT -P log || Error "failed to initialize GIT server"
    else
        Error "no ceph mount point in $CEPHFS_STORE_DIR to initialize GIT server"
    fi
}

git_server_init()
{
    export master_control=$(cube_master_control)
    remote_run $master_control "$HEX_SDK _git_server_init"
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
    Quiet -n _git_identity
    # local cephfs path, not ssh://VIP (stalls during set_ready reconfig). #1195
    Quiet -n $GIT remote add $project ${cube_git_dir}
    if [ -e "$CUBE_GITIGNORE" ] ; then
        if $GIT fetch ; then
            Quiet -n $GIT branch --track $branch $project/$branch
            # mixed reset: index follows HEAD, no file is written
            Quiet -n $GIT reset -q
        else
            Error "git server (on VIP node) is not ready"
        fi
    else
        Error "failed to generate $CUBE_GITIGNORE"
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
    local master=$(cube_master_control)
    if [ "x$T_net_hostname" = "x$master" ] ; then
        $HEX_SDK _git_server_init
    else
        $HEX_SDK _git_client_init
    fi
}

git_push()
{
    local msg="${@:-n/a}"
    local project=cube
    local d

    $HEX_SDK _git_client_init
    Quiet -n pushd $CUBE_GIT_WORKTREE
    # Commit tracked changes to this node's own branch; peers untouched. Every step is checked and
    # fails the call: a fixpack install records its change here, and a failure that went unseen
    # left the change uncommitted, to be swept into the next fixpack's commit.
    if [ -e .git/index.lock ] ; then
        Error "git: .git/index.lock exists on $HOSTNAME: another git is running, or one was killed; nothing recorded"
        return 1
    fi
    _git_identity || { Error "git: cannot set the commit identity on $HOSTNAME" ; return 1 ; }
    $GIT add -u || { Error "git: add failed on $HOSTNAME" ; return 1 ; }
    $GIT diff --cached --quiet
    d=$?
    if [ $d -eq 0 ] ; then
        log_info "git: nothing to record on $HOSTNAME"
    elif [ $d -ne 1 ] ; then
        Error "git: cannot tell what changed on $HOSTNAME (git diff exit $d)"
        return 1
    elif ! $GIT commit -q -m "$msg" ; then
        Error "git: commit failed on $HOSTNAME"
        return 1
    elif ! $GIT push -q $project +HEAD:refs/heads/nodes/$HOSTNAME ; then
        Error "git: $HOSTNAME's change is committed on the node but not pushed to $project nodes/$HOSTNAME"
        return 1
    fi
    Quiet -n popd
    Quiet -n $GIT -P log -3
}
