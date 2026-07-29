systemctl stop lachesis >/dev/null 2>&1
rm -f /usr/lib/systemd/system/lachesis.service
systemctl daemon-reload >/dev/null 2>&1
rm -f /tmp/settings.txt /etc/cube/lachesis/lachesis.yaml
