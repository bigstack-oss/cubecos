CURRENT_VERSION=$(/bin/grep 'sys.product.version' /etc/settings.sys | /usr/bin/awk '{print $NF}')
FIRST_CTRLHOST=$(cubectl node list | head -n1 | awk -F"," '{print $1}')

# Removing cube.git is a must such that new firmware does not pull check-ins from old one
rm -rf /var/support/localrpms /var/support/map_* /mnt/cephfs/backup/cube.git /store/ppu
# Until it is rolled, a 3.1.x node runs its own git code: a fixpack install's git_push pushes its
# tree to cube.git master and runs `git stash ; git pull` on every node, and a peer with no /.git
# checks that tree out over its /. The opt-out stops both for the roll; 3.2 ignores the marker.
# /etc/version is the running slot; sys.product.version was seen naming 3.2.0 on a 3.1.20 node.
case "$(cat /etc/version 2>/dev/null)" in
    CUBE_3.1.*) touch /etc/appliance/state/cube_git_optout ;;
esac
mkdir -p /store/ppu/libvirt/secrets/
cubectl node list -j > /store/ppu/cluster-info.json
cp /etc/libvirt/secrets/* /store/ppu/libvirt/secrets/

# Cluster level tasks
# Run on first control node only
if [ "$FIRST_CTRLHOST" == "$(hostname)" ]; then
    # Backup mysql
    hex_sdk support_mysql_backup_create
    # Guard ceph for the whole rolling upgrade BEFORE any node reboots (covers the
    # first node too); the relay re-sets it per step and clears it on
    # completion/pause/abort.
    hex_sdk ceph_enter_rolling
    # every broker still runs this release; the next minor refuses to start while a flag it
    # requires is off (#2164), so enable them all before any node reboots. Never fails the
    # staging: a broker that refuses keeps its data and the bootstrap goes on without it.
    # logger, because the roll drops the staging output and install.log lands in the new slot
    rmq="timeout 120 env LANG=en_US.utf8 /usr/sbin/rabbitmqctl -q"
    $rmq enable_feature_flag all
    if ! ff=$($rmq list_feature_flags name state stability) ; then
        logger -t cube-update "rabbitmq: cannot read feature flags on $(hostname)"
    else
        off=$(echo "$ff" | awk '$2=="disabled" && $3!="experimental" {print $1}' | paste -sd' ')
        [ -z "$off" ] || logger -t cube-update "rabbitmq: feature flags still disabled: $off"
    fi
fi


echo "Firmware on $HOSTNAME has been updated with success!"
