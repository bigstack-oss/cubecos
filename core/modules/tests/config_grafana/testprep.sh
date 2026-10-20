# stand in for what the grafana rpm populates in a real rootfs
mkdir -p /etc/grafana /var/lib/grafana /var/log/grafana
rm -f /etc/grafana/grafana.ini /var/lib/grafana/grafana.db
