#
# TEST - whether can generate etcd config successfully
#   1. using curl to send request to control node and get the mock response
#   2. generate etcd config
#

cat >/tmp/settings.txt <<EOF
cubesys.role=network
cubesys.controller=mydomain
cubesys.controller.ip=1.2.3.4
cubesys.control.hosts=node0,node4
cubesys.management=IF.1
etcd.enabled=true
net.hostname=node4
EOF

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# mock curl to return message of joining member successfully
cp $DIR/mock/curl/member_join_success /usr/bin/curl

./hex_config -vvve commit /tmp/settings.txt

result=$(cat /etc/etcd/etcd.conf.yml)

expect=$(cat -<< EOM
name: "node4"
initial-cluster: "demo-etcd-1=http://10.240.0.1:2380,demo-etcd-2=http://10.240.0.2:2380,demo-etcd-3=http://10.240.0.3:2380,node4=http://10.240.0.4:2380"
initial-cluster-state: "existing"
data-dir: /var/lib/etcd
initial-cluster-token: 'cube-etcd-cluster'
initial-advertise-peer-urls: http://9.4.8.7:2380
advertise-client-urls: http://9.4.8.7:2379
listen-peer-urls: http://0.0.0.0:2380
listen-client-urls: http://0.0.0.0:2379
EOM
)

if [ "${expect}" != "${result}" ]; then
  echo "ETCD config is not correctly generated."
  exit 1
fi