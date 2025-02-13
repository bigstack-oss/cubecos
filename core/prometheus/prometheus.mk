# Cube SDK
# Prometheus installation

ROOTFS_DNF += prometheus2

PROMETHEUS_REPO = $(shell cp $(COREDIR)/prometheus/prometheus.repo $(ROOTDIR)/etc/yum.repos.d/ ; echo "prometheus")

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p /var/log/prometheus
	$(Q)chroot $(ROOTDIR) chown prometheus:prometheus /var/log/prometheus
	$(Q)chroot $(ROOTDIR) systemctl disable prometheus
	$(Q)mv -f $(ROOTDIR)/etc/prometheus/prometheus.yml $(ROOTDIR)/etc/prometheus/prometheus.yml.org
