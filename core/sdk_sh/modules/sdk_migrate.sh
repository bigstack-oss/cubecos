# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

migrate_prepare()
{
    touch $STATE_DIR/cube_migration
}

migrate_fixpack()
{
    if [ -f $STATE_DIR/fixpack_migrated ] ; then
        return 0
    fi

    # FW upgrade should've included fixpack contents of previous releases
    rm -fr /var/support/fixpack /var/fixpack/* /var/appliance-db/fixpack.history
    touch $STATE_DIR/fixpack_migrated
}

migrate_git()
{
    # /.git is infra plumbing, not an operator-facing service: converge it in
    # the background until done and never surface it to health checks. #1195
    [ -f $STATE_DIR/git_migrated ] && return 0
    setsid $HEX_SDK _migrate_git_bg </dev/null >/dev/null 2>&1 &
}

# Unbounded self-convergence: this node inits only ITSELF (master hosts the
# bare repo, peers clone it) -- concurrent full git_init from every node
# stomped each other's / worktrees. flock keeps one loop per node.
_migrate_git_bg()
{
    exec 9>/run/migrate_git.lock
    flock -n 9 || return 0
    while [ ! -f $STATE_DIR/git_migrated ] ; do
        if $HEX_SDK cube_node_ready ; then
            $HEX_SDK git_node_init
            if git -C / log -1 >/dev/null 2>&1 ; then
                touch $STATE_DIR/git_migrated
                return 0
            fi
        fi
        sleep 20
    done
}

migrate_keystone_db()
{
    if [ -f $STATE_DIR/keystone_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "/usr/bin/keystone-manage db_sync" keystone

        /usr/bin/keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
        /usr/bin/keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
        local id_url=$($MYSQL -u root -D keystone -e "SELECT id,url from endpoint where interface='admin'" | awk '/35357/{print $1" "$2}')
        local id=$(echo $id_url | awk '{print $1}')
        local url=$(echo $id_url | awk '{print $2}'| sed 's/35357/5000/g')
        $MYSQL -u root -D keystone -e "UPDATE endpoint set url='$url' where id='$id'"
    fi

    /usr/bin/sed -i 's/35357/5000/g' /etc/admin-openrc.sh

    touch $STATE_DIR/keystone_db_migrated
}

migrate_keystone()
{
    if [ -f $STATE_DIR/keystone_migrated ] ; then
        return 0
    fi

    # to v1.3.2
    # multi-domain: role assignment check for default domain
    local assign=$($OPENSTACK role assignment list --domain default -f value -c User)
    if ! echo $assign | grep -q $($HEX_SDK os_get_user_id_by_name admin) ; then
        $OPENSTACK role add --user admin --domain default admin
    fi
    if ! echo $assign | grep -q $($HEX_SDK os_get_user_id_by_name admin_cli) ; then
        $OPENSTACK role add --user admin_cli --domain default admin
    fi

    # to v2.4
    if ! $OPENSTACK role show service ; then
        $OPENSTACK role create service
        $OPENSTACK role add --project service --user cinder service
        $OPENSTACK role add --project service --user nova service
    fi

    touch $STATE_DIR/keystone_migrated
}

# Caracal secure-RBAC: service-to-service APIs check role:service with no admin
# fallback, but only cinder/nova ever got it. Own marker: keystone_migrated
# short-circuits on clusters that already ran the v2.4 step.
migrate_keystone_service_role()
{
    if [ -f $STATE_DIR/keystone_service_role_migrated ] ; then
        return 0
    fi

    is_control_node || return 0

    $OPENSTACK role show service >/dev/null 2>&1 || $OPENSTACK role create service

    local u
    for u in barbican cinder cyborg designate glance heat ironic ironic-inspector \
             masakari monasca neutron nova octavia placement skyline watcher ; do
        $OPENSTACK user show $u >/dev/null 2>&1 || continue
        $OPENSTACK role add --project service --user $u service >/dev/null 2>&1
    done

    touch $STATE_DIR/keystone_service_role_migrated
}

migrate_barbican_db()
{
    if [ -f $STATE_DIR/barbican_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "barbican-manage db upgrade" barbican
    fi

    touch $STATE_DIR/barbican_db_migrated
}

migrate_cinder_db()
{
    if [ -f $STATE_DIR/cinder_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        # db_schema_stein.tgz (python3.6) no longer works with Yoga (python3.9)
        # local path=/usr/lib/python3.9/site-packages/cinder/db/sqlalchemy/migrate_repo
        # mv $path/versions $path/versions_latest
        # (cd $path && tar zxf /etc/cinder/db_schema_stein.tgz)

        # su -s /bin/sh -c "cinder-manage db sync" cinder
        # su -s /bin/sh -c "cinder-manage db online_data_migrations" cinder
        # su -s /bin/sh -c "cinder-manage db purge 90" cinder

        # rm -rf $path/versions
        # mv $path/versions_latest $path/versions

        ( su -s /bin/sh -c "cinder-manage db sync" cinder && \
              su -s /bin/sh -c "cinder-manage db online_data_migrations" cinder && \
              su -s /bin/sh -c "cinder-manage db purge 90" cinder && \
              touch $STATE_DIR/cinder_db_migrated ) || true
    fi
}

migrate_glance_db()
{
    if [ -f $STATE_DIR/glance_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "/usr/bin/glance-manage db_sync" glance
    fi

    touch $STATE_DIR/glance_db_migrated
}

migrate_heat_db()
{
    if [ -f $STATE_DIR/heat_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "/usr/bin/heat-manage db_sync" heat
    fi

    touch $STATE_DIR/heat_db_migrated
}

migrate_neutron_db()
{
    if [ -f $STATE_DIR/neutron_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade heads" neutron
        $MYSQL -u root -D neutron -e "SET FOREIGN_KEY_CHECKS = 0 ; TRUNCATE TABLE agents ; SET FOREIGN_KEY_CHECKS = 1"
        $MYSQL -u root -D neutron -e "UPDATE ml2_port_binding_levels SET driver='ovn' WHERE driver='linuxbridge'"
        $MYSQL -u root -D neutron -e "UPDATE ml2_port_bindings SET vif_type='ovs' WHERE vif_type='bridge'"
        $MYSQL -u root -D neutron -e "UPDATE networksegments SET network_type='geneve' WHERE network_type='vxlan'"
        $MYSQL -u root -D neutron -e "TRUNCATE TABLE networkdhcpagentbindings"
        $MYSQL -u root -D neutron -e "TRUNCATE TABLE routerl3agentbindings"

        # upgrade to 2.2.0
        su -s /bin/sh -c "neutron-db-manage --subproject neutron-vpnaas upgrade heads" neutron

        # Yoga <-> Antelope compatibility shim for the mixed-version window.
        #
        # zed/expand/I43e0b669096_port_forwarding_port_ranges.py replaces
        # portforwardings.external_port and .socket with start/end range columns.
        # Upstream put it in the *expand* branch, so there is no phased form of
        # this migration that leaves the old columns standing: the moment the
        # first node migrates the shared schema, every still-Yoga neutron-server
        # on the other control nodes answers 500 to any port query with
        #   (1054, "Unknown column 'portforwardings.external_port' in 'SELECT'")
        # That is not confined to port forwarding -- the port_forwarding service
        # plugin's callback fires on every port create and update, so it takes
        # out the whole port API on 2 of 3 servers behind the VIP, and with it
        # the live migration that rolling_upgrade drains each node with.
        #
        # Deferring the migration instead does not help; it only inverts which
        # servers are broken, and worse, the healthy pool then shrinks as the
        # roll proceeds instead of growing. Since only the column *shape*
        # changed, re-add the two dropped columns as generated columns so the
        # migrated schema answers both dialects. They are additive and derived,
        # and invisible to Antelope's ORM, which names its columns explicitly.
        # Yoga can read port forwardings through them but not create one --
        # generated columns reject writes -- which is the accepted trade for
        # keeping the port API and the drain alive during the window.
        #
        # migrate_neutron_db_post() drops them once no Yoga server is left.
        if [ "$($MYSQL -N -u root -D neutron -e "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = 'neutron' AND TABLE_NAME = 'portforwardings' AND COLUMN_NAME IN ('external_port', 'socket')")" = "0" ] ; then
            $MYSQL -u root -D neutron -e "ALTER TABLE portforwardings ADD COLUMN external_port int(11) GENERATED ALWAYS AS (external_port_start) VIRTUAL, ADD COLUMN socket varchar(36) GENERATED ALWAYS AS (concat(internal_ip_address, ':', internal_port_start)) VIRTUAL"
        fi
    fi

    touch $STATE_DIR/neutron_db_migrated
}

migrate_neutron_db_post()
{
    if [ -f $STATE_DIR/neutron_db_post_migrated ] ; then
        return 0
    fi

    if ! is_control_node ; then
        touch $STATE_DIR/neutron_db_post_migrated
        return 0
    fi

    # Drop the mixed-window compatibility shim migrate_neutron_db() added, but
    # only once every control node runs Antelope's neutron-server. An unreachable
    # node counts as unknown and holds the shim, so a half-finished roll never
    # loses the columns out from under a Yoga server; carrying two generated
    # columns for one more cluster_start costs nothing.
    $HEX_SDK os_neutron_version_uniform || return 0

    $MYSQL -u root -D neutron -e "ALTER TABLE portforwardings DROP COLUMN IF EXISTS external_port, DROP COLUMN IF EXISTS socket"

    touch $STATE_DIR/neutron_db_post_migrated
}

migrate_neutron_ovn_sync()
{
    if [ -f $STATE_DIR/neutron_ovn_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        neutron-ovn-db-sync-util --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini --ovn-neutron_sync_mode repair
    fi

    touch $STATE_DIR/neutron_ovn_migrated
}

migrate_nova_db()
{
    if [ -f $STATE_DIR/nova_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        chown nova:nova /var/log/nova/nova-manage.log
        su -s /bin/sh -c "nova-manage api_db sync" nova
        su -s /bin/sh -c "nova-manage db sync" nova
        su -s /bin/sh -c "placement-manage db sync" nova
        # NOTE: this used to force `update nova.services set version = 61` behind a
        # guard on the openstack client version. Removed rather than repaired, on
        # three counts. The guard never fired: $OPENSTACK carries its `timeout <n>`
        # prefix, so the pattern expanded to "xtimeout 60 /usr/bin/openstack 6."
        # against a subject of "xopenstack 6.2.1". 61 is a yoga-era constant --
        # antelope's nova reports SERVICE_VERSION 66 -- so reviving it would have
        # written a *lower* version than the code actually speaks. And it is
        # unnecessary: nova writes its own row on every service start, verified by
        # restarting nova-conductor and watching nova.services.updated_at advance
        # with version staying 66.
    fi

    touch $STATE_DIR/nova_db_migrated
}

migrate_nova_db_post()
{
    mountpoint -- $CEPHFS_STORE_DIR  | grep -q "is a mountpoint" || $HEX_SDK ceph_mount_cephfs
    if [ ! -e ${CEPHFS_NOVA_DIR}/instances ] ; then
        mkdir -p ${CEPHFS_NOVA_DIR}/instances
        chown -R nova:nova ${CEPHFS_NOVA_DIR}
        chmod -R 0755 ${CEPHFS_NOVA_DIR}
        find /mnt/target/var/lib/nova/instances/* -maxdepth 1 -type d | grep -v -e locks -e compute_nodes -e _base | xargs -i cp -rpf {} /var/lib/nova/instances/
    fi

    if [ -f $STATE_DIR/nova_db_post_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        # Chain the marker to the migration, the way migrate_cinder_db() does.
        # Invoked without --max-count, nova-manage db online_data_migrations loops
        # in batches until nothing is left to migrate, so it returns 0 on success
        # and 2 for "Some migrations failed unexpectedly. Check log for details."
        # Touching the marker unconditionally recorded that failure as a completed
        # migration, so the rows it could not convert were never revisited for the
        # life of the release. Leaving the marker unwritten means the next Commit()
        # retries it.
        ( su -s /bin/sh -c "nova-manage db online_data_migrations" nova && \
              touch $STATE_DIR/nova_db_post_migrated ) || true
        # Not chained: removing the nova-consoleauth service row is unrelated
        # bookkeeping, and its failure should not hold back the migration marker.
        $HEX_SDK os_nova_service_remove $HOSTNAME "nova-consoleauth"
    else
        touch $STATE_DIR/nova_db_post_migrated
    fi
}

migrate_ironic_db()
{
    if [ -f $STATE_DIR/ironic_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "/usr/bin/ironic-dbsync --config-file /etc/ironic/ironic.conf upgrade" ironic
        su -s /bin/sh -c "/usr/bin/ironic-inspector-dbsync --config-file /etc/ironic-inspector/inspector.conf upgrade" ironic-inspector
    fi

    touch $STATE_DIR/ironic_db_migrated
}

migrate_manila_db()
{
    if [ -f $STATE_DIR/manila_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "/usr/bin/manila-manage db sync" manila
    fi

    touch $STATE_DIR/manila_db_migrated
}

migrate_manila_db_post()
{
    if [ -f $STATE_DIR/manila_db_post_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        manila service-disable $HOSTNAME@cephfsnative manila-share 2>/dev/null
    fi

    touch $STATE_DIR/manila_db_post_migrated
}

migrate_masakari_db()
{
    if [ -f $STATE_DIR/masakari_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "/usr/bin/masakari-manage db sync" masakari
    fi

    touch $STATE_DIR/masakari_db_migrated
}

migrate_monasca_db()
{
    if [ -f $STATE_DIR/monasca_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "/usr/bin/monasca_db upgrade" monasca
    fi

    touch $STATE_DIR/monasca_db_migrated
}

migrate_designate_db()
{
    if [ -f $STATE_DIR/designate_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "/usr/bin/designate-manage database sync" designate
    fi

    touch $STATE_DIR/designate_db_migrated
}

migrate_octavia_db()
{
    if [ -f $STATE_DIR/octavia_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "/usr/bin/octavia-db-manage upgrade head" octavia
    fi

    touch $STATE_DIR/octavia_db_migrated
}

migrate_watcher_db()
{
    if [ -f $STATE_DIR/watcher_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "watcher-db-manage --config-file /etc/watcher/watcher.conf upgrade" watcher
    fi

    touch $STATE_DIR/watcher_db_migrated
}

migrate_cyborg_db()
{
    if [ -f $STATE_DIR/cyborg_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "cyborg-dbsync --config-file /etc/cyborg/cyborg.conf upgrade" cyborg
    fi

    touch $STATE_DIR/cyborg_db_migrated
}

migrate_ceph()
{
    if [ -f $STATE_DIR/ceph_cluster_migrated ] ; then
        return 0
    fi
    Quiet -n $HEX_SDK ceph_wait_for_services

    local release=$($CEPH version  -f json | jq -r .version | cut -d" " -f5)

    # NOT `$CEPH osd require-osd-release $release`. That took the *local* CLI's
    # release and pinned the cluster to it unconditionally, which is wrong twice
    # over on a rolling upgrade: on the first node to reboot into reef it asks a
    # cluster that still holds quincy OSDs to disallow pre-reef ones, ceph
    # refuses, the refusal is not checked -- and the marker below is written
    # anyway, so it is never retried and the cluster stays on
    # require_osd_release quincy for good.
    #
    # Finalization is not done here. migrate_ceph short-circuits on its own
    # ceph_cluster_migrated marker, so it is one-shot per node and cannot retry -- on
    # the node that matters it has usually already run. config_ceph.cpp's Commit()
    # owns it instead, from every node, retried while its own upgrade marker stands.

    case $release in
        nautilus|pacific|quincy|reef)
            for p in $($CEPH osd pool ls) ; do
                local mode=$($CEPH osd pool get $p pg_autoscale_mode | awk '{print $2}' | tr -d '\n')
                if [ "$mode" != "on" ] ; then
                    $CEPH osd pool set $p pg_autoscale_mode on
                fi
            done
            ;;
        *)
            ;;
    esac
    if [ -e $CEPHFS_CLIENT_AUTHKEY -a -s $CEPHFS_CLIENT_AUTHKEY ] ; then
        :
    else
        ceph-authtool -p $ADMIN_KEYRING > $CEPHFS_CLIENT_AUTHKEY
        chmod 0600 $CEPHFS_CLIENT_AUTHKEY 2>/dev/null
    fi

    touch $STATE_DIR/ceph_cluster_migrated
}

migrate_pacemaker_remote()
{
    if [ -f $STATE_DIR/pacemaker_remote_migrated ] ; then
        return 0
    fi

    local master=$1
    local hostname=$(hostname)

    if is_pure_compute_node ; then
        systemctl stop pacemaker_remote
        remote_run $master $HEX_SDK pacemaker_remote_remove $hostname
        for OFF_N in $($HEX_SDK remote_run $master "pcs status nodes 2>/dev/null" | grep "Remote Nodes:" -A 99 | grep "Offline:" | cut -d":" -f2) ; do
            remote_run $master $HEX_SDK pacemaker_remote_remove $OFF_N
        done
        remote_run $master $HEX_SDK pacemaker_remote_add $hostname
    fi

    touch $STATE_DIR/pacemaker_remote_migrated
}

migrate_libvirt()
{
    # During a rolling upgrade the new rootfs comes up with an empty /etc/libvirt/secrets;
    # update.sh stashed this node's own copy under /store/ppu first. Restore it wherever
    # there is one -- a compute node needs the ceph secret to open rbd volumes just as much
    # as a control does, and gating this on is_control_node was half of why a freshly
    # upgraded compute could not be live-migrated onto (#856); the other half is that
    # nothing recreated it there, which config_nova now does.
    ls /etc/libvirt/secrets/*.{base64,xml} >/dev/null 2>&1 || \
        { ls /store/ppu/libvirt/secrets/* >/dev/null 2>&1 && \
          cp -r /store/ppu/libvirt/secrets/* /etc/libvirt/secrets/ ; }

    touch /run/cube_libvirt
}
