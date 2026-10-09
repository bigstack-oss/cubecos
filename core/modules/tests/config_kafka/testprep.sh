# stand in for what core/kafka/kafka.mk and the rootfs populate in a real image
mkdir -p /opt/kafka/config /etc/logrotate.d
touch /opt/kafka/config/zookeeper.properties.def /opt/kafka/config/server.properties.def
id zookeeper >/dev/null 2>&1 || useradd -r -M -s /sbin/nologin zookeeper

# keep anything already in the log dirs out of the way; testpost.sh puts it back
for d in /var/log/kafka /var/log/zookeeper; do
    if [ -d $d ] && [ ! -d $d.test-orig ]; then
        mv $d $d.test-orig
    fi
    mkdir -p $d
done

# stand-in units rather than a mocked systemctl: the jail runs real systemd as PID 1,
# so SystemdCommitService is exercised for real
for svc in zookeeper kafka; do
    cat > /usr/lib/systemd/system/$svc.service <<UNIT
[Unit]
Description=$svc test stand-in (config_kafka unit test)

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true

[Install]
WantedBy=multi-user.target
UNIT
done
systemctl daemon-reload

touch /etc/settings.txt
