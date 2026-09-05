# Cube SDK
# Prometheus installation

# EPEL's `prometheus` is the 3.x line. packagecloud's `prometheus2` stops at 2.55.1 and
# every 2.x LTS is EOL (2.37 2023-07-31, 2.45 2024-07-31, 2.53 2025-07-31); 2.55 was never
# an LTS at all. 3.13 is the current LTS, supported to 2027-07-31.
#
# This also retires the source build that used to live in core/prometheus/Makefile. Its one
# real benefit was building against the jail's Go rather than a stale release toolchain --
# and EPEL builds 3.13.1 with go1.26.4, ahead of the jail's go1.25.12, so that reason is
# gone. Using the rpm also keeps the package identity honest: syft catalogues an rpm-owned
# binary at the rpm's version (exclude-binary-overlap-by-ownership), so a source-built 3.x
# dropped on top of a 2.55.1 rpm would have been reported as 2.55.1 in the SBOM forever.
ROOTFS_DNF += prometheus

# This also drops packagecloud's prometheus.repo, which prometheus2 was its only consumer of.
# It was kept in reserve for the exporters, but it is stale everywhere it matters -- against
# upstream: node_exporter 1.9.0 vs 1.12.1, blackbox 0.26.0 vs 0.28.0, memcached 0.15.0 vs
# 0.17.0, apache 1.0.10 vs 1.1.1, mysqld 0.17.2 vs 0.20.0, snmp 0.28.0 vs 0.30.1, statsd
# 0.28.0 vs 0.31.0 -- the same neglect that left prometheus itself at 2.55.1. Of the exporters
# the telemetry replacement needs, EPEL carries only node-exporter (1.12.1, current), and no
# upstream exporter publishes an rpm at all: every one ships a linux-amd64.tar.gz and nothing
# else. So they come from EPEL where it has them and from the release tarballs otherwise, and
# there is no third-party rpm repo left to keep.

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p /var/log/prometheus
	$(Q)chroot $(ROOTDIR) chown prometheus:prometheus /var/log/prometheus
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/systemd/system/prometheus.service.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/prometheus/prometheus-restart.conf ./etc/systemd/system/prometheus.service.d/
	$(Q)chroot $(ROOTDIR) systemctl disable prometheus
	$(Q)mv -f $(ROOTDIR)/etc/prometheus/prometheus.yml $(ROOTDIR)/etc/prometheus/prometheus.yml.org
