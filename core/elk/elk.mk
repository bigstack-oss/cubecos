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

OSEARCH_VER := 3.9.0
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
	$(Q)# customImportMapDashboards adds custom map layers and styles. The shipped saved
	$(Q)# objects (export.ndjson) are an index pattern and a saved search, with no map in them.
	$(Q)chroot $(ROOTDIR) $(OSEARCH_BOARDS_HOME)/bin/opensearch-dashboards-plugin --allow-root remove customImportMapDashboards
	$(Q)chroot $(ROOTDIR) mkdir -p $(OSEARCH_BOARDS_LOG_DIR)
	$(Q)cp -f $(ROOTDIR)$(OSEARCH_BOARDS_CONF_DIR)/opensearch_dashboards.yml $(ROOTDIR)$(OSEARCH_BOARDS_CONF_DIR)/opensearch_dashboards.yml.orig
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/opensearch-dashboards/opensearch-dashboards.service ./etc/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/opensearch-dashboards/export.ndjson .$(OSEARCH_BOARDS_CONF_DIR)
	$(Q)chroot $(ROOTDIR) chown opensearch-dashboards:opensearch-dashboards $(OSEARCH_BOARDS_LOG_DIR)

#
# Logstash
#

LOGSTASH_VER := 9.5.5
LOGSTASH_CONF_DIR := /etc/logstash
LOGSTASH_CONF_D_DIR := $(LOGSTASH_CONF_DIR)/conf.d
LOGSTASH_CONF_EVENTDB_DIR := $(LOGSTASH_CONF_DIR)/eventdb
LOGSTASH_HOME := /usr/share/logstash
LOGSTASH_LOG_DIR := /var/log/logstash
LOGSTASH_LIB_DIR := /var/lib/logstash
LOGSTASH_JDK := $(LOGSTASH_HOME)/jdk

LOGSTASH_TGZ := logstash-$(LOGSTASH_VER)-linux-x86_64.tar.gz
LOGSTASH_DL_URL := $(ELASTIC_DL_HOST)/downloads/logstash
# Elastic has signed every release with this key since 2013. Pinning the fingerprint is
# what makes the check worth anything: the key travels the same channel as the tarball,
# so accepting whatever key that channel hands back would verify nothing.
LOGSTASH_GPG_FPR := 46095ACC8548582C1A2699A9D27D666CD88E42B4

# Checked with gpgv against a throwaway keyring rather than `gpg --verify` against a
# homedir: gpg wants gpg-agent even to read a public keyring, and the agent does not
# reliably start under mountrootfs -- it failed a build in one jail while the same command
# worked by hand in the same container. gpgv needs no agent, no homedir and no keyring
# mutation, which is what it exists for.
#
# Download to .part and only rename once the detached signature checks out, so neither a
# truncated object from a caching proxy nor a tampered one is ever left where the next
# run would extract it as a finished download.
$(ARCS_DIR)/$(LOGSTASH_TGZ):
	$(Q)wget $(LOGSTASH_DL_URL)/$(LOGSTASH_TGZ) -O $@.part
	$(Q)wget $(LOGSTASH_DL_URL)/$(LOGSTASH_TGZ).asc -O $@.asc
	$(Q)wget -qO- https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor > $@.gpg
	$(Q)gpgv --keyring $@.gpg --status-fd 1 $@.asc $@.part | \
		grep -q '^\[GNUPG:\] VALIDSIG $(LOGSTASH_GPG_FPR) '
	$(Q)rm -f $@.asc $@.gpg
	$(Q)mv $@.part $@

rootfs_install:: $(ARCS_DIR)/$(LOGSTASH_TGZ)
	$(Q)tar xf $< -C $(ROOTDIR)/usr/share/
	$(Q)mv $(ROOTDIR)/usr/share/logstash-$(LOGSTASH_VER) $(ROOTDIR)$(LOGSTASH_HOME)
	$(Q)mv $(ROOTDIR)$(LOGSTASH_HOME)/config $(ROOTDIR)$(LOGSTASH_CONF_DIR)
	$(Q)chroot $(ROOTDIR) mkdir -p $(LOGSTASH_CONF_EVENTDB_DIR) $(LOGSTASH_LOG_DIR) $(LOGSTASH_LIB_DIR)
	$(Q)cp -f $(ROOTDIR)$(LOGSTASH_CONF_DIR)/logstash.yml $(ROOTDIR)$(LOGSTASH_CONF_DIR)/logstash.yml.orig
	$(Q)cp -f $(ROOTDIR)$(LOGSTASH_CONF_DIR)/log4j2.properties $(ROOTDIR)$(LOGSTASH_CONF_DIR)/log4j2.properties.orig
	$(Q)cat $(COREDIR)/elk/logstash/log4j2-cube.properties >> $(ROOTDIR)$(LOGSTASH_CONF_DIR)/log4j2.properties
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
# From a pack assembled here out of pinned .gem files, not by name. By name, logstash-plugin
# resolves against rubygems.org's whole-ecosystem index -- ~50 MB, fetched cold on every build
# because heavy_base starts empty -- to install 163 KB of gems, over a path measured at 43 KB/s
# from the build network: 15 minutes on a good day, and builds have sat silent in it for 44 and
# 56 minutes without any of bundler's timeouts firing (#1730). A file:// pack is resolved locally
# only, against Logstash's own Gemfile.lock (lib/pluginmanager/bundler/logstash_injector.rb),
# which already carries every runtime dependency of both plugins; it writes the same lockfile the
# online install did. If a bump ever needs a gem that lock lacks, the install stops within
# seconds naming it -- pin that gem the same way and add it under logstash/dependencies/.
#
# Pinned by digest as well as by version: nothing here checks a signature on a .gem, and these
# are the digests rubygems.org publishes for the two releases.
LOGSTASH_PLUGIN_ENV := PATH=$(LOGSTASH_JDK)/bin:$$PATH LD_LIBRARY_PATH=$(LOGSTASH_JDK)/lib LS_JAVA_OPTS="-Xmx2048M"
LOGSTASH_OUT_SYSLOG_VER := 3.1.0
LOGSTASH_OUT_SYSLOG_GEM := logstash-output-syslog-$(LOGSTASH_OUT_SYSLOG_VER).gem
LOGSTASH_OUT_SYSLOG_SHA256 := 6f8a6ab355178b43b254c2358352d83c9dc996261343725906f46d1351b9dc44
LOGSTASH_OUT_OSEARCH_VER := 2.1.1
LOGSTASH_OUT_OSEARCH_GEM := logstash-output-opensearch-$(LOGSTASH_OUT_OSEARCH_VER)-java.gem
LOGSTASH_OUT_OSEARCH_SHA256 := 6e247b92ef07bb738275115f2aa28282f10a9abb9ce1f7c5f12acd54884ffa97
LOGSTASH_PLUGIN_PACK := logstash-plugins-$(LOGSTASH_VER)-$(LOGSTASH_OUT_SYSLOG_VER)-$(LOGSTASH_OUT_OSEARCH_VER).zip
LOGSTASH_GEM_DL_URL := $(RUBYGEMS_DL_HOST)/downloads

# .part then rename, as for the tarball above, so a truncated or swapped gem is never zipped.
$(ARCS_DIR)/$(LOGSTASH_OUT_SYSLOG_GEM):
	$(Q)wget $(LOGSTASH_GEM_DL_URL)/$(LOGSTASH_OUT_SYSLOG_GEM) -O $@.part
	$(Q)echo "$(LOGSTASH_OUT_SYSLOG_SHA256)  $@.part" | sha256sum -c -
	$(Q)mv $@.part $@

$(ARCS_DIR)/$(LOGSTASH_OUT_OSEARCH_GEM):
	$(Q)wget $(LOGSTASH_GEM_DL_URL)/$(LOGSTASH_OUT_OSEARCH_GEM) -O $@.part
	$(Q)echo "$(LOGSTASH_OUT_OSEARCH_SHA256)  $@.part" | sha256sum -c -
	$(Q)mv $@.part $@

# The layout lib/pluginmanager/pack_installer/pack.rb reads: plugins directly under logstash/.
$(ARCS_DIR)/$(LOGSTASH_PLUGIN_PACK): $(ARCS_DIR)/$(LOGSTASH_OUT_SYSLOG_GEM) $(ARCS_DIR)/$(LOGSTASH_OUT_OSEARCH_GEM)
	$(Q)rm -rf $@.d $@.part
	$(Q)mkdir -p $@.d/logstash
	$(Q)cp $^ $@.d/logstash/
	$(Q)cd $@.d && zip -q -X -r $@.part logstash
	$(Q)rm -rf $@.d
	$(Q)mv $@.part $@

rootfs_install:: $(ARCS_DIR)/$(LOGSTASH_PLUGIN_PACK)
	$(Q)cp -f $< $(ROOTDIR)/tmp/$(LOGSTASH_PLUGIN_PACK)
	$(Q)chroot $(ROOTDIR) /usr/bin/env $(LOGSTASH_PLUGIN_ENV) $(LOGSTASH_HOME)/bin/logstash-plugin install file:///tmp/$(LOGSTASH_PLUGIN_PACK)
	$(Q)rm -f $(ROOTDIR)/tmp/$(LOGSTASH_PLUGIN_PACK)

# Bundled plugins no pipeline in conf.d uses, removed because they carry vulnerable jars:
# elastic_integration vendors jackson 2.18 and 3.1, azure_event_hubs jackson 2.21.6. The
# removal is local -- logstash-plugin rewrites Gemfile and Gemfile.lock and deletes the gems
# without resolving anything against rubygems.org -- so it costs seconds and no network. A
# Logstash bump that stops bundling one fails here, which is the cue to drop it from the list.
LOGSTASH_UNUSED_PLUGINS := logstash-filter-elastic_integration logstash-input-azure_event_hubs

rootfs_install::
	$(Q)chroot $(ROOTDIR) /usr/bin/env $(LOGSTASH_PLUGIN_ENV) $(LOGSTASH_HOME)/bin/logstash-plugin remove $(LOGSTASH_UNUSED_PLUGINS)

#
# Beats (filebeat, auditbeat)
#

BEATS_VER := 9.5.2

ROOTFS_DNF_DL_FROM += https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$(BEATS_VER)-x86_64.rpm
ROOTFS_DNF_DL_FROM += https://artifacts.elastic.co/downloads/beats/auditbeat/auditbeat-$(BEATS_VER)-x86_64.rpm

# No rootfs_install for the beats: their units come from the rpms. The copies this tree
# used to install over them were upstream's own files, one word of a Description apart,
# and a vendored unit only masks whatever upstream changes in it next.
