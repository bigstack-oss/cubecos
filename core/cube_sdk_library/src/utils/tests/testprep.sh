#!/bin/sh

cat >/usr/sbin/hex_sdk <<EOF
#!/bin/bash

ifname=\$2

if [ "\$ifname" == "eth0" ]; then
  echo "eth0.10"
  echo "eth0.20"
  echo "br0"
elif [ "\$ifname" == "eth1" ]; then
  echo "br0"
  echo "eth0.10"
  echo "eth0.20"
elif [ "\$ifname" == "eth2" ]; then
  echo "bond0"
elif [ "\$ifname" == "bond0" ]; then
  echo "br0"
  echo "bond0.10"
  echo "bond0.20"
elif [ "\$ifname" == "eth3" ]; then
  echo "eth3.10"
elif [ "\$ifname" == "eth5" ]; then
  echo "bond1"
elif [ "\$ifname" == "bond1" ]; then
  echo "bond1.3500"
fi
EOF

chmod 755 /usr/sbin/hex_sdk