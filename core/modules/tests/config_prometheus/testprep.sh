# stand in for what the component .mk and rpm populate in a real rootfs
mkdir -p /etc/prometheus/targets /etc/default /etc/cron.d /etc/logrotate.d /var/log/prometheus
rm -f /etc/prometheus/prometheus.yml

touch /etc/settings.txt
