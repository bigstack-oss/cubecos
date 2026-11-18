# stand in for the default config populated by the manila rootfs
mkdir -p /etc/manila
: > /etc/manila/manila.conf.def
rm -f /etc/manila/manila.conf /tmp/settings.txt /tmp/commit_manila_*.log
touch /etc/settings.txt
