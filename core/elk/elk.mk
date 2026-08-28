# Cube SDK
# elk installation (OpenSearch, OpenSearch-Dashboards, Logstash and Beats)

ifneq (,$(wildcard $(ROOTDIR)))
# Imported for its side effect: it is what lets `rpm -K` speak for the beats rpms, which
# arrive through ROOTFS_DNF_DL_FROM and install as @commandline. No repo file is added:
# since the initial commit the beats have always been direct rpm downloads, so nothing
# in the image has ever resolved a package from Elastic's yum repo.
ELK_KEY := $(shell chroot $(ROOTDIR) rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch 2>/dev/null ; echo "elastic")
OSEARCH := $(shell chroot $(ROOTDIR) rpm --import https://artifacts.opensearch.org/publickeys/opensearch-release.pgp ; echo "opensearch")
else
OSEARCH := $(shell echo "opensearch")
endif

#
# OpenSearch
#

OSEARCH_VER := 3.8.0
OSEARCH_CONF_DIR := /etc/$(OSEARCH)
OSEARCH_CONF_SECURITY_DIR := $(OSEARCH_CONF_DIR)/opensearch-security

ROOTFS_DNF_DL_FROM += https://artifacts.opensearch.org/releases/bundle/opensearch/$(OSEARCH_VER)/opensearch-$(OSEARCH_VER)-linux-x64.rpm
ROOTFS_PIP_NC += curator-$(OSEARCH)

rootfs_install::
	$(Q)chroot $(ROOTDIR) sh -c 'sed "s/\/var\/run\//\/run\//g" /usr/lib/tmpfiles.d/$(OSEARCH).conf > /etc/tmpfiles.d/$(OSEARCH).conf'
	$(Q)chroot $(ROOTDIR) systemctl disable $(OSEARCH)
	$(Q)cp -f $(ROOTDIR)$(OSEARCH_CONF_DIR)/$(OSEARCH).yml $(ROOTDIR)$(OSEARCH_CONF_DIR)/$(OSEARCH).yml.orig
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/opensearch/config.yml .$(OSEARCH_CONF_SECURITY_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/opensearch/roles.yml .$(OSEARCH_CONF_SECURITY_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/opensearch/roles_mapping.yml .$(OSEARCH_CONF_SECURITY_DIR)

#
# OpenSearch-Dashboards
#

OSEARCH_BOARDS_CONF_DIR := /etc/$(OSEARCH)-dashboards
OSEARCH_BOARDS_LOG_DIR := /var/log/$(OSEARCH)-dashboards
OSEARCH_BOARDS_HOME := /usr/share/$(OSEARCH)-dashboards

ROOTFS_DNF_DL_FROM += https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/$(OSEARCH_VER)/opensearch-dashboards-$(OSEARCH_VER)-linux-x64.rpm

rootfs_install::
	$(Q)chroot $(ROOTDIR) $(OSEARCH_BOARDS_HOME)/bin/opensearch-dashboards-plugin --allow-root remove securityDashboards
	$(Q)chroot $(ROOTDIR) mkdir -p $(OSEARCH_BOARDS_LOG_DIR)
	$(Q)cp -f $(ROOTDIR)$(OSEARCH_BOARDS_CONF_DIR)/opensearch_dashboards.yml $(ROOTDIR)$(OSEARCH_BOARDS_CONF_DIR)/opensearch_dashboards.yml.orig
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/opensearch-dashboards/opensearch-dashboards.service ./etc/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/opensearch-dashboards/export.ndjson .$(OSEARCH_BOARDS_CONF_DIR)
	$(Q)chroot $(ROOTDIR) chown opensearch-dashboards:opensearch-dashboards $(OSEARCH_BOARDS_LOG_DIR)

#
# Logstash
#

LOGSTASH_VER := 9.3.8
LOGSTASH_CONF_DIR := /etc/logstash
LOGSTASH_CONF_D_DIR := $(LOGSTASH_CONF_DIR)/conf.d
LOGSTASH_CONF_EVENTDB_DIR := $(LOGSTASH_CONF_DIR)/eventdb
LOGSTASH_HOME := /usr/share/logstash
LOGSTASH_LOG_DIR := /var/log/logstash
LOGSTASH_LIB_DIR := /var/lib/logstash
LOGSTASH_JDK := $(LOGSTASH_HOME)/jdk

LOGSTASH_TGZ := logstash-$(LOGSTASH_VER)-linux-x86_64.tar.gz
LOGSTASH_DL_URL := https://artifacts.elastic.co/downloads/logstash
# Elastic has signed every release with this key since 2013. Pinning the fingerprint is
# what makes the check worth anything: the key travels the same channel as the tarball,
# so accepting whatever key that channel hands back would verify nothing.
LOGSTASH_GPG_FPR := 46095ACC8548582C1A2699A9D27D666CD88E42B4
LOGSTASH_GNUPGHOME := $(ARCS_DIR)/logstash-gnupg

# Download to .part and only rename once the detached signature checks out, so neither a
# truncated object from a caching proxy nor a tampered one is ever left where the next
# run would extract it as a finished download.
$(ARCS_DIR)/$(LOGSTASH_TGZ):
	$(Q)wget $(LOGSTASH_DL_URL)/$(LOGSTASH_TGZ) -O $@.part
	$(Q)wget $(LOGSTASH_DL_URL)/$(LOGSTASH_TGZ).asc -O $@.asc
	$(Q)rm -rf $(LOGSTASH_GNUPGHOME) && mkdir -p -m 700 $(LOGSTASH_GNUPGHOME)
	$(Q)wget -qO- https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
		GNUPGHOME=$(LOGSTASH_GNUPGHOME) gpg --batch --quiet --import
	$(Q)GNUPGHOME=$(LOGSTASH_GNUPGHOME) gpg --batch --status-fd 1 --verify $@.asc $@.part | \
		grep -q '^\[GNUPG:\] VALIDSIG $(LOGSTASH_GPG_FPR) '
	$(Q)rm -rf $(LOGSTASH_GNUPGHOME) $@.asc
	$(Q)mv $@.part $@

rootfs_install:: $(ARCS_DIR)/$(LOGSTASH_TGZ)
	$(Q)tar xf $< -C $(ROOTDIR)/usr/share/
	$(Q)mv $(ROOTDIR)/usr/share/logstash-$(LOGSTASH_VER) $(ROOTDIR)$(LOGSTASH_HOME)
	$(Q)mv $(ROOTDIR)$(LOGSTASH_HOME)/config $(ROOTDIR)$(LOGSTASH_CONF_DIR)
	$(Q)chroot $(ROOTDIR) mkdir -p $(LOGSTASH_CONF_EVENTDB_DIR) $(LOGSTASH_LOG_DIR) $(LOGSTASH_LIB_DIR)
	$(Q)cp -f $(ROOTDIR)$(LOGSTASH_CONF_DIR)/logstash.yml $(ROOTDIR)$(LOGSTASH_CONF_DIR)/logstash.yml.orig
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
	$(Q)chroot $(ROOTDIR) chown -R logstash:logstash $(LOGSTASH_CONF_DIR) $(LOGSTASH_CONF_EVENTDB_DIR) $(LOGSTASH_LOG_DIR) $(LOGSTASH_LIB_DIR) $(LOGSTASH_HOME)

# install logstash plugins, such as output-syslog for N-Reporter
#
# Pinned, because logstash-plugin resolves these from rubygems at build time: unpinned,
# the image's plugin versions are whatever upstream published that morning, and neither
# the change nor the day it happened appears in this repo.
LOGSTASH_PLUGIN_ENV := PATH=$(LOGSTASH_JDK)/bin:$$PATH LD_LIBRARY_PATH=$(LOGSTASH_JDK)/lib LS_JAVA_OPTS="-Xmx2048M"
LOGSTASH_OUT_SYSLOG_VER := 3.1.0
LOGSTASH_OUT_OSEARCH_VER := 2.1.1

rootfs_install::
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) /usr/bin/env $(LOGSTASH_PLUGIN_ENV) $(LOGSTASH_HOME)/bin/logstash-plugin install --version $(LOGSTASH_OUT_SYSLOG_VER) logstash-output-syslog
	$(Q)chroot $(ROOTDIR) /usr/bin/env $(LOGSTASH_PLUGIN_ENV) $(LOGSTASH_HOME)/bin/logstash-plugin install --version $(LOGSTASH_OUT_OSEARCH_VER) logstash-output-opensearch
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

#
# Beats (filebeat, auditbeat)
#

BEATS_VER := 9.5.2

ROOTFS_DNF_DL_FROM += https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$(BEATS_VER)-x86_64.rpm
ROOTFS_DNF_DL_FROM += https://artifacts.elastic.co/downloads/beats/auditbeat/auditbeat-$(BEATS_VER)-x86_64.rpm

# No rootfs_install for the beats: their units come from the rpms. The copies this tree
# used to install over them were upstream's own files, one word of a Description apart,
# and a vendored unit only masks whatever upstream changes in it next.
