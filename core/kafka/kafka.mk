# Cube SDK
# zookeeper/kafka installation

KAFKA_BIN_DIR := /opt/kafka
KAFKA_APP_DIR := /var/lib/kafka
KAFKA_LOG_DIR := /var/log/kafka
KAFKA_RUN_DIR := /var/run/kafka

KAFKA_VER := 3.9.2
KAFKA_TGZ := kafka_2.13-$(KAFKA_VER).tgz
KAFKA_DL_URL := https://archive.apache.org/dist/kafka/$(KAFKA_VER)
# The Apache release manager who signed this release. Apache signs per-signer rather than
# per-project, so this belongs next to KAFKA_VER and moves with it -- a bump that forgets
# it fails the build instead of quietly trusting whatever the KEYS file carries. Find the
# new one with: gpg --verify <tgz>.asc <tgz>
KAFKA_GPG_FPR := D9472951E133753353DCE20D72E522CC9FCBBAC9

# Checked with gpgv rather than `gpg --verify` -- see the note on the logstash rule in
# core/elk/elk.mk; gpg needs gpg-agent to read a keyring and the agent does not reliably
# start under mountrootfs.
#
# Download to .part and only rename once the detached signature checks out, so a truncated
# or tampered object is never left where the next run would unpack it as a finished
# download. KEYS comes from downloads.apache.org, a different host to the tarball's.
$(ARCS_DIR)/$(KAFKA_TGZ):
	$(Q)wget $(KAFKA_DL_URL)/$(KAFKA_TGZ) -O $@.part
	$(Q)wget $(KAFKA_DL_URL)/$(KAFKA_TGZ).asc -O $@.asc
	$(Q)wget -qO- https://downloads.apache.org/kafka/KEYS | gpg --dearmor > $@.gpg
	$(Q)gpgv --keyring $@.gpg --status-fd 1 $@.asc $@.part | \
		grep -q '^\[GNUPG:\] VALIDSIG $(KAFKA_GPG_FPR) '
	$(Q)rm -f $@.asc $@.gpg
	$(Q)mv $@.part $@

rootfs_install:: $(ARCS_DIR)/$(KAFKA_TGZ)
	$(Q)chroot $(ROOTDIR) mkdir -p $(KAFKA_BIN_DIR) $(KAFKA_APP_DIR) $(KAFKA_LOG_DIR) $(KAFKA_RUN_DIR)
	$(Q)tar -I pigz -xvf $< --directory $(ROOTDIR)$(KAFKA_BIN_DIR) --strip-components 1
	$(Q)chroot $(ROOTDIR) chown kafka:kafka $(KAFKA_BIN_DIR) $(KAFKA_APP_DIR) $(KAFKA_LOG_DIR) $(KAFKA_RUN_DIR)
	$(Q)cp -f $(ROOTDIR)$(KAFKA_BIN_DIR)/config/zookeeper.properties $(ROOTDIR)$(KAFKA_BIN_DIR)/config/zookeeper.properties.def
	$(Q)cp -f $(ROOTDIR)$(KAFKA_BIN_DIR)/config/server.properties $(ROOTDIR)$(KAFKA_BIN_DIR)/config/server.properties.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/kafka/zookeeper.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/kafka/kafka.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/kafka/log4j.properties ./opt/kafka/config/

ZK_LOG_DIR := /var/log/zookeeper

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(ZK_LOG_DIR)
	$(Q)chroot $(ROOTDIR) chown zookeeper:zookeeper $(ZK_LOG_DIR)
