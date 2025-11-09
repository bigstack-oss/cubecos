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
    # Backup mysql
    hex_sdk support_mysql_backup_create
fi


echo "Firmware on $HOSTNAME has been updated with success!"
