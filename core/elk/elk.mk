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

ROOTFS_DNF_DL_FROM += https://artifacts.opensearch.org/releases/bundle/opensearch/$(OSEARCH_VER)/opensearch-$(OSEARCH_VER)-linux-x64.rpm

rootfs_install::
	$(Q)chroot $(ROOTDIR) sh -c 'sed "s/\/var\/run\//\/run\//g" /usr/lib/tmpfiles.d/$(OSEARCH).conf > /etc/tmpfiles.d/$(OSEARCH).conf'
	$(Q)chroot $(ROOTDIR) systemctl disable $(OSEARCH)
	$(Q)cp -f $(ROOTDIR)$(OSEARCH_CONF_DIR)/$(OSEARCH).yml $(ROOTDIR)$(OSEARCH_CONF_DIR)/$(OSEARCH).yml.orig
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/systemd/system/$(OSEARCH).service.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/opensearch/opensearch-start-timeout.conf ./etc/systemd/system/$(OSEARCH).service.d/

# Bundled plugins that carry vulnerable jars and that nothing here uses. No code in this tree,
# cube-cos-api, cube-cos-ui or lachesis calls a _plugins API, and on live nodes their system
# indices hold only what the plugins write for themselves at startup -- no monitor, detector,
# model, notebook, report or channel. security goes with them: config_opensearch has always
# run it disabled. opensearch-plugin removes one plugin per call and refuses one that another
# still extends, so dependents come first: skills extends ml, security-analytics extends
# alerting, notifications extends notifications-core. ingest-geoip is a module, which
# opensearch-plugin will not remove, and no ingest pipeline exists to use it.
OSEARCH_UNUSED_PLUGINS := opensearch-skills opensearch-ml opensearch-security-analytics \
	opensearch-alerting opensearch-notifications opensearch-notifications-core \
	opensearch-anomaly-detection opensearch-flow-framework opensearch-neural-search \
	opensearch-observability opensearch-performance-analyzer opensearch-reports-scheduler \
	opensearch-search-relevance opensearch-sql opensearch-ubi opensearch-security
OSEARCH_PLUGIN_CLI = chroot $(ROOTDIR) env OPENSEARCH_JAVA_HOME=/usr/share/$(OSEARCH)/jdk /usr/share/$(OSEARCH)/bin/opensearch-plugin

rootfs_install::
	$(Q)$(foreach p,$(OSEARCH_UNUSED_PLUGINS),$(OSEARCH_PLUGIN_CLI) remove $(p) && ) true
	$(Q)rm -rf $(ROOTDIR)/usr/share/$(OSEARCH)/modules/ingest-geoip

# Jars swapped for fixed releases of the same artifacts from Maven Central, pinned by sha256, the
# way core/kafka/kafka.mk refreshes Kafka's. Each entry is <groupId>:<artifactId>:<version>:<sha256>
# followed by what it replaces.
ELK_JAR_DIR := $(ARCS_DIR)/elk-jars
elk_jar_field = $(word $(1),$(subst :, ,$(2)))
elk_jar_path = $(ELK_JAR_DIR)/$(call elk_jar_field,2,$(1))-$(call elk_jar_field,3,$(1)).jar

# $(1) groupId, $(2) artifactId, $(3) version, $(4) sha256. .part then rename, as for the tarballs.
define elk_jar
$$(ELK_JAR_DIR)/$(2)-$(3).jar:
	$$(Q)mkdir -p $$(@D)
	$$(Q)wget $$(MAVEN_DL_HOST)/$(subst .,/,$(1))/$(2)/$(3)/$(2)-$(3).jar -O $$@.part
	$$(Q)echo "$(4)  $$@.part" | sha256sum -c -
	$$(Q)mv $$@.part $$@
endef
elk_jar_rule = $(eval $(call elk_jar,$(call elk_jar_field,1,$(1)),$(call elk_jar_field,2,$(1)),$(call elk_jar_field,3,$(1)),$(call elk_jar_field,4,$(1))))

# Guava has a known vulnerability fixed in 33.7.2, and failureaccess 1.0.3 is what 33.7.2 requires.
# logstash-core, logstash-integration-kafka and OpenSearch's transport-grpc module each bundle an
# older pair, and none has a release that bundles 33.7.2 yet, so all three take this pair below.
# Their download rules are defined here, once.
ELK_GUAVA := com.google.guava:guava:33.7.2-jre:b530942257fb935f8b2cfaa5f8eb5bd59c555fd8e8d01b8ce98912e077ea606c
ELK_FAILUREACCESS := com.google.guava:failureaccess:1.0.3:cbfc3906b19b8f55dd7cfd6dfe0aa4532e834250d7f080bd8d211a3e246b59cb
ELK_GUAVA_JARS := $(call elk_jar_path,$(ELK_GUAVA)) $(call elk_jar_path,$(ELK_FAILUREACCESS))
$(foreach e,$(ELK_GUAVA) $(ELK_FAILUREACCESS),$(call elk_jar_rule,$(e)))

# OpenSearch 3.9.0, the newest release, ships Jackson 3.2.2 in lib/, and jackson-core 3.2.2 has a
# known vulnerability fixed in 3.2.3. The four Jackson jars there move to 3.2.3 together. The last
# field is the jar replaced. The rm is not -f: an OpenSearch bump that no longer ships one of them
# fails here, which is the cue to revisit the list.
OSEARCH_JAR_REFRESH := \
	tools.jackson.core:jackson-core:3.2.3:a0c17e7e665a5e95c82f5fb45c0fec2ae3dc556c80f0016452c9c84cd23f3817:jackson-core-3.2.2.jar \
	tools.jackson.dataformat:jackson-dataformat-cbor:3.2.3:b7e4e671e2f2ceab70b75119d59d527b89e039c1a8c21eac6267a1a8ecf637be:jackson-dataformat-cbor-3.2.2.jar \
	tools.jackson.dataformat:jackson-dataformat-smile:3.2.3:acb78b50561181a4811da09702cf96f7f5dd0e15d06b085a547eee9ec0d6f742:jackson-dataformat-smile-3.2.2.jar \
	tools.jackson.dataformat:jackson-dataformat-yaml:3.2.3:260dd15f1a044dc00cbefd6f01198403fe45ff4ae5fc37895a7842cab6c583d0:jackson-dataformat-yaml-3.2.2.jar
OSEARCH_JARS := $(foreach e,$(OSEARCH_JAR_REFRESH),$(call elk_jar_path,$(e)))
$(foreach e,$(OSEARCH_JAR_REFRESH),$(call elk_jar_rule,$(e)))

rootfs_install:: $(OSEARCH_JARS)
	$(Q)$(foreach e,$(OSEARCH_JAR_REFRESH),rm $(ROOTDIR)/usr/share/$(OSEARCH)/lib/$(call elk_jar_field,5,$(e)) && ) true
	$(Q)cp -f $(OSEARCH_JARS) $(ROOTDIR)/usr/share/$(OSEARCH)/lib/

# The transport-grpc module, which opensearch-knn extends, bundles Guava 33.2.1 and failureaccess
# 1.0.2 in its own directory and loads them in its own classloader; 3.9.0 is the newest release and
# main still bundles 33.2.1. The rm is not -f, as above.
OSEARCH_GRPC_DIR := /usr/share/$(OSEARCH)/modules/transport-grpc

rootfs_install:: $(ELK_GUAVA_JARS)
	$(Q)rm $(ROOTDIR)$(OSEARCH_GRPC_DIR)/guava-33.2.1-jre.jar $(ROOTDIR)$(OSEARCH_GRPC_DIR)/failureaccess-1.0.2.jar
	$(Q)cp -f $(ELK_GUAVA_JARS) $(ROOTDIR)$(OSEARCH_GRPC_DIR)/

#
# OpenSearch-Dashboards
#

OSEARCH_BOARDS_CONF_DIR := /etc/$(OSEARCH)-dashboards
OSEARCH_BOARDS_LOG_DIR := /var/log/$(OSEARCH)-dashboards
OSEARCH_BOARDS_HOME := /usr/share/$(OSEARCH)-dashboards

ROOTFS_DNF_DL_FROM += https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/$(OSEARCH_VER)/opensearch-dashboards-$(OSEARCH_VER)-linux-x64.rpm

# Apps that only drive the OpenSearch plugins OSEARCH_UNUSED_PLUGINS removes, so left in
# place they would be pages that fail on every request. investigationDashboards has no
# plugin of its own but calls ml, ppl/sql and observability's notebooks. indexManagementDashboards
# and queryInsightsDashboards go too, though their plugins stay: the scanner finds vulnerable
# packages in each one's yarn.lock, and nothing uses either -- no ISM policy exists, and no code
# here calls them.
OSEARCH_BOARDS_UNUSED_APPS := alertingDashboards anomalyDetectionDashboards assistantDashboards \
	flowFrameworkDashboards investigationDashboards mlCommonsDashboards notificationsDashboards \
	observabilityDashboards queryWorkbenchDashboards reportsDashboards searchRelevanceDashboards \
	securityAnalyticsDashboards indexManagementDashboards queryInsightsDashboards

rootfs_install::
	$(Q)chroot $(ROOTDIR) $(OSEARCH_BOARDS_HOME)/bin/opensearch-dashboards-plugin --allow-root remove securityDashboards
	$(Q)# customImportMapDashboards adds custom map layers and styles. The shipped saved
	$(Q)# objects (export.ndjson) are an index pattern and a saved search, with no map in them.
	$(Q)chroot $(ROOTDIR) $(OSEARCH_BOARDS_HOME)/bin/opensearch-dashboards-plugin --allow-root remove customImportMapDashboards
	$(Q)$(foreach a,$(OSEARCH_BOARDS_UNUSED_APPS),chroot $(ROOTDIR) $(OSEARCH_BOARDS_HOME)/bin/opensearch-dashboards-plugin --allow-root remove $(a) && ) true
	$(Q)# @elastic/eui ships its own repository's GitHub Actions workflows inside the npm package,
	$(Q)# and the scanner flags an action one of them uses. Nothing in the image can run a workflow.
	$(Q)rm -r $(ROOTDIR)$(OSEARCH_BOARDS_HOME)/node_modules/@elastic/eui/.github
	$(Q)chroot $(ROOTDIR) mkdir -p $(OSEARCH_BOARDS_LOG_DIR)
	$(Q)cp -f $(ROOTDIR)$(OSEARCH_BOARDS_CONF_DIR)/opensearch_dashboards.yml $(ROOTDIR)$(OSEARCH_BOARDS_CONF_DIR)/opensearch_dashboards.yml.orig
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/opensearch-dashboards/opensearch-dashboards.service ./etc/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/elk/opensearch-dashboards/export.ndjson .$(OSEARCH_BOARDS_CONF_DIR)
	$(Q)chroot $(ROOTDIR) chown opensearch-dashboards:opensearch-dashboards $(OSEARCH_BOARDS_LOG_DIR)

# Dashboards runs on the Node it bundles under node/, and 3.9.0 bundles 22.23.0, whose known
# vulnerabilities are fixed in 22.23.2. That directory is the official linux-x64 build's layout,
# so it is replaced with the newest release of the same 22 line from nodejs.org, pinned by sha256
# as nodejs.org's SHASUMS256.txt lists it. --no-same-owner keeps the tarball's build uid out of
# the image. Drop this once a Dashboards release bundles a Node at least this new.
OSEARCH_BOARDS_NODE_VER := 22.23.3
OSEARCH_BOARDS_NODE_TXZ := node-v$(OSEARCH_BOARDS_NODE_VER)-linux-x64.tar.xz
OSEARCH_BOARDS_NODE_SHA256 := df450af89261115ef9f9e3830c3eeb2cc9213b63c720b1af623cb5dcbe2e02de

$(ARCS_DIR)/$(OSEARCH_BOARDS_NODE_TXZ):
	$(Q)wget $(NODEJS_DL_HOST)/dist/v$(OSEARCH_BOARDS_NODE_VER)/$(OSEARCH_BOARDS_NODE_TXZ) -O $@.part
	$(Q)echo "$(OSEARCH_BOARDS_NODE_SHA256)  $@.part" | sha256sum -c -
	$(Q)mv $@.part $@

rootfs_install:: $(ARCS_DIR)/$(OSEARCH_BOARDS_NODE_TXZ)
	$(Q)rm -rf $(ROOTDIR)$(OSEARCH_BOARDS_HOME)/node
	$(Q)mkdir -p $(ROOTDIR)$(OSEARCH_BOARDS_HOME)/node
	$(Q)tar -xJf $< -C $(ROOTDIR)$(OSEARCH_BOARDS_HOME)/node --strip-components 1 --no-same-owner

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

# logstash-integration-kafka, which the conf.d pipelines read Kafka with, vendors Jackson 2.21.6, and
# jackson-core 2.21.6 has a known vulnerability fixed in 2.21.7; 12.1.10, its newest release, still
# vendors 2.21.6. logstash-core loads 2.21.7 already, so jar-dependencies skips the gem's own
# jackson-core and jackson-databind, but it does load the gem's jackson-dataformat-csv and
# jackson-datatype-jdk8 2.21.6. All four move to 2.21.7 and the gem's jar list names 2.21.7, so the
# plugin runs on the one Jackson line logstash-core loads. The gem's lz4-java 1.10.1, which the
# Kafka client compresses with, has a known vulnerability fixed in 1.11.4 and moves the same way, and
# so do its Guava 32.0.1 and failureaccess 1.0.1, which only its Avro schema-registry client needs:
# they take the pair defined above, whose download rules are not defined again here.
# The last field is the version replaced. Nothing here is -f: a Logstash bump that changes the
# gem's version, or what it vendors, fails here.
LOGSTASH_KAFKA_GEM := $(LOGSTASH_HOME)/vendor/bundle/jruby/3.4.0/gems/logstash-integration-kafka-12.1.9-java
LOGSTASH_KAFKA_JAR_REFRESH := \
	com.fasterxml.jackson.core:jackson-core:2.21.7:8c5623b98f32d5f7e1287ff61ed50e08ab7b11381e991fff89327faabba42261:2.21.6 \
	com.fasterxml.jackson.core:jackson-databind:2.21.7:1290c2795e93e8a6861a6c4d9ff0d844d32f5ea178362cb2721edf5561e828b1:2.21.6 \
	com.fasterxml.jackson.dataformat:jackson-dataformat-csv:2.21.7:588050148497158cabdc05c0ae3a7e123194a486b8c62745778fc6239f9b085e:2.21.6 \
	com.fasterxml.jackson.datatype:jackson-datatype-jdk8:2.21.7:b8f62f98363ed9aa259b3a479a64fcbe7e081158a8bec6733972e900d12f4e47:2.21.6 \
	at.yawk.lz4:lz4-java:1.11.4:58c8e0b813960d2a248e050c353baea73139b48a2ffc55382d42c69707e17325:1.10.1 \
	$(ELK_GUAVA):32.0.1-jre \
	$(ELK_FAILUREACCESS):1.0.1
LOGSTASH_KAFKA_JARS_RB = $(ROOTDIR)$(LOGSTASH_KAFKA_GEM)/lib/logstash-integration-kafka_jars.rb
# $(1) one LOGSTASH_KAFKA_JAR_REFRESH entry: swap the jar in the gem's vendor/jar-dependencies tree
# and the version its jar list requires.
logstash_kafka_jar = d=$(ROOTDIR)$(LOGSTASH_KAFKA_GEM)/vendor/jar-dependencies/$(subst .,/,$(call elk_jar_field,1,$(1)))/$(call elk_jar_field,2,$(1)) && \
	rm $$d/$(call elk_jar_field,5,$(1))/$(call elk_jar_field,2,$(1))-$(call elk_jar_field,5,$(1)).jar && \
	rmdir $$d/$(call elk_jar_field,5,$(1)) && mkdir $$d/$(call elk_jar_field,3,$(1)) && \
	cp $(call elk_jar_path,$(1)) $$d/$(call elk_jar_field,3,$(1))/ && \
	grep -q "'$(call elk_jar_field,2,$(1))', '$(call elk_jar_field,5,$(1))'" $(LOGSTASH_KAFKA_JARS_RB) && \
	sed -i "s/'$(call elk_jar_field,2,$(1))', '$(call elk_jar_field,5,$(1))'/'$(call elk_jar_field,2,$(1))', '$(call elk_jar_field,3,$(1))'/" $(LOGSTASH_KAFKA_JARS_RB)

$(foreach e,$(filter-out $(ELK_GUAVA):% $(ELK_FAILUREACCESS):%,$(LOGSTASH_KAFKA_JAR_REFRESH)),$(call elk_jar_rule,$(e)))

rootfs_install:: $(foreach e,$(LOGSTASH_KAFKA_JAR_REFRESH),$(call elk_jar_path,$(e)))
	$(Q)$(foreach e,$(LOGSTASH_KAFKA_JAR_REFRESH),$(call logstash_kafka_jar,$(e)) && ) true
	$(Q)chroot $(ROOTDIR) chown -R logstash:logstash $(LOGSTASH_KAFKA_GEM)

# logstash-core bundles Guava 33.1.0 and failureaccess 1.0.2 in lib/jars, which bin/logstash.lib.sh
# puts on the class path by glob, so no list names them; 9.5.5 is the newest release and main still
# pins 33.1.0. They take the pair defined above. Nothing here is -f, as above.
LOGSTASH_CORE_JARS := $(LOGSTASH_HOME)/logstash-core/lib/jars

rootfs_install:: $(ELK_GUAVA_JARS)
	$(Q)rm $(ROOTDIR)$(LOGSTASH_CORE_JARS)/guava-33.1.0-jre.jar $(ROOTDIR)$(LOGSTASH_CORE_JARS)/failureaccess-1.0.2.jar
	$(Q)cp -f $(ELK_GUAVA_JARS) $(ROOTDIR)$(LOGSTASH_CORE_JARS)/
	$(Q)chroot $(ROOTDIR) chown logstash:logstash $(LOGSTASH_CORE_JARS)/guava-33.7.2-jre.jar $(LOGSTASH_CORE_JARS)/failureaccess-1.0.3.jar

#
# Beats (filebeat, auditbeat)
#

BEATS_VER := 9.5.5

ROOTFS_DNF_DL_FROM += https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$(BEATS_VER)-x86_64.rpm
ROOTFS_DNF_DL_FROM += https://artifacts.elastic.co/downloads/beats/auditbeat/auditbeat-$(BEATS_VER)-x86_64.rpm

# filebeat and auditbeat are rebuilt from the same tag and installed over the rpms' binaries:
# Elastic's 9.5.5 is built with go1.26.8, older than the October 2026 security release
# (1.27.2 / 1.26.9), and links an x/net older than its fix; the jail's Go and BEATS_GO_GET cover
# both. These are the OSS beats, not x-pack: config_logstash uses filebeat's filestream input with
# the kafka output and auditbeat's file_integrity module, all OSS, so none of the Elastic-licensed
# code is needed. The rpms stay for everything else and name the version in the SBOM. Return to
# their binaries on the condition core/exporters/Makefile gives.
BEATS_GO_GET := golang.org/x/crypto@v0.58.0 golang.org/x/net@v0.61.0 golang.org/x/text@v0.43.0
BEATS_GO_DIR := $(ARCS_DIR)/beats-go
BEATS_SRC := $(BEATS_GO_DIR)/beats-$(BEATS_VER)-src
BEATS_VERSION_PKG := github.com/elastic/beats/v7/libbeat/version

# The tag is cloned shallow, and the modules come from proxy.golang.org, checked against
# sum.golang.org.
$(BEATS_SRC):
	$(call RUN_CMD_TIMED, rm -rf $@.part && \
		git clone -q --depth 1 -b v$(BEATS_VER) https://github.com/elastic/beats.git $@.part && \
		mv $@.part $@,"  CLONE   beats-$(BEATS_VER)")

$(BEATS_GO_DIR)/beats.built: $(BEATS_SRC) $(COREDIR)/elk/elk.mk
	$(Q)mkdir -p $(BEATS_GO_DIR)/bin
	$(call RUN_CMD_TIMED, cd $< && go get $(BEATS_GO_GET) && go mod tidy && \
		for c in filebeat auditbeat ; do \
			CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X $(BEATS_VERSION_PKG).commit=$$(git rev-parse HEAD)" \
				-o $(BEATS_GO_DIR)/bin/$$c ./$$c || exit 1 ; \
		done,"  BUILD   beats-$(BEATS_VER)")
	$(Q)touch $@

rootfs_install:: $(BEATS_GO_DIR)/beats.built
	$(Q)install -m 0755 $(BEATS_GO_DIR)/bin/filebeat $(ROOTDIR)/usr/share/filebeat/bin/filebeat
	$(Q)install -m 0755 $(BEATS_GO_DIR)/bin/auditbeat $(ROOTDIR)/usr/share/auditbeat/bin/auditbeat

# No rootfs_install for the beats' units: they come from the rpms. The copies this tree
# used to install over them were upstream's own files, one word of a Description apart,
# and a vendored unit only masks whatever upstream changes in it next.
