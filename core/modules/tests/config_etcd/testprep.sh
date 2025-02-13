# backup original etcdctl first
if [ -f /usr/bin/etcdctl ]; then
  mv /usr/bin/etcdctl /usr/bin/etcdctl.bak
fi

# backup original curl first
if [ -f /usr/bin/curl ]; then
  mv /usr/bin/curl /usr/bin/curl.bak
fi

rm -f /etc/appliance/state/etcd_member_id
rm -f /etc/etcd/etcd.conf.yml

touch /etc/settings.txt