# Cube SDK
# thanos installation

THANOS_VER := 0.42.4
THANOS_TGZ := thanos-$(THANOS_VER).linux-amd64.tar.gz
THANOS_DL_URL := https://github.com/thanos-io/thanos/releases/download/v$(THANOS_VER)

# Thanos publishes no detached signature, only a sha256sums.txt covering the whole
# release, so that is what is checked. It comes from the same host as the tarball, which
# is weaker than kafka's cross-host KEYS, but it is all upstream offers -- and it still
# catches a truncated or swapped object. As with kafka, download to .part and only rename
# once the digest matches, so a bad object is never left where the next run unpacks it.
$(ARCS_DIR)/$(THANOS_TGZ):
	$(Q)wget $(THANOS_DL_URL)/$(THANOS_TGZ) -O $@.part
	$(Q)wget -qO- $(THANOS_DL_URL)/sha256sums.txt | grep " $(THANOS_TGZ)$$" | \
		sed "s#$(THANOS_TGZ)#$@.part#" | sha256sum -c -
	$(Q)mv $@.part $@

rootfs_install:: $(ARCS_DIR)/$(THANOS_TGZ)
	$(Q)tar -I pigz -xf $< --directory $(ROOTDIR)/usr/bin --strip-components 1 --wildcards '*/thanos'
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/thanos
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/thanos/thanos-sidecar.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/thanos/thanos-query.service ./lib/systemd/system
	$(Q)chroot $(ROOTDIR) systemctl disable thanos-sidecar
	$(Q)chroot $(ROOTDIR) systemctl disable thanos-query
