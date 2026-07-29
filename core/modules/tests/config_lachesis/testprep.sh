# stand in for what the component .mk and rpm populate in a real rootfs
mkdir -p /etc/cube/lachesis /var/log/lachesis /var/lib/lachesis
rm -f /etc/cube/lachesis/lachesis.yaml

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
cp -f $DIR/../../../lachesis/lachesis.yaml.in /etc/cube/lachesis/lachesis.yaml.in

# a stand-in unit rather than a mocked systemctl: the jail runs real systemd as
# PID 1, so SystemdCommitService is exercised for real and is-active reads back
cat > /usr/lib/systemd/system/lachesis.service <<'UNIT'
[Unit]
Description=lachesis test stand-in (config_lachesis unit test)

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl stop lachesis >/dev/null 2>&1

touch /etc/settings.txt
