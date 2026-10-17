# Cube SDK
# rabbitmq installation

ROOTFS_DNF += logrotate

# rabbitmq-server 3.12 declares "erlang >= 25.0" and "erlang < 27.0" itself, so
# 25 would still run it; 26 is taken now because 3.13, the next rung, runs on
# nothing older. 3.11 declares "erlang < 26.0", so erlang 26 cannot be rolled
# out ahead of the broker the way 25 was for 3.11 - the two move together.
# modern-erlang keeps two 26.x builds next to the 27s 3.12 refuses, so pin the
# later one
ERLANG_VER := 26.2.5.15-1.el9
LOCKED_DNF += erlang-$(ERLANG_VER)

# rabbitmq refuses to skip minor versions on upgrade, so 3.12 is the only step
# reachable from 3.11 - pin it against the 3.13/4.x the repo also serves.
# 3.12.14 is the last release of the 3.12 series
RABBITMQ_VER := 3.12.14-1.el8
LOCKED_DNF += rabbitmq-server-$(RABBITMQ_VER)

# install erlang
rootfs_install::
	$(Q)# primary RabbitMQ signing key
	$(Q)chroot $(ROOTDIR) rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/rabbitmq-release-signing-key.asc'
	$(Q)# modern Erlang repository
	$(Q)chroot $(ROOTDIR) rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key'
	$(Q)cp -f $(COREDIR)/rabbitmq/erlang.repo $(ROOTDIR)/etc/yum.repos.d/
	$(Q)chroot $(ROOTDIR) dnf install -y erlang-$(ERLANG_VER).x86_64

# install rabbitmq
rootfs_install::
	$(Q)chroot $(ROOTDIR) rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key'
	$(Q)cp -f $(COREDIR)/rabbitmq/rabbitmq.repo $(ROOTDIR)/etc/yum.repos.d/
	$(Q)chroot $(ROOTDIR) dnf install -y rabbitmq-server-$(RABBITMQ_VER).noarch

# cowboy and cowlib, the HTTP server behind the management, prometheus, web-stomp and web-mqtt
# plugins, are swapped for the releases RabbitMQ 4.2 pins. 3.12.14 bundles cowboy 2.12.0 and cowlib
# 2.13.0, which have known vulnerabilities fixed in cowboy 2.15.0 and cowlib 2.16.1, and no 3.x
# release moves them (3.13 bundles the same). They are compiled from their hex.pm packages, pinned
# by hex's own sha256, with the image's erlc, so the beams match the OTP that loads them; the
# packages carry their finished .app files, and HTTP/3 (quicer) stays compiled out, as hex builds
# them. cowboy 2.17 takes the bundled ranch 2.1.0 (it asks for >= 1.8.0 and < 3.0.0). Each entry is
# <package>:<version>:<sha256>:<version it replaces>, cowlib first, since cowboy compiles against
# it. The rm is not -f: a RabbitMQ that no longer bundles the old one fails here, which is the cue
# to revisit the list.
RABBITMQ_PLUGINS := /usr/lib/rabbitmq/lib/rabbitmq_server-$(firstword $(subst -, ,$(RABBITMQ_VER)))/plugins
RABBITMQ_HEX_SWAP := \
	cowlib:2.18.0:c4f89d33a61162d4cfdcb5a1af7e562d80a700b2573cc71020ce6521b152dc1a:2.13.0 \
	cowboy:2.17.0:84f0e4c9d5820342cd506472052b79336d0d9d3624e46303f6d0af9dc94e8d5f:2.12.0
RABBITMQ_HEX_DIR := $(ARCS_DIR)/hex
rabbitmq_hex_field = $(word $(1),$(subst :, ,$(2)))
rabbitmq_hex_tar = $(RABBITMQ_HEX_DIR)/$(call rabbitmq_hex_field,1,$(1))-$(call rabbitmq_hex_field,2,$(1)).tar

# $(1) package, $(2) version, $(3) sha256. .part then rename, as for the jars.
define rabbitmq_hex
$$(RABBITMQ_HEX_DIR)/$(1)-$(2).tar:
	$$(Q)mkdir -p $$(@D)
	$$(Q)wget $$(HEX_DL_HOST)/tarballs/$(1)-$(2).tar -O $$@.part
	$$(Q)echo "$(3)  $$@.part" | sha256sum -c -
	$$(Q)mv $$@.part $$@
endef
$(foreach e,$(RABBITMQ_HEX_SWAP),$(eval $(call rabbitmq_hex,$(call rabbitmq_hex_field,1,$(e)),$(call rabbitmq_hex_field,2,$(e)),$(call rabbitmq_hex_field,3,$(e)))))

# Behaviour modules compile first, quietly, since some implement others; the full pass that follows
# then checks every module against them, with the bundled ranch and the new cowlib on the path.
rabbitmq_hex_install = n=$(call rabbitmq_hex_field,1,$(1))-$(call rabbitmq_hex_field,2,$(1)) && \
	rm -rf $(ROOTDIR)/tmp/hex-$$n && mkdir -p $(ROOTDIR)/tmp/hex-$$n/ebin && \
	tar -xOf $(call rabbitmq_hex_tar,$(1)) contents.tar.gz | tar -xz -C $(ROOTDIR)/tmp/hex-$$n && \
	chroot $(ROOTDIR) sh -c "cd /tmp/hex-$$n && \
		O='-o ebin -pa ebin -I include -pa $(RABBITMQ_PLUGINS)/cowlib-*/ebin -pa $(RABBITMQ_PLUGINS)/ranch-*/ebin +debug_info +deterministic' && \
		grep -l '^-callback' src/*.erl | xargs -r erlc -W0 \$$O && erlc \$$O src/*.erl" && \
	rm -r $(ROOTDIR)$(RABBITMQ_PLUGINS)/$(call rabbitmq_hex_field,1,$(1))-$(call rabbitmq_hex_field,4,$(1)) && \
	mkdir $(ROOTDIR)$(RABBITMQ_PLUGINS)/$$n && \
	cp -r $(ROOTDIR)/tmp/hex-$$n/ebin $$(ls -d $(ROOTDIR)/tmp/hex-$$n/include 2>/dev/null) $(ROOTDIR)$(RABBITMQ_PLUGINS)/$$n/ && \
	rm -rf $(ROOTDIR)/tmp/hex-$$n

rootfs_install:: $(foreach e,$(RABBITMQ_HEX_SWAP),$(call rabbitmq_hex_tar,$(e)))
	$(Q)$(foreach e,$(RABBITMQ_HEX_SWAP),$(call rabbitmq_hex_install,$(e)) && ) true

rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/rabbitmq/epmd@.socket ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/rabbitmq/epmd@.service ./lib/systemd/system
	$(Q)# listen from sockets.target on: any erl that runs before the socket does --
	$(Q)# rpm scriptlets and health checks call rabbitmqctl -- finds 4369 closed,
	$(Q)# spawns its own `epmd -daemon`, and the socket then cannot bind
	$(Q)chroot $(ROOTDIR) systemctl enable epmd@0.0.0.0.socket
	$(Q)chroot $(ROOTDIR) sh -c 'sed "s/\/var\/run\//\/run\//g" /usr/lib/tmpfiles.d/rabbitmq-server.conf > /etc/tmpfiles.d/rabbitmq-server.conf'
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/systemd/system/rabbitmq-server.service.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/rabbitmq/rabbitmq-server-overrides.conf ./etc/systemd/system/rabbitmq-server.service.d/
