# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

migrate_prepare()
{
    if is_control_node ; then
        # During rolling upgrade, maria times out to start on control 2 and 3
        touch /etc/appliance/state/mysql_new_cluster
    fi
    touch /run/cube_migration
}

migrate_keystone_db()
{
    if [ -f $STATE_DIR/keystone_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "keystone-manage db_sync" keystone

        keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
        keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
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
        su -s /bin/sh -c "glance-manage db_sync" glance
    fi

    touch $STATE_DIR/glance_db_migrated
}

migrate_heat_db()
{
    if [ -f $STATE_DIR/heat_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "heat-manage db_sync" heat
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
    fi

    touch $STATE_DIR/neutron_db_migrated
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
        if [[ "x$($OPENSTACK --version)" =~ "x$OPENSTACK 6." ]] ; then
            mysql -e "update nova.services set version = 61 where deleted = 0;"
        fi
    fi

    touch $STATE_DIR/nova_db_migrated
}

migrate_nova_db_post()
{
    mountpoint -- $CEPHFS_STORE_DIR  | grep -q "is a mountpoint" || ceph_mount_cephfs
    if [ ! -e ${CEPHFS_NOVA_DIR}/instances ] ; then
        mkdir -p ${CEPHFS_NOVA_DIR}/instances
        chown -R nova:nova ${CEPHFS_NOVA_DIR}
        chmod -R 0755 ${CEPHFS_NOVA_DIR}
        find /mnt/target/var/lib/nova/instances/* -maxdepth 1 -type d | grep -v -e locks -e compute_nodes -e _base | xargs -i cp -rpf {} /mnt/cephfs/nova/instances/
    fi

    if [ -f $STATE_DIR/nova_db_post_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "nova-manage db online_data_migrations" nova
        $HEX_SDK os_nova_service_remove $HOSTNAME "nova-consoleauth"
    fi

    touch $STATE_DIR/nova_db_post_migrated
}

migrate_ironic_db()
{
    if [ -f $STATE_DIR/ironic_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "ironic-dbsync --config-file /etc/ironic/ironic.conf upgrade" ironic
        su -s /bin/sh -c "ironic-inspector-dbsync --config-file /etc/ironic-inspector/inspector.conf upgrade" ironic-inspector
    fi

    touch $STATE_DIR/ironic_db_migrated
}

migrate_manila_db()
{
    if [ -f $STATE_DIR/manila_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "manila-manage db sync" manila
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
        su -s /bin/sh -c "/usr/local/bin/masakari-manage db sync" masakari
    fi

    touch $STATE_DIR/masakari_db_migrated
}

migrate_monasca_db()
{
    if [ -f $STATE_DIR/monasca_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "/usr/local/bin/monasca_db upgrade" monasca
    fi

    touch $STATE_DIR/monasca_db_migrated
}

migrate_designate_db()
{
    if [ -f $STATE_DIR/designate_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "/usr/local/bin/designate-manage database sync" designate
    fi

    touch $STATE_DIR/designate_db_migrated
}

migrate_octavia_db()
{
    if [ -f $STATE_DIR/octavia_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "octavia-db-manage upgrade head" octavia
    fi

    touch $STATE_DIR/octavia_db_migrated
}

migrate_senlin_db()
{
    if [ -f $STATE_DIR/senlin_db_migrated ] ; then
        return 0
    fi

    if is_control_node ; then
        su -s /bin/sh -c "senlin-manage db_sync" senlin
    fi

    touch $STATE_DIR/senlin_db_migrated
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
    $CEPH osd require-osd-release $release
    case $release in
        nautilus|pacific|quincy)
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
        for OFF_N in $($HEX_SDK remote_run $master "pcs status nodes" | grep "Remote Nodes:" -A 99 | grep "Offline:" | cut -d":" -f2) ; do
            remote_run $master $HEX_SDK pacemaker_remote_remove $OFF_N
        done
        remote_run $master $HEX_SDK pacemaker_remote_add $hostname
    fi

    touch $STATE_DIR/pacemaker_remote_migrated
}

migrate_libvirt()
{
    if is_control_node ; then
        # During rolling upgrade, master control has empty virsh secret-list
        ls /etc/libvirt/secrets/*.{base64,xml} >/dev/null 2>&1 || cp -r /store/ppu/libvirt/secrets/* /etc/libvirt/secrets/
    fi

    touch /run/cube_libvirt
}
