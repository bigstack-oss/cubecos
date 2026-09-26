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
             masakari neutron nova octavia placement skyline watcher ; do
        $OPENSTACK user show $u >/dev/null 2>&1 || continue
        $OPENSTACK role add --project service --user $u service >/dev/null 2>&1
    done

    touch $STATE_DIR/keystone_service_role_migrated
}

# Retiring an OpenStack service leaves state behind that the A/B partition swap does not
# take: its keystone catalogue entries, its MySQL database and the MySQL users that own it.
# Everything under /etc, in a venv or in a unit file lives only in the rootfs and goes with
# it; these three do not.
#
# The keystone half is the part that has to be done rather than left. A catalogue entry is
# what clients discover, so an endpoint pointing at a port nothing listens on is not
# untidiness: an SDK that asks for it waits out its own timeout, and `openstack endpoint
# list` shows an appliance advertising a service it does not have.
#
# Endpoints go before the service, because keystone refuses to delete a service that still
# has them on some releases and an orphaned endpoint is the harder one to find afterwards.
# The user is domain-scoped: every service user is created with --domain, so deleting one
# by bare name only works while the name happens to be unique across domains.
_migrate_os_retire_keystone()
{
    local service=$1
    local user=$2
    local domain ep

    source hex_tuning /etc/settings.txt cubesys.domain
    domain=${T_cubesys_domain:-default}

    for ep in $($OPENSTACK endpoint list --service "$service" -f value -c ID 2>/dev/null) ; do
        Quiet -n $OPENSTACK endpoint delete $ep
    done
    Quiet -n $OPENSTACK service delete "$service"
    [ -n "$user" ] && Quiet -n $OPENSTACK user delete --domain $domain "$user"

    return 0
}

# Monasca, removed from the build by issue #672 phase 4.
#
# What is deliberately NOT done here:
#
#   the influxdb monasca database   it holds real history an operator may still want to
#                                   read, and it ages out under the retention policy it
#                                   was last given. Dropping it is the one irreversible
#                                   step in this retirement and belongs to the operator.
#   the monasca.* tunings           /etc/settings.txt is the appliance's own source of
#                                   truth and editing it from the side is worse than the
#                                   "Unknown settings name ... ignored" warning each
#                                   leftover key logs on a commit.
migrate_monasca_retire()
{
    if [ -f $STATE_DIR/monasca_retired ] ; then
        return 0
    fi

    is_control_node || return 0

    _migrate_os_retire_keystone monasca-api monasca

    # Both the database and the grants. Leaving the users behind would leave accounts with
    # rights on a schema nothing owns any more.
    $MYSQL -e "DROP DATABASE IF EXISTS monasca"
    $MYSQL -e "DROP USER IF EXISTS 'monasca'@'%'"
    $MYSQL -e "DROP USER IF EXISTS 'monasca'@'localhost'"
    $MYSQL -e "FLUSH PRIVILEGES"

    touch $STATE_DIR/monasca_retired
}

# Senlin, removed from the build by d4550c91 back on the yoga train. Its cleanup used to be
# an operator-invoked hex_cli command, `management cleanup cleanup_senlin`, which is the
# reason this exists: a retirement that only happens when somebody remembers to type it
# does not happen. Nothing tells an operator the command is there, nothing tells them which
# release needs it, and a cluster that has rolled through three upgrades since still
# advertises a clustering endpoint.
#
# It also only did half the job. config_senlin.cpp created a senlin database with grants to
# 'senlin'@'localhost' and 'senlin'@'%'; the CLI command deleted the endpoints, the service
# and the user and left all three of those behind, on every cluster upgraded from that era.
migrate_senlin_retire()
{
    if [ -f $STATE_DIR/senlin_retired ] ; then
        return 0
    fi

    is_control_node || return 0

    _migrate_os_retire_keystone senlin senlin

    $MYSQL -e "DROP DATABASE IF EXISTS senlin"
    $MYSQL -e "DROP USER IF EXISTS 'senlin'@'%'"
    $MYSQL -e "DROP USER IF EXISTS 'senlin'@'localhost'"
    $MYSQL -e "FLUSH PRIVILEGES"

    touch $STATE_DIR/senlin_retired
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

migrate_cinder_ext_storage_unsupported()
{
    local f

    if [ -f $STATE_DIR/cinder_ext_storage_unsupported_migrated ] ; then
        return 0
    fi

    if ! is_control_node ; then
        touch $STATE_DIR/cinder_ext_storage_unsupported_migrated
        return 0
    fi

    # Caracal ships the Dell Storage Center drivers with SUPPORTED = False, so
    # cinder-volume refuses to initialize the backend unless the operator opts in
    # with enable_unsupported_driver. The built-in model carries that opt-in now,
    # but a model only reaches backends created or re-applied after the upgrade.
    # /etc/cinder/backends is CONFIG_MIGRATE'd (config_cinder.cpp), so an upgraded
    # cluster carries its pre-Caracal backend config forward verbatim and the
    # driver stays dead -- every attach failing with
    #   'SCFCDriver' object has no attribute '_client'
    # and with it the live migration a rolling upgrade drains each node with.
    #
    # Only /etc/cinder/backends is rewritten, because that is the source of truth
    # and the only copy that lasts: config_cinder calls this from
    # SetStorageBackend(), immediately before it wipes cinder.d/ext_storage_*.conf
    # and re-copies them from here. Writing cinder.d as well would be undone by
    # that copy seconds later.
    #
    # Insert after volume_driver rather than appending: these files hold one
    # section each today, but appending would land outside the section the day one
    # does not. iSCSI is matched as well -- same upstream flag, same failure --
    # even though only the FC model ships built in.
    for f in /etc/cinder/backends/ext_storage_*.conf ; do
        [ -f "$f" ] || continue
        grep -qE "^volume_driver[[:space:]]*=.*storagecenter_(fc|iscsi)\." "$f" || continue
        grep -qE "^enable_unsupported_driver" "$f" && continue
        sed -i "/^volume_driver[[:space:]]*=.*storagecenter_/a enable_unsupported_driver = True" "$f"
        log_info "migrate_cinder_ext_storage_unsupported: opted $f into the unsupported SC driver"
    done

    touch $STATE_DIR/cinder_ext_storage_unsupported_migrated
}

migrate_cinder_ext_storage_fujitsu_password()
{
    local f

    if [ -f $STATE_DIR/cinder_ext_storage_fujitsu_password_migrated ] ; then
        return 0
    fi

    if ! is_control_node ; then
        touch $STATE_DIR/cinder_ext_storage_fujitsu_password_migrated
        return 0
    fi

    # Epoxy's ETERNUS DX driver logs into the array's CLI with an SSH key unless
    # told otherwise: fujitsu_passwordless is new in 2025.1 and defaults to True,
    # and the key it then reads is fujitsu_private_key_path, which nothing on
    # CubeCOS provisions. Caracal always logged in with the EternusUser and
    # EternusPassword of the backend's cinder_eternus_config_file, which is how the
    # built-in models are set up, so every CLI call an upgraded Fujitsu backend
    # makes would fail -- upstream's upgrade note tells existing users to pin
    # fujitsu_passwordless = False. The models carry that pin now, but a model only
    # reaches backends created or re-applied after the upgrade, so the backends
    # /etc/cinder/backends already holds are pinned here, the same way and for the
    # same reasons migrate_cinder_ext_storage_unsupported opts SC backends in.
    #
    # A backend that already names fujitsu_passwordless is left alone: that is an
    # operator's choice, made after the option existed.
    for f in /etc/cinder/backends/ext_storage_*.conf ; do
        [ -f "$f" ] || continue
        grep -qE "^volume_driver[[:space:]]*=.*eternus_dx_(fc|iscsi)\." "$f" || continue
        grep -qE "^fujitsu_passwordless" "$f" && continue
        sed -i "/^volume_driver[[:space:]]*=.*eternus_dx_/a fujitsu_passwordless = False" "$f"
        log_info "migrate_cinder_ext_storage_fujitsu_password: kept $f on the ETERNUS password login"
    done

    touch $STATE_DIR/cinder_ext_storage_fujitsu_password_migrated
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

        # No compatibility shim for the caracal <-> epoxy window: every migration
        # 2024.2 and 2025.1 add is an additive expand (numa_affinity_policy's
        # 'socket', the porttrusted table, networks.qinq), the contract head does not
        # move, and a caracal neutron-server names none of them.
        #
        # Exactly one such shim is carried at a time. The supported upgrade path is
        # stepwise -- 3.1.10 (Antelope) -> 3.1.20 (Caracal) -> 3.2.0 (Epoxy), no jumping -- so
        # an epoxy build can never meet an Antelope neutron-server, and the
        # Antelope <-> Caracal subnets.in_use shim that used to live here (#1431) is
        # dead code. Its leftover is not: the shim re-added the column for the mixed
        # window and left dropping it to migrate_neutron_db_post(), which only
        # cluster_start ran, and a master-first roll never reaches it -- so a 3.1.20
        # cluster can still carry the column. Neither caracal's nor epoxy's ORM names
        # it (HasInUse is only the two lock registers in both), so it goes here, on the
        # first control node that migrates, whatever the others still run.
        $MYSQL -u root -D neutron -e "ALTER TABLE subnets DROP COLUMN IF EXISTS in_use"
    fi

    touch $STATE_DIR/neutron_db_migrated
}

migrate_neutron_ovn_sync()
{
    local i=0

    if [ -f $STATE_DIR/neutron_ovn_migrated ] ; then
        return 0
    fi

    if ! is_control_node ; then
        touch $STATE_DIR/neutron_ovn_migrated
        return 0
    fi

    # The OVN northbound DB lives under /etc/ovn on the A/B root partition, so an
    # upgrade boots into an empty one: the networks exist only in neutron's MySQL
    # until this sync rebuilds them. Until it does, the OVN mechanism driver fails
    # every port bind with
    #   RowNotFound: Cannot find Logical_Switch with name=neutron-<network-id>
    # which takes out port binding, and with it the live migration that
    # rolling_upgrade drains each node with. Diagnosed on cube4510 during the
    # 3.1.10 -> 3.1.20 roll (2026-09-05).
    #
    # config_neutron calls this from CommitLast(), not Commit(): ovndb_servers is
    # promoted by pacemaker_last, and CONFIG_REQUIRES(neutron_last, pacemaker_last)
    # is what puts this after the promotion. Called from Commit() it ran a measured
    # 8 minutes before the northbound was listening and silently did nothing.
    #
    # Everything below is bounded, because this runs inside a hex_config commit:
    # blocking here blocks the node's whole bootstrap, and with it its slot in a
    # rolling upgrade.
    #
    # - The probe is a safety net for a slow promotion, not the mechanism -- the
    #   ordering above is. Worst case 24 * (5s connect + 5s sleep) = 4 minutes,
    #   then give up and leave it for the next boot. Probe the VIP the way
    #   neutron's ovn_nb_connection does rather than a local socket, since the
    #   promoted node may be another one.
    # - The sync itself gets a hard timeout. It takes seconds in practice; 600s is
    #   the ceiling that keeps a wedged sync from eating the roll's node deadline.
    # - Only mark the migration done when the sync actually succeeded. Marking it
    #   unconditionally turned one early failure into a permanent skip: the marker
    #   lives under /etc/appliance/state, which is CONFIG_MIGRATE'd, so it rode
    #   onto the next partition and no later boot ever retried. Returning without
    #   the marker leaves it to the next boot / cluster_start instead.
    local nb="tcp:$($HEX_SDK shared_id):6641"
    while [ $i -lt 24 ] ; do
        ovn-nbctl --db="$nb" --timeout=5 show >/dev/null 2>&1 && break
        sleep 5
        i=$((i + 1))
    done
    if [ $i -ge 24 ] ; then
        log_warning "migrate_neutron_ovn_sync: OVN northbound $nb not reachable; leaving the sync for the next boot"
        return 0
    fi

    if ! timeout 600 neutron-ovn-db-sync-util --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini --ovn-neutron_sync_mode repair ; then
        log_warning "migrate_neutron_ovn_sync: sync failed or timed out; leaving it for the next boot"
        return 0
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
        # cyborg 14.1.0 (CVE-2026-40214) scopes an ARQ to its project_id, a column
        # 12.0.0 never filled in -- nova's bind does not send one -- so every ARQ bound
        # before the upgrade would drop out of what a non-admin caller can see, nova
        # acting for the instance's owner included. online_data_migrations backfills
        # it from nova's record of each bound instance, the step upstream's upgrade
        # notes place between the schema upgrade and the service restart.
        # cyborg-conductor repeats it at startup, but only logs a failure there. Chain
        # the marker to it, the way migrate_nova_db_post() does, so a failure is
        # retried by the next Commit() rather than recorded as done.
        ( su -s /bin/sh -c "cyborg-dbsync --config-file /etc/cyborg/cyborg.conf online_data_migrations" cyborg && \
              touch $STATE_DIR/cyborg_db_migrated ) || true
    else
        touch $STATE_DIR/cyborg_db_migrated
    fi
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

# Retire the ceph-mgr influx module on a cluster upgraded from a release that had it
# enabled. From v3.1.20 the mgr's own prometheus module is the source of ceph metrics,
# enabled per node by config_ceph.cpp and scraped through haproxy, so the influx route
# is both redundant and the non-HA one: only the active mgr writes, which left the ceph
# database populated on one node of three.
#
# This is not free with the A/B partition switch. The module enablement lives in the mon
# quorum's mgr map and mgr/influx/* in the mon config store, neither of which is on the
# rootfs -- a rolling upgrade carries both forward untouched, so nothing clears them
# unless we do it here.
#
# No marker of its own, deliberately. Same lesson migrate_ceph records above: a one-shot
# per-node marker cannot retry, and this needs a serving mgr that a freshly booted node
# often does not have yet. config_ceph.cpp's Commit owns the gate and keys off a marker
# it clears only on rc 0, so an early run against an unavailable mgr is retried on the
# next commit. Returns non-zero until the state is actually clean.
migrate_ceph_mgr_influx()
{
    local ready=$($CEPH mgr dump -f json 2>/dev/null | jq -r .available 2>/dev/null | tr -d '\n')
    if [ "$ready" != "true" ] ; then
        log_info "migrate_ceph_mgr_influx: no serving mgr yet, will retry"
        return 1
    fi

    local modules=$($CEPH mgr module ls -f json 2>/dev/null)
    if [ "x$modules" = "x" ] ; then
        log_info "migrate_ceph_mgr_influx: mgr module list unavailable, will retry"
        return 1
    fi

    if echo "$modules" | jq -r '.enabled_modules[]' | grep -qx influx ; then
        log_info "migrate_ceph_mgr_influx: disabling the influx mgr module"
        $CEPH mgr module disable influx || return 1
    fi

    # Enumerated rather than named, so a hostname/port/interval set by an older release,
    # by health_ceph_mgr's old auto-repair, or by hand all go the same way. The section is
    # taken from the dump too: config-set wrote them under 'mgr', but a hand-set key could
    # sit under mgr.<id>.
    local keys=$($CEPH config dump -f json 2>/dev/null | \
                 jq -r '.[] | select(.name | startswith("mgr/influx/")) | "\(.section) \(.name)"')
    local section name
    while read -r section name ; do
        [ "x$name" = "x" ] && continue
        log_info "migrate_ceph_mgr_influx: removing $section $name"
        $CEPH config rm $section $name || return 1
    done <<< "$keys"

    return 0
}
