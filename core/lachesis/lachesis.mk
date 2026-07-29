# Cube SDK
# lachesis (per-tenant network telemetry agent) installation

LACHESIS_RPM = $(TOP_BLDDIR)/core/lachesis/lachesis.rpm

# the rpm owns /etc/cube/lachesis, /var/lib/lachesis and /var/log/lachesis.
# installed disabled everywhere; config_lachesis enables per role at commit time.
rootfs_install::
	$(Q)cp -f $(LACHESIS_RPM) $(ROOTDIR)/tmp/
	$(Q)chroot $(ROOTDIR) dnf install -y /tmp/lachesis.rpm
	$(Q)rm -f $(ROOTDIR)/tmp/lachesis.rpm
	$(Q)chroot $(ROOTDIR) systemctl disable lachesis
	$(Q)cp -f $(COREDIR)/lachesis/lachesis.yaml.in $(ROOTDIR)/etc/cube/lachesis/

# for RC builds
heavyfs_install::
	$(Q)cp -f $(LACHESIS_RPM) $(ROOTDIR)/tmp/
	$(Q)chroot $(ROOTDIR) rpm -e lachesis
	$(Q)chroot $(ROOTDIR) rpm -i /tmp/lachesis.rpm
	$(Q)rm -f $(ROOTDIR)/tmp/lachesis.rpm
	$(Q)chroot $(ROOTDIR) systemctl disable lachesis
	$(Q)cp -f $(COREDIR)/lachesis/lachesis.yaml.in $(ROOTDIR)/etc/cube/lachesis/
