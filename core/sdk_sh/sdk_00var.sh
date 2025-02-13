# service status request timeout
SRVTO=60
SRVLTO=120
SRVSTO=10

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
GIT="timeout $SRVLTO /usr/bin/git"
MAPFILE=/tmp/monmap.sdk
CRUSHMAPFILE=/tmp/crushmap.sdk
BUILTIN_BACKPOOL=cinder-volumes
BUILTIN_CACHEPOOL=cachepool
BUILTIN_EPHEMERAL=ephemeral-vms

ETCDCTL="/usr/local/bin/etcdctl --endpoints=$HOSTNAME:12379"
CURL="timeout $SRVTO /usr/bin/curl"
MYSQL="timeout $SRVTO /usr/bin/mysql"

