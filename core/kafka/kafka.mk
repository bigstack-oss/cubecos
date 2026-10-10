# Cube SDK
# zookeeper/kafka installation

KAFKA_BIN_DIR := /opt/kafka
KAFKA_APP_DIR := /var/lib/kafka
KAFKA_LOG_DIR := /var/log/kafka
KAFKA_RUN_DIR := /var/run/kafka

KAFKA_VER := 3.9.2
KAFKA_TGZ := kafka_2.13-$(KAFKA_VER).tgz
KAFKA_DL_URL := $(APACHE_DL_HOST)/dist/kafka/$(KAFKA_VER)
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

# Kafka 3.9 is the last line that runs on ZooKeeper and 3.9.2 is its last release; Kafka 4 needs
# KRaft, and ZooKeeper would have to stay anyway for octavia's jobboard (config_octavia.cpp). The
# jars 3.9.2 bundles for jackson 2.16.2, netty 4.1.125, zookeeper 3.8.4, jline 3.25.1, plexus-utils
# 3.5.1 and lz4-java 1.10.1 all have known vulnerabilities, and the 3.9 branch has not moved any of
# them. So each is swapped for a fixed release of the same artifact from Maven Central, within the
# line Kafka was built against -- jackson 2.x (all ten modules together, scala included), netty
# 4.1, zookeeper 3.8, lz4-java 1.x -- and pinned by sha256 like the logstash gems. Jetty stays at
# 9.4.57: fixes after 9.4.58 are not published openly, and ZooKeeper's admin server, the one Jetty
# user among the services that run here, is off (admin.enableServer=false in Kafka's shipped
# zookeeper.properties).
#
# <groupId>:<artifactId>:<version>:<sha256>:<the 3.9.2 jar it replaces>. The rm is not -f: a
# Kafka bump that no longer ships one of these jars fails here, which is the cue to revisit the list.
KAFKA_JAR_REFRESH := \
	com.fasterxml.jackson.core:jackson-annotations:2.18.11:9eab0d36da981645392427eedcb087e13be542488e37f935723dc0be50d18a53:jackson-annotations-2.16.2.jar \
	com.fasterxml.jackson.core:jackson-core:2.18.11:825fa72dfb9e2f8a642322f1390dbac22c30d15ebd6dc6b3772158821ee124eb:jackson-core-2.16.2.jar \
	com.fasterxml.jackson.core:jackson-databind:2.18.11:075ad94a76c3edf83e1972dc26f476361eb6b9d0e260d93fc11105509bc79cab:jackson-databind-2.16.2.jar \
	com.fasterxml.jackson.dataformat:jackson-dataformat-csv:2.18.11:fc8b46cce9ab081a8c0995c79bd58d8bf190c0897cc1a39b929002bd0d2a9c6a:jackson-dataformat-csv-2.16.2.jar \
	com.fasterxml.jackson.datatype:jackson-datatype-jdk8:2.18.11:efb0704bc8c9ff1eab7f1f8d0aabe3365d601b875b6dfc2a89ff750f9e0a8d2f:jackson-datatype-jdk8-2.16.2.jar \
	com.fasterxml.jackson.jaxrs:jackson-jaxrs-base:2.18.11:7ac14feba8c41f36d31c8e4f249de8a02971054a4dcc5c8529f9d0131bad2f4b:jackson-jaxrs-base-2.16.2.jar \
	com.fasterxml.jackson.jaxrs:jackson-jaxrs-json-provider:2.18.11:347118c93c9c9d202f71d635a9fc33bc822c65f2be7acd7c1309adfaf47e2697:jackson-jaxrs-json-provider-2.16.2.jar \
	com.fasterxml.jackson.module:jackson-module-afterburner:2.18.11:53b38d9ac2ba84a58005d6287a1d9a5e24db16658d055a7e5133be037e93b42d:jackson-module-afterburner-2.16.2.jar \
	com.fasterxml.jackson.module:jackson-module-jaxb-annotations:2.18.11:6ef536c210df2d5ba2ece053567702eee714a8543b36b1c3dcc430073b12d065:jackson-module-jaxb-annotations-2.16.2.jar \
	com.fasterxml.jackson.module:jackson-module-scala_2.13:2.18.11:703d0f2aacaf6f41527b8465da1ffcf41fe1f8d95a6f5def0f116b573407fb67:jackson-module-scala_2.13-2.16.2.jar \
	io.netty:netty-buffer:4.1.139.Final:48d805b74e56dc5f92b1f288858185abc86db16d293e8da183542df6243427f2:netty-buffer-4.1.125.Final.jar \
	io.netty:netty-codec:4.1.139.Final:ad43f07219dfb757a87b9c2b4765002be478c5401971379954e3d182f285fe6b:netty-codec-4.1.125.Final.jar \
	io.netty:netty-common:4.1.139.Final:50372d86e27b4b1cf0810d75eb534795966a199049a1e85a0c41bbd2bb97f519:netty-common-4.1.125.Final.jar \
	io.netty:netty-handler:4.1.139.Final:ff85f00781b956d618b20f33da076c839a5e43e0084108b07bab0c19737168ec:netty-handler-4.1.125.Final.jar \
	io.netty:netty-resolver:4.1.139.Final:562a5388c88325b7d6ed05e8168736871ce0e64ab01e0ce52ea7710760b9b457:netty-resolver-4.1.125.Final.jar \
	io.netty:netty-transport:4.1.139.Final:be7bff8b6274e7fae12bbad3c565777539e9b069517e0b3acc06d9ac2cd6ec05:netty-transport-4.1.125.Final.jar \
	io.netty:netty-transport-classes-epoll:4.1.139.Final:99ea06d67e3e2792cc93521b686223c78da2561bfdf98533ebb29fed1729cce4:netty-transport-classes-epoll-4.1.125.Final.jar \
	io.netty:netty-transport-native-epoll:4.1.139.Final:f094d849f39ad2a0ffe5c05867d464a2601657185cb795ff98d1e0d8135a1400:netty-transport-native-epoll-4.1.125.Final.jar \
	io.netty:netty-transport-native-unix-common:4.1.139.Final:8e660ac8a485fc8d8b47d87d04ea33d19902dc6fc5a113e9353b762188b3f333:netty-transport-native-unix-common-4.1.125.Final.jar \
	org.apache.zookeeper:zookeeper:3.8.7:fd12731eecb5d3ace48fa25f0141f011bcb13273b5dca301ff15d5409bd52a91:zookeeper-3.8.4.jar \
	org.apache.zookeeper:zookeeper-jute:3.8.7:a4980a3cd8fe0b4640326ccb4048556de66a34d0ed0c12a2380df7315de15b36:zookeeper-jute-3.8.4.jar \
	org.jline:jline:3.30.17:32ca18a3b5c742bc8a7b42af61ad9b3320dab525361b793ea9e3cb361e292c1d:jline-3.25.1.jar \
	org.codehaus.plexus:plexus-utils:3.6.1:05a63effd67e2d6b9d610cc82e2bd7473289d34802e57a529b28110f28af5679:plexus-utils-3.5.1.jar \
	at.yawk.lz4:lz4-java:1.11.4:58c8e0b813960d2a248e050c353baea73139b48a2ffc55382d42c69707e17325:lz4-java-1.10.1.jar
KAFKA_JAR_DIR := $(ARCS_DIR)/kafka-$(KAFKA_VER)-jars
kafka_jar_field = $(word $(1),$(subst :, ,$(2)))
KAFKA_JARS := $(foreach e,$(KAFKA_JAR_REFRESH),$(KAFKA_JAR_DIR)/$(call kafka_jar_field,2,$(e))-$(call kafka_jar_field,3,$(e)).jar)

# $(1) groupId, $(2) artifactId, $(3) version, $(4) sha256. .part then rename, as for the tarball.
define kafka_jar
$$(KAFKA_JAR_DIR)/$(2)-$(3).jar:
	$$(Q)mkdir -p $$(@D)
	$$(Q)wget $$(MAVEN_DL_HOST)/$(subst .,/,$(1))/$(2)/$(3)/$(2)-$(3).jar -O $$@.part
	$$(Q)echo "$(4)  $$@.part" | sha256sum -c -
	$$(Q)mv $$@.part $$@
endef
$(foreach e,$(KAFKA_JAR_REFRESH),$(eval $(call kafka_jar,$(call kafka_jar_field,1,$(e)),$(call kafka_jar_field,2,$(e)),$(call kafka_jar_field,3,$(e)),$(call kafka_jar_field,4,$(e)))))

rootfs_install:: $(KAFKA_JARS)
	$(Q)$(foreach e,$(KAFKA_JAR_REFRESH),rm $(ROOTDIR)$(KAFKA_BIN_DIR)/libs/$(call kafka_jar_field,5,$(e)) && ) true
	$(Q)cp -f $(KAFKA_JARS) $(ROOTDIR)$(KAFKA_BIN_DIR)/libs/

ZK_LOG_DIR := /var/log/zookeeper

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(ZK_LOG_DIR)
	$(Q)chroot $(ROOTDIR) chown zookeeper:zookeeper $(ZK_LOG_DIR)
