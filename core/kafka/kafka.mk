# Cube SDK
# zookeeper/kafka installation

KAFKA_BIN_DIR := /opt/kafka
KAFKA_APP_DIR := /var/lib/kafka
KAFKA_LOG_DIR := /var/log/kafka
KAFKA_RUN_DIR := /var/run/kafka

KAFKA_VER := 3.8.0
KAFKA_TGZ := kafka_2.13-$(KAFKA_VER).tgz

$(ARCS_DIR)/$(KAFKA_TGZ):
	$(Q)wget https://downloads.apache.org/kafka/$(KAFKA_VER)/$(KAFKA_TGZ) -O $@

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
