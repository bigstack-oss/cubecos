# Cube SDK
# Openstack + most heavy lifting installs (dnf/rpm, pip, git)
# Output is heavyfs.cgz which is dependent upon by rootfs

include ../../build.mk

PROJ_HEAVYFS_INSTALL := 1
HORIZON_APP_DIR := /usr/share/openstack-dashboard
HORIZON_DIR := $(HORIZON_APP_DIR)/openstack_dashboard
HORIZON_ETCDIR := /etc/openstack-dashboard
HORIZON_POLICY_DIR := $(HORIZON_ETCDIR)/default_policies
RPMS_DIR := $(CURDIR)/RPMS
PIPS_DIR := $(CURDIR)/PIPS
ARCS_DIR := $(CURDIR)/ARCS
HEAVYFS = $(CURDIR)/heavy_rootfs

OSP_SRCDIR := $(ROOTDIR)/usr/lib/python3.9/site-packages/
OSP_LOCAL_SRCDIR := $(ROOTDIR)/usr/local/lib/python3.9/site-packages/
OSP_PATCHDIR := $(SRCDIR)/$(OPENSTACK_RELEASE)_patch

BLKLST_DNF += iptables-legacy iptables-legacy-libs python3-django3 ceph-mgr-k8sevents

ALL = $(HEAVYFS)

# cube user & group accounts
rootfs_install::
	$(Q)cat $(SRCDIR)/account/$(HEX_DIST)/passwd > $(ROOTDIR)/etc/passwd
	$(Q)cat $(SRCDIR)/account/$(HEX_DIST)/shadow > $(ROOTDIR)/etc/shadow
	$(Q)cat $(SRCDIR)/account/$(HEX_DIST)/group > $(ROOTDIR)/etc/group
	$(Q)cat $(SRCDIR)/account/$(HEX_DIST)/gshadow > $(ROOTDIR)/etc/gshadow
	$(Q)(echo "Cube0s!"; sleep 1; echo "Cube0s!") | chroot $(ROOTDIR) /usr/bin/passwd hacluster >/dev/null 2>&1
	$(Q)cp -f $(ROOTDIR)/etc/passwd $(TOP_BLDDIR)/core/main/passwd.before
	$(Q)cp -f $(ROOTDIR)/etc/shadow $(TOP_BLDDIR)/core/main/shadow.before
	$(Q)cp -f $(ROOTDIR)/etc/group $(TOP_BLDDIR)/core/main/group.before
	$(Q)cp -f $(ROOTDIR)/etc/gshadow $(TOP_BLDDIR)/core/main/gshadow.before
	$(Q)mkdir -p $(ROOTDIR)/etc/rc.d/init.d
	$(Q)chroot $(ROOTDIR) ln -sf rc.d/init.d /etc/init.d

# Preparation of repos should be done first
rootfs_install::
	# $(Q)sed "s/\/var\/run\//\/run\//g" $(ROOTDIR)/usr/lib/tmpfiles.d/subscription-manager.conf > $(ROOTDIR)/etc/tmpfiles.d/subscription-manager.conf
	$(Q)chroot $(ROOTDIR) dnf clean all
	$(Q)echo "Add to $(ROOTDIR) repos: $(INFLUXDB_REPO) $(CEPH_REPO) $(PROMETHEUS_REPO) $(ELK_REPO) $(DOCKER_REPO)"
	$(Q)mkdir -p $(RPMS_DIR) $(PIPS_DIR) $(ARCS_DIR)

rootfs_install::
	$(Q)chroot $(ROOTDIR) dnf -y install centos-release-openstack-$(OPENSTACK_RELEASE)
	$(Q)chroot $(ROOTDIR) rpm -e centos-release-ceph-pacific --nodeps || true
	$(Q)chroot $(ROOTDIR) dnf -y install centos-release-ceph-quincy
	$(Q)chroot $(ROOTDIR) dnf config-manager --set-enabled highavailability

# ceph-nfs-ganesha repo needs to be installed before packages
rootfs_install::
	$(Q)chroot $(ROOTDIR) dnf -y install centos-release-nfs-ganesha5

# Lock kernel to known good version
rootfs_install::
	$(Q)chroot $(ROOTDIR) dnf install -y 'dnf-command(versionlock)'

LOCKED_DNF += kernel-lt-$(KERNEL_VERS) kernel-lt-core-$(KERNEL_VERS) kernel-lt-devel-$(KERNEL_VERS) kernel-lt-modules-$(KERNEL_VERS)
rootfs_install::
	$(Q)chroot $(ROOTDIR) dnf versionlock add $(LOCKED_DNF)

# FIrst try to download kernel-lt from elrepo mirror which has better availabilities
rootfs_install::
	$(Q)cp /etc/yum.repos.d/elrepo-kernel-mirror.repo $(ROOTDIR)/etc/yum.repos.d/

# Secondly try elrepo (where only latest versions can be found)
# rootfs_install::
# 	$(Q)chroot $(ROOTDIR) rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
# 	$(Q)chroot $(ROOTDIR) rpm --import https://www.elrepo.org/RPM-GPG-KEY-v2-elrepo.org
# 	$(Q)chroot $(ROOTDIR) dnf install -y https://www.elrepo.org/elrepo-release-9.el9.elrepo.noarch.rpm
# 	$(Q)chroot $(ROOTDIR) dnf config-manager --set-enabled elrepo-kernel

$(call PROJ_INSTALL_DNF_NOARCH,,$(LOCKED_DNF))

rootfs_install::
	$(Q)chroot $(ROOTDIR) dnf versionlock add $(LOCKED_DNF)

# python3-xmlsec
PYTHON3_SAML_REQUIRE := libxml2-devel xmlsec1-devel xmlsec1-openssl-devel libtool-ltdl-devel python-xmlsec

# DDoS-ed repo sites block IPs from offending source
rootfs_install::
	$(Q)[ ! -e $(ROOTDIR)/etc/yum.repos.d/elrepo.repo ] || sed -i 's/^mirrorlist=.*/#&/g' $(ROOTDIR)/etc/yum.repos.d/elrepo.repo

rootfs_install::
	$(Q)chroot $(ROOTDIR) dnf update -y systemd

# erlang 26.2.5-1.el9 doesn't work with rabbitmq
ERLANG_VER := 24.3.4.2-1.el9s
ERLANG += erlang-asn1-$(ERLANG_VER) erlang-compiler-$(ERLANG_VER) erlang-crypto-$(ERLANG_VER) erlang-eldap-$(ERLANG_VER) erlang-erts-$(ERLANG_VER) erlang-inets-$(ERLANG_VER) erlang-kernel-$(ERLANG_VER) erlang-mnesia-$(ERLANG_VER) erlang-os_mon-$(ERLANG_VER)
ERLANG += erlang-public_key-$(ERLANG_VER) erlang-runtime_tools-$(ERLANG_VER) erlang-sasl-$(ERLANG_VER) erlang-snmp-$(ERLANG_VER) erlang-ssl-$(ERLANG_VER) erlang-stdlib-$(ERLANG_VER) erlang-syntax_tools-$(ERLANG_VER) erlang-tools-$(ERLANG_VER) erlang-xmerl-$(ERLANG_VER)
LOCKED_DNF += $(ERLANG)
rootfs_install::
	$(Q)chroot $(ROOTDIR) dnf -y install $(ERLANG)

# ruby-3.1.2-141.module_el9+156+2e0939d1 has no i686 and conflicts with ruby-3.0.4-161.el9.i686.rpm
RUBY := ruby-3.0.4-161.el9
LOCKED_DNF += $(RUBY)

# python3-numpy-1:1.23.5-1.el9.x86_64 from @commandline and python3-numpy-1:1.20.1-5.el9.x86_64 from appstream
PYTHON3-NUMPY := python3-numpy-1:1.20.1-5.el9
PYTHON3-NUMPY-F2PY := python3-numpy-f2py-1:1.20.1-5.el9
LOCKED_DNF += $(PYTHON3-NUMPY-F2PY)

$(call PROJ_INSTALL_DNF_NOARCH,-w ,"curl wget jq tcpdump util-linux uuid git python3-devel gcc java-11-openjdk-headless $(RUBY) $(ROOTFS_DNF_NOARCH_P1) edk2-ovmf python3-pip python3-six python3-openstackclient python3-lasso sos emacs-nox expect $(PYTHON3_SAML_REQUIRE) perf arp-scan")

rootfs_install::
	$(Q)chroot $(ROOTDIR) python3 -m pip install -U pip
	$(Q)chroot $(ROOTDIR) dnf install -y liburing

# ceph dashboard sso needs python3-saml which complains LookupError: unknown encoding: cp437
rootfs_install::
	$(Q)wget https://raw.githubusercontent.com/python/cpython/main/Lib/encodings/cp437.py -P $(ROOTDIR)/usr/lib64/python3.9/encodings/

# install no constraint packages first
$(call PROJ_INSTALL_PIP_NC,,$(ROOTFS_PIP_NC))
$(call PROJ_INSTALL_PIP,-b "$(OPS_GITHUB_BRANCH)" -d "$(ROOTFS_PIP_DL_FROM)",$(ROOTFS_PIP))

# cannot install both python3-google-auth-1:2.28.0-1.el9.noarch from @commandline and python3-google-auth-1:1.30.0-1.el9s.noarch from centos-openstack-yoga
LOCKED_DNF += python3-google-auth-1.30.0-1.el9s

$(call PROJ_INSTALL_DNF_NOARCH,-d "$(ROOTFS_DNF_DL_FROM)","$(ROOTFS_DNF)")
# $(call PROJ_INSTALL_DNF_NOARCH,-n,"$(ROOTFS_DNF_NS)")

# Allow admin to be sudoers
rootfs_install::
	$(Q)mkdir -p $(ROOTDIR)/etc/sudoers.d
	$(Q)echo "admin ALL=(root) NOPASSWD: ALL" > $(ROOTDIR)/etc/sudoers.d/admin

# Default systemd service stop timeout
rootfs_install::
	$(Q)sed -i 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=90s/' $(ROOTDIR)/etc/systemd/system.conf
	$(Q)sed -i 's/#DefaultTimeoutStartSec.*/DefaultTimeoutStartSec=300s/' $(ROOTDIR)/etc/systemd/system.conf
	# $(Q)find  $(ROOTDIR)/usr/lib/systemd/system/ -type f | grep -v crpytsetup.slice | xargs sed -i "s/^TimeoutStopSec.*//"
	$(Q)chroot $(ROOTDIR) systemctl mask systemd-journal-flush

# Disable USB storage drivers
rootfs_install::
	$(Q)echo "blacklist uas" >> $(ROOTDIR)/etc/modprobe.d/usb.conf
	$(Q)echo "blacklist usb_storage" >> $(ROOTDIR)/etc/modprobe.d/usb.conf
	$(Q)echo "install usb_storage /bin/true" >> $(ROOTDIR)/etc/modprobe.d/usb.conf

# note: install skyline pkgs first since it doesn't follow yoga constraint
HEAVY_COMPONENTS += api ui skyline nginx
HEAVY_COMPONENTS += webapp mysql mongodb ntp rabbitmq memcache etcd ceph pacemaker haproxy grafana
HEAVY_COMPONENTS += influxdb prometheus kapacitor elk telegraf kafka keystone glance nova ironic neutron cinder swift
HEAVY_COMPONENTS += heat horizon octavia barbican manila designate masakari monasca senlin watcher cyborg
HEAVY_COMPONENTS += terraform docker k3s keycloak rancher appfw nvidia

include $(shell for m in $(HEAVY_COMPONENTS); do ls $(COREDIR)/$$m/$$m.mk; done)
$(shell for r in $(LOCKED_DNF); do echo $$r >> $(LOCKED_RPMS); done)
$(shell for r in $(BLKLST_DNF); do echo $$r >> $(BLKLST_RPMS); done)

ifneq ($(RC),)
heavyfs_install::
	$(Q)cp -f /etc/resolv.conf $(HEAVYFS)/etc/resolv.conf
	$(Q)cp -f $(ROOTDIR)/etc/passwd $(TOP_BLDDIR)/core/main/passwd.before
	$(Q)cp -f $(ROOTDIR)/etc/shadow $(TOP_BLDDIR)/core/main/shadow.before
	$(Q)cp -f $(ROOTDIR)/etc/group $(TOP_BLDDIR)/core/main/group.before
	$(Q)cp -f $(ROOTDIR)/etc/gshadow $(TOP_BLDDIR)/core/main/gshadow.before

rootfs.cgz:
	$(Q)rm -f *.pkg
	$(Q)mount -o ro $(PROJ_NFS_SERVER):$(PROJ_NFS_CUBECOS_PATH)/$(FW_VER) /mnt
	$(Q)cp -f $$(ls -1 /mnt/$(RC)/CUBE/*.pkg | grep -v "_[0-9][.]pkg") ./
	$(Q)umount /mnt
	$(Q)mkdir -p pkg
	$(Q)mount *.pkg pkg
	$(Q)mv -f pkg/$@ $@
	$(Q)umount pkg
	$(Q)rmdir pkg

$(HEAVYFS): rootfs.cgz $(shell for m in $(HEAVY_COMPONENTS); do find $(COREDIR)/$$m -type f -name '*.mk' -o -name Makefile; done)
	$(call RUN_CMD_TIMED, $(SHELL) $(HEX_SCRIPTSDIR)/mountrootfs -s -D '$(MAKECMD) ROOTDIR=@ROOTDIR@ PROJ_BUILD_LABEL="heavyfs" heavyfs_install' $< $@, "  GEN     $@") || mv -f $@ /tmp/
	$(Q)cp -f /etc/resolv.conf $@/etc/resolv.conf
else
$(HEAVYFS): $(HEX_FULL_ROOTFS) $(shell for m in $(HEAVY_COMPONENTS); do find $(COREDIR)/$$m -type f -name '*.mk' -o -name Makefile; done)
	$(call RUN_CMD_TIMED, $(SHELL) $(HEX_SCRIPTSDIR)/mountrootfs -s -D '$(MAKECMD) ROOTFS_DNF_NOARCH_P1="$(ROOTFS_DNF_NOARCH_P1)" ROOTFS_DNF_DL_FROM="$(ROOTFS_DNF_DL_FROM)" ROOTFS_DNF="$(addsuffix .x86_64,$(ROOTFS_DNF)) $(ROOTFS_DNF_NOARCH)" ROOTFS_PIP="$(ROOTFS_PIP)" ROOTFS_PIP_NC="$(ROOTFS_PIP_NC)" ROOTFS_PIP_DL_FROM="$(ROOTFS_PIP_DL_FROM)" ROOTDIR=@ROOTDIR@ PROJ_BUILD_LABEL="heavyfs" rootfs_install' $< $@, "  GEN     $@") || mv -f $@ /tmp/
endif

rootfs_install::
	$(Q)[ -d $(OSP_PATCHDIR) ] && cp -rf $(OSP_PATCHDIR)/* $(OSP_SRCDIR)/ || /bin/true
	$(Q)[ -d $(OSP_PATCHDIR) ] && cp -rf $(OSP_PATCHDIR)/* $(OSP_LOCAL_SRCDIR)/ || /bin/true

# /var/update should work irrespective of a functioning cephfs mount
rootfs_install::
	$(Q)chroot $(ROOTDIR) sh -c "mkdir -p /mnt/cephfs/update"
	$(Q)chroot $(ROOTDIR) sh -c "rm -rf /var/update ; ln -sf /mnt/cephfs/update /var/update"

PKGCLEAN += $(HEAVYFS) $(RPMS_DIR) $(PIPS_DIR) $(ARCS_DIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
