# Cube SDK
# elk installation (OpenSearch, Logstash and OpenSearch-Dashboards)

ifneq (,$(wildcard $(ROOTDIR)))
ELK_REPO := $(shell chroot $(ROOTDIR) rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch 2>/dev/null && cp $(COREDIR)/elk/elasticsearch/elastic.repo $(ROOTDIR)/etc/yum.repos.d/ ; echo "elastic")
OSEARCH := $(shell chroot $(ROOTDIR) rpm --import https://artifacts.opensearch.org/publickeys/opensearch.pgp && cp $(COREDIR)/elk/opensearch/opensearch.repo $(ROOTDIR)/etc/yum.repos.d/ ; echo "opensearch")
else
OSEARCH := $(shell echo "opensearch")
endif

LOGSTASH_VER := 9.2.3
LOGSTASH_CONF_DIR := /etc/logstash
LOGSTASH_CONF_D_DIR := $(LOGSTASH_CONF_DIR)/conf.d
LOGSTASH_CONF_EVENTDB_DIR := $(LOGSTASH_CONF_DIR)/eventdb
LOGSTASH_HOME := /usr/share/logstash
LOGSTASH_LOG_DIR := /var/log/logstash
LOGSTASH_LIB_DIR := /var/lib/logstash
LOGSTASH_JDK := $(LOGSTASH_HOME)/jdk

NODE_VERSION := 20
OSEARCH_VER := 3.4.0
OSEARCH_CONF_DIR := /etc/$(OSEARCH)
OSEARCH_CONF_SECURITY_DIR := $(OSEARCH_CONF_DIR)/opensearch-security
OSEARCH_HOME := /usr/share/$(OSEARCH)
OSEARCH_BOARDS_CONF_DIR := /etc/$(OSEARCH)-dashboards
OSEARCH_BOARDS_LOG_DIR := /var/log/$(OSEARCH)-dashboards
OSEARCH_DASHBOARDS := $(OSEARCH)-dashboards

BEATS_VER := 9.2.3
ROOTFS_DNF_DL_FROM += https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$(BEATS_VER)-x86_64.rpm
ROOTFS_DNF_DL_FROM += https://artifacts.elastic.co/downloads/beats/auditbeat/auditbeat-$(BEATS_VER)-x86_64.rpm

ROOTFS_DNF_DL_FROM += https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/$(OSEARCH_VER)/opensearch-dashboards-$(OSEARCH_VER)-linux-x64.rpm
ROOTFS_DNF_DL_FROM += https://artifacts.opensearch.org/releases/bundle/opensearch/$(OSEARCH_VER)/opensearch-$(OSEARCH_VER)-linux-x64.rpm
ROOTFS_PIP_NC += curator-$(OSEARCH)

LOGSTASH_TGZ := logstash-$(LOGSTASH_VER)-linux-x86_64.tar.gz
$(ARCS_DIR)/$(LOGSTASH_TGZ):
	$(Q)wget https://artifacts.elastic.co/downloads/logstash/$(LOGSTASH_TGZ) -O $@

rootfs_install:: $(ARCS_DIR)/$(LOGSTASH_TGZ)
	$(Q)tar xf $< -C $(ROOTDIR)/usr/share/
	$(Q)chroot $(ROOTDIR) sh -c 'sed "s/\/var\/run\//\/run\//g" /usr/lib/tmpfiles.d/$(OSEARCH).conf > /etc/tmpfiles.d/$(OSEARCH).conf'
	$(Q)chroot $(ROOTDIR) systemctl disable $(OSEARCH)
	$(Q)chroot $(ROOTDIR) /usr/share/opensearch-dashboards/bin/opensearch-dashboards-plugin --allow-root remove securityDashboards
	$(Q)mv $(ROOTDIR)/usr/share/logstash-$(LOGSTASH_VER) $(ROOTDIR)/usr/share/logstash
	$(Q)mv $(ROOTDIR)/usr/share/logstash/config $(ROOTDIR)$(LOGSTASH_CONF_DIR)
	$(Q)chroot $(ROOTDIR) mkdir -p $(OSEARCH_BOARDS_LOG_DIR) $(LOGSTASH_CONF_EVENTDB_DIR) $(LOGSTASH_LOG_DIR) $(LOGSTASH_LIB_DIR)
	$(Q)cp -f $(ROOTDIR)/etc/$(OSEARCH)/$(OSEARCH).yml $(ROOTDIR)/etc/$(OSEARCH)/$(OSEARCH).yml.orig
	$(Q)cp -f $(ROOTDIR)/etc/logstash/logstash.yml $(ROOTDIR)/etc/logstash/logstash.yml.orig
	$(Q)cp -f $(ROOTDIR)/etc/opensearch-dashboards/opensearch_dashboards.yml $(ROOTDIR)/etc/opensearch-dashboards/opensearch_dashboards.yml.orig
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/opensearch/config.yml .$(OSEARCH_CONF_SECURITY_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/opensearch/roles.yml .$(OSEARCH_CONF_SECURITY_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/opensearch/roles_mapping.yml .$(OSEARCH_CONF_SECURITY_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/pipelines.yml .$(LOGSTASH_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/patterns.txt .$(LOGSTASH_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/logs-ec-template.json.in .$(LOGSTASH_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/default-ec-template.json.in .$(LOGSTASH_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/eventdb/log-to-event-key.yml .$(LOGSTASH_CONF_EVENTDB_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/eventdb/event-key-to-msg.yml .$(LOGSTASH_CONF_EVENTDB_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/eventdb/ifname-to-ifkey.yml .$(LOGSTASH_CONF_EVENTDB_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/conf.d/log-transformer.conf.in .$(LOGSTASH_CONF_D_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/conf.d/auditlog-transformer.conf.in .$(LOGSTASH_CONF_D_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/conf.d/hex-event-mapper.conf.in .$(LOGSTASH_CONF_D_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/conf.d/ops-event-mapper.conf.in .$(LOGSTASH_CONF_D_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/conf.d/ceph-event-mapper.conf.in .$(LOGSTASH_CONF_D_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/conf.d/kernel-event-mapper.conf.in .$(LOGSTASH_CONF_D_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/conf.d/telegraf-persister.conf.in .$(LOGSTASH_CONF_D_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/conf.d/telegraf-hc-persister.conf.in .$(LOGSTASH_CONF_D_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/conf.d/telegraf-events-persister.conf.in .$(LOGSTASH_CONF_D_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/logstash.service ./etc/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/filebeat.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/logstash/auditbeat.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/opensearch-dashboards/opensearch-dashboards.service ./etc/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/opensearch-dashboards/export.ndjson .$(OSEARCH_BOARDS_CONF_DIR)
	$(Q)chroot $(ROOTDIR) chown -R logstash:logstash $(LOGSTASH_CONF_DIR) $(LOGSTASH_CONF_EVENTDB_DIR) $(LOGSTASH_LOG_DIR) $(LOGSTASH_LIB_DIR) $(LOGSTASH_HOME)
	$(Q)chroot $(ROOTDIR) chown opensearch-dashboards:opensearch-dashboards $(OSEARCH_BOARDS_LOG_DIR)

# install logstash plugins, such as output-syslog for N-Reporter
rootfs_install::
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) /usr/bin/env PATH=$(LOGSTASH_JDK)/bin:$$PATH LD_LIBRARY_PATH=$(LOGSTASH_JDK)/lib $(LOGSTASH_HOME)/bin/logstash-plugin install logstash-output-syslog logstash-output-opensearch
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# security patch
rootfs_install::
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)cd $(ROOTDIR)/usr/share/opensearch-dashboards/plugins/reportsDashboards && nvm install $(NODE_VERSION) && \
		nvm use $(NODE_VERSION) && \
		npm install -g yarn && \
		yarn add jspdf@4.0.0 && \
		rm -rf node_modules/.cache
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV
