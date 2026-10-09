for svc in zookeeper kafka; do
    systemctl stop $svc >/dev/null 2>&1
    rm -f /usr/lib/systemd/system/$svc.service
done
systemctl daemon-reload >/dev/null 2>&1

for d in /var/log/kafka /var/log/zookeeper; do
    rm -rf $d
    [ -d $d.test-orig ] && mv $d.test-orig $d
done

rm -f /tmp/settings.txt /tmp/commit_kafka.log /tmp/logrotate_kafka.*
rm -f /etc/logrotate.d/kafka /etc/logrotate.d/zookeeper
