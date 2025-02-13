if [ -f /usr/bin/etcdctl.bak ]; then
  mv /usr/bin/etcdctl.bak /usr/bin/etcdctl
fi

if [ -f /usr/bin/curl.bak ]; then
  mv /usr/bin/curl.bak /usr/bin/curl
fi

rm /etc/settings.txt