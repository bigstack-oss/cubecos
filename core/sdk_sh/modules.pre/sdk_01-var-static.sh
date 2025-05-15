# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

if [ -f /etc/admin-openrc.sh ] ; then
    source /etc/admin-openrc.sh
fi

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin

# service status request timeout
SRVTO=60
SRVLTO=120
SRVSTO=10

HEX_SDK=/usr/sbin/hex_sdk
HEX_CFG=/usr/sbin/hex_config
HEX_CLI=/usr/sbin/hex_cli
HEX_TUN=/usr/sbin/hex_tuning
HEX_STATE_DIR=/etc/appliance/state
SETTINGS_TXT=/etc/settings.txt
SETTINGS_SYS=/etc/settings.sys

IP="timeout $SRVTO /sbin/ip"
OPENSTACK="timeout $SRVTO /usr/bin/openstack"
NOVA="timeout $SRVSTO /usr/local/bin/nova"
MANILA="timeout $SRVTO /usr/bin/manila"
DNF="/usr/bin/dnf"
WGET="timeout $SRVTO /usr/bin/wget"
CEPHFS_STORE_DIR=/mnt/cephfs
CEPHFS_BACKUP_DIR=/mnt/cephfs/backup
CEPHFS_GLANCE_DIR=/mnt/cephfs/glance
CEPHFS_NOVA_DIR=/mnt/cephfs/nova
CEPHFS_K8S_DIR=/mnt/cephfs/k8s
CEPHFS_UPDATE_DIR=/mnt/cephfs/update
ADMIN_KEYRING=/etc/ceph/ceph.client.admin.keyring
CEPHFS_CLIENT_AUTHKEY=/etc/ceph/admin.key
CEPH_OSD_MAP=/var/lib/ceph/osd/dev_osd.map
CEPH="timeout $SRVSTO /usr/bin/ceph"
GIT="timeout 300 /usr/bin/git"
MAPFILE=/tmp/monmap.sdk
CRUSHMAPFILE=/tmp/crushmap.sdk
BUILTIN_BACKPOOL=cinder-volumes
BUILTIN_CACHEPOOL=cachepool
BUILTIN_EPHEMERAL=ephemeral-vms

ETCDCTL="/usr/local/bin/etcdctl --endpoints=$HOSTNAME:12379"
TERRAFORM_CUBE="/usr/local/bin/terraform-cube.sh"
CURL="timeout $SRVTO /usr/bin/curl"
MYSQL="timeout $SRVTO /usr/bin/mysql"

RESERVED_USERS="admin_cli\|masakari\|placement\|heat\|glance\|monasca\|heat_domain_admin\|neutron\|nova\|cyborg\|cinder\|barbican\|manila\|octavia\|designate\|ironic\|ironic-inspector\|senlin\|watcher"

KUBECTL=/usr/local/bin/kubectl
KP_BIN="/usr/bin/kapacitor"
ALERT_RESP_DIR="/var/alert_resp"
ALERT_EXTRA="/etc/kapacitor/alert_extra/configs.yml"

NVIDIA_SMI=/usr/bin/nvidia-smi
NVIDIA_SRIOV=/usr/lib/nvidia/sriov-manage

STATE_DIR=/etc/appliance/state
OPS_MIGRATED=$STATE_DIR/ops_migrated

DEV_LIST=/var/appliance-db/device.lst

DB="\"hc\".\"sflow\""

NFS_DIR="/mnt/nfs"
POLICY_DIR="/etc/policies"
EVENTS_DB="events"
TELEGRAF_DB="telegraf"
MONASCA_DB="monasca"
CEPH_DB="ceph"
