CURRENT_VERSION=$(/bin/grep 'sys.product.version' /etc/settings.sys | /usr/bin/awk '{print $NF}')
FIRST_CTRLHOST=$(cubectl node list | head -n1 | awk -F"," '{print $1}')

# Removing cube.git is a must such that new firmware does not pull check-ins from old one
rm -rf /var/support/localrpms /var/support/map_* /mnt/cephfs/backup/cube.git /store/ppu
mkdir -p /store/ppu/libvirt/secrets/
cubectl node list -j > /store/ppu/cluster-info.json
cp /etc/libvirt/secrets/* /store/ppu/libvirt/secrets/

# Cluster level tasks
# Run on first control node only
if [ "$FIRST_CTRLHOST" == "$(hostname)" ]; then
    # Workaround: restart etcd to let etcd-watch to apply pending tunning updates
    systemctl restart etcd && sleep 60
    # Backup k3s etcd data
    k3s etcd-snapshot
    # Backup mysql
    hex_sdk support_mysql_backup_create

    # Version specific tasks
    # Removing leagacy k3s workloads before 2.3.0
    if [ "$CURRENT_VERSION" = $(echo -e "$CURRENT_VERSION\n2.3.0" | sort -V | head -n1) ]; then
        cubectl config reset --hard manageiq postgresql tyk redis mongodb || true
        k3s kubectl delete -n cattle-system -R -f /opt/manifests/rancher/ || true
        k3s kubectl delete -n keycloak -R -f /opt/manifests/keycloak/ || true
        k3s kubectl delete -n ingress-nginx -R -f /opt/manifests/ingress-nginx/ || true
        # Mark all nodes unschedulable
        k3s kubectl taint node --all not_upgraded=true:NoSchedule
    fi
fi
