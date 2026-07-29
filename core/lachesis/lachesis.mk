# Cube SDK
# lachesis (per-tenant network telemetry agent) installation

LACHESIS_RPM = $(TOP_BLDDIR)/core/lachesis/lachesis.rpm

# grafana dashboards come from the lachesis clone, not a vendored copy, so they
# cannot drift from the metrics they query. grafana.mk installs provisioning/
# first: lachesis is last in HEAVY_COMPONENTS, so this lands on top of it.
LACHESIS_DASHBOARDS = $(TOP_BLDDIR)/core/lachesis/git/deploy/grafana/dashboards

# the rpm owns /etc/cube/lachesis, /var/lib/lachesis and /var/log/lachesis.
# installed disabled everywhere; config_lachesis enables per role at commit time.
rootfs_install::
	$(Q)cp -f $(LACHESIS_RPM) $(ROOTDIR)/tmp/
	$(Q)chroot $(ROOTDIR) dnf install -y /tmp/lachesis.rpm
	$(Q)rm -f $(ROOTDIR)/tmp/lachesis.rpm
	$(Q)chroot $(ROOTDIR) systemctl disable lachesis
	$(Q)cp -f $(COREDIR)/lachesis/lachesis.yaml.in $(ROOTDIR)/etc/cube/lachesis/
	$(Q)cp -f $(LACHESIS_DASHBOARDS)/*.json $(ROOTDIR)/etc/grafana/provisioning/dashboards/
	$(Q)chmod 0644 $(ROOTDIR)/etc/grafana/provisioning/dashboards/lachesis-*.json

# for RC builds
heavyfs_install::
	$(Q)cp -f $(LACHESIS_RPM) $(ROOTDIR)/tmp/
	$(Q)chroot $(ROOTDIR) rpm -e lachesis
	$(Q)chroot $(ROOTDIR) rpm -i /tmp/lachesis.rpm
	$(Q)rm -f $(ROOTDIR)/tmp/lachesis.rpm
	$(Q)chroot $(ROOTDIR) systemctl disable lachesis
	$(Q)cp -f $(COREDIR)/lachesis/lachesis.yaml.in $(ROOTDIR)/etc/cube/lachesis/
