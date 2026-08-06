# Cube SDK
# Openstack + most heavy lifting installs (dnf/rpm, pip, git)
# Output is heavyfs.cgz which is dependent upon by rootfs

include ../../build.mk

PROJ_HEAVYFS_INSTALL := 1
RPMS_DIR := $(CURDIR)/RPMS
PIPS_DIR := $(CURDIR)/PIPS
ARCS_DIR := $(CURDIR)/ARCS
HEAVYFS = $(CURDIR)/heavy_rootfs

OSP_SRCDIR := $(ROOTDIR)/usr/lib/python3.9/site-packages/
OSP_LOCAL_SRCDIR := $(ROOTDIR)/usr/local/lib/python3.9/site-packages/
OSP_PATCHDIR := $(SRCDIR)/$(OPENSTACK_RELEASE)_patch

ROOTFS_PIP += numpy
BLKLST_DNF += iptables-legacy iptables-legacy-libs python3-django3 ceph-mgr-k8sevents
BLKLST_DNF += python3-PyMySQL   # CVE-2024-36039 Upgrade to version: 1.1.1
BLKLST_DNF += python3-django    # CVE-2022-28347, CVE-2023-31047, CVE-2025-64459 CVE-2023-46695, CVE-2023-43665, CVE-2022-36359 Upgrade to version: 3.2.23
ROOTFS_PIP += python-jose       # CVE-2024-33663 Upgrade to version: 3.4.0
BLKLST_DNF += python3-monascaclient # Remove DNF managed package
BLKLST_DNF += python3-scciclient # CVE-2022-2996
ROOTFS_PIP += python-scciclient # CVE-2022-2996 Upgrade to version: 0.12.0
BLKLST_DNF += python3-pillow    # CVE-2023-50447
ROOTFS_PIP += pillow            # CVE-2023-50447 Upgrade to version: 10.2.0
ROOTFS_PIP += waitress          # CVE-2024-49768 Upgrade to version: 3.0.1
BLKLST_DNF += python3-numexpr   # Remove DNF managed package
ROOTFS_PIP += numexpr           # CVE-2023-39631 Upgrade to version: 2.8.5
BLKLST_DNF += ansible ansible-core # CVE-2025-58367 Remove DNF managed package

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

# cube configs
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos

# cube static data
rootfs_install::
	$(Q)mkdir -p $(ROOTDIR)/usr/share/cube
	$(Q)mkdir -p $(ROOTDIR)/usr/share/cube/cos
	$(Q)cp -f $(TOP_SRCDIR)/LICENSE $(ROOTDIR)/usr/share/cube/cos/

# Preparation of repos should be done first
rootfs_install::
	# $(Q)sed "s/\/var\/run\//\/run\//g" $(ROOTDIR)/usr/lib/tmpfiles.d/subscription-manager.conf > $(ROOTDIR)/etc/tmpfiles.d/subscription-manager.conf
	$(Q)mount -t proc proc $(ROOTDIR)/proc || /bin/true
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
	$(Q)chroot $(ROOTDIR) sed \
		-i '/\[centos-nfs-ganesha-5-source\]/,/^$$/ {s|^baseurl=.*|baseurl=https://mirror.stream.centos.org/SIGs/9-stream/storage/source/nfsganesha-5/|}' \
		/etc/yum.repos.d/CentOS-NFS-Ganesha-5.repo

# Disable module mariadb from CentOS Stream 9 - AppStream repo to avoid dependency conflicts after switching to MariaDB official repo
rootfs_install::
	$(Q)chroot $(ROOTDIR) dnf module disable mariadb -y

# Lock kernel to known good version
rootfs_install::
	$(Q)chroot $(ROOTDIR) dnf install -y 'dnf-command(versionlock)'

# elrepo
rootfs_install::
	$(Q)cp /etc/yum.repos.d/elrepo.repo $(ROOTDIR)/etc/yum.repos.d/

# DDoS-ed repo sites block IPs from offending source
rootfs_install::
	$(Q)[ ! -e $(ROOTDIR)/etc/yum.repos.d/elrepo.repo ] || sed -i 's/^mirrorlist=.*/#&/g' $(ROOTDIR)/etc/yum.repos.d/elrepo.repo

KERNEL_PKGS := kernel-$(KERNEL_VERS) kernel-core-$(KERNEL_VERS) kernel-devel-$(KERNEL_VERS) kernel-modules-$(KERNEL_VERS)
rootfs_install::
	$(Q)cp -r /kernel-$(KERNEL_VERS) $(ROOTDIR)/
	$(Q)for k in $(KERNEL_PKGS) ; do chroot $(ROOTDIR) rpm -i --nodeps /kernel-$(KERNEL_VERS)/$$k.rpm ; done
	$(Q)chroot $(ROOTDIR) dnf versionlock add $(KERNEL_PKGS)
	$(Q)rm -rf $(ROOTDIR)/kernel-$(KERNEL_VERS)

# qemu-kvm-17:9.1.0-27.el9 is not compatible with 17:9.1.0-20 (v3.0.0)
# Pinned NVR: live-migration-compatible with 3.1.0's qemu. Never unpin -- an
# unpinned build floats to build-day c9s. Rig validation + drift: cubecos#1150.
QEMU_VER := -17:10.1.0-22.el9
# Filename NVR (no epoch); kojihub keeps builds the c9s mirror rotates away, so an
# air-gapped rebuild resolves the exact NVR (same pattern as mysql.mk).
QEMU_NVR := 10.1.0-22.el9
QEMU_URL := https://kojihub.stream.centos.org/kojifiles/packages/qemu-kvm/10.1.0/22.el9/x86_64
QEMU_PKGS := qemu-kvm qemu-kvm-device-display-virtio-gpu-pci qemu-kvm-device-display-virtio-gpu
QEMU_PKGS += qemu-kvm-device-display-virtio-vga qemu-kvm-device-usb-redirect qemu-kvm-device-usb-host
QEMU_PKGS += qemu-guest-agent qemu-kvm-block-rbd qemu-kvm-block-blkio qemu-kvm-common qemu-kvm-core
QEMU_PKGS += qemu-img qemu-kvm-audio-pa qemu-pr-helper qemu-kvm-tools qemu-kvm-ui-egl-headless
QEMU_PKGS += qemu-kvm-ui-opengl qemu-kvm-docs
QEMU_LOCKED_RPMS := $(foreach p,$(QEMU_PKGS),$(p)$(QEMU_VER))
LOCKED_DNF += $(QEMU_LOCKED_RPMS)
$(foreach p,$(QEMU_PKGS),$(eval ROOTFS_DNF_DL_FROM += $(QEMU_URL)/$(p)-$(QEMU_NVR).x86_64.rpm))

$(call PROJ_INSTALL_DNF_NOARCH,,$(LOCKED_DNF))

rootfs_install::
	$(Q)chroot $(ROOTDIR) dnf update -y systemd

# python3-xmlsec
PYTHON3_SAML_REQUIRE := libxml2-devel xmlsec1-devel xmlsec1-openssl-devel libtool-ltdl-devel python-xmlsec

# ruby-3.1.2-141.module_el9+156+2e0939d1 has no i686 and conflicts with ruby-3.0.4-161.el9.i686.rpm
RUBY := ruby-3.0.7-166.el9
LOCKED_DNF += $(RUBY)

OPENSSL_VER := 3.5.1-6.el9
OPENSSL += openssl-$(OPENSSL_VER) openssl-devel-$(OPENSSL_VER) openssl-libs-$(OPENSSL_VER)
LOCKED_DNF += $(OPENSSL)

# python3-numpy-1:1.23.5-1.el9.x86_64 from @commandline and python3-numpy-1:1.20.1-5.el9.x86_64 from appstream
# PYTHON3-NUMPY := python3-numpy-1:1.20.1-5.el9
# PYTHON3-NUMPY-F2PY := python3-numpy-f2py-1:1.20.1-5.el9
# LOCKED_DNF += $(PYTHON3-NUMPY-F2PY)

$(call PROJ_INSTALL_DNF_NOARCH,-w ,"curl wget jq tcpdump util-linux uuid git python3-devel gcc java-11-openjdk-headless $(RUBY) $(ROOTFS_DNF_NOARCH_P1) edk2-ovmf python3-pip python3-six python3-openstackclient python3-lasso sos emacs-nox expect tcl $(PYTHON3_SAML_REQUIRE) perf arp-scan")

rootfs_install::
	$(Q)chroot $(ROOTDIR) python3 -m pip install -U pip
	$(Q)chroot $(ROOTDIR) dnf install -y liburing

# ceph dashboard sso needs python3-saml which complains LookupError: unknown encoding: cp437
rootfs_install::
	$(Q)wget https://raw.githubusercontent.com/python/cpython/main/Lib/encodings/cp437.py -P $(ROOTDIR)/usr/lib64/python3.9/encodings/

# cannot install both python3-google-auth-1:2.28.0-1.el9.noarch from @commandline and python3-google-auth-1:1.30.0-1.el9s.noarch from centos-openstack-yoga
LOCKED_DNF += python3-google-auth-1.30.0-1.el9s

$(call PROJ_INSTALL_DNF_NOARCH,-d "$(ROOTFS_DNF_DL_FROM)","$(ROOTFS_DNF)")
# $(call PROJ_INSTALL_DNF_NOARCH,-n,"$(ROOTFS_DNF_NS)")

# install no constraint packages first
$(call PROJ_INSTALL_PIP_NC,,$(ROOTFS_PIP_NC))
$(call PROJ_INSTALL_PIP,-b "$(OPS_GITHUB_BRANCH)" -d "$(ROOTFS_PIP_DL_FROM)",$(ROOTFS_PIP))

# install python 3.10 for openstack antelope
rootfs_install::
	$(Q)# we need to mount /dev into the chroot environment because building cpython would write to /dev/null, a character device
	$(Q)mount -o bind /dev $(ROOTDIR)/dev || true
	$(Q)chroot $(ROOTDIR) dnf -y install git pkg-config
	$(Q)chroot $(ROOTDIR) dnf -y install dnf-plugins-core
	$(Q)chroot $(ROOTDIR) dnf -y builddep python3
	$(Q)chroot $(ROOTDIR) mkdir -p /usr/src/python-3.10
	$(Q)chroot $(ROOTDIR) wget -O /usr/src/python-3.10/Python-3.10.20.tgz https://www.python.org/ftp/python/3.10.20/Python-3.10.20.tgz
	$(Q)chroot $(ROOTDIR) tar -xvzf /usr/src/python-3.10/Python-3.10.20.tgz -C /usr/src/python-3.10
	$(Q)chroot $(ROOTDIR) bash -c "cd /usr/src/python-3.10/Python-3.10.20 && ./configure --enable-optimizations"
	$(Q)chroot $(ROOTDIR) bash -c "cd /usr/src/python-3.10/Python-3.10.20 && make altinstall"
	$(Q)umount -l $(ROOTDIR)/dev || true
	$(Q)# ensure python 3.10 is successfully built
	$(Q)chroot $(ROOTDIR) [ -f /usr/local/bin/python3.10 ]
	$(Q)chroot $(ROOTDIR) [ -f /usr/local/bin/pip3.10 ]

# install python 3.11 for openstack caracal
rootfs_install::
	$(Q)# we need to mount /dev into the chroot environment because building cpython would write to /dev/null, a character device
	$(Q)mount -o bind /dev $(ROOTDIR)/dev || true
	$(Q)chroot $(ROOTDIR) dnf -y install git pkg-config
	$(Q)chroot $(ROOTDIR) dnf -y install dnf-plugins-core
	$(Q)chroot $(ROOTDIR) dnf -y builddep python3
	$(Q)chroot $(ROOTDIR) mkdir -p /usr/src/python-$(CARACAL_PYTHON_VER)
	$(Q)chroot $(ROOTDIR) wget -O /usr/src/python-$(CARACAL_PYTHON_VER)/Python-$(CARACAL_PYTHON_PATCH_VER).tgz https://www.python.org/ftp/python/$(CARACAL_PYTHON_PATCH_VER)/Python-$(CARACAL_PYTHON_PATCH_VER).tgz
	$(Q)chroot $(ROOTDIR) tar -xvzf /usr/src/python-$(CARACAL_PYTHON_VER)/Python-$(CARACAL_PYTHON_PATCH_VER).tgz -C /usr/src/python-$(CARACAL_PYTHON_VER)
	$(Q)chroot $(ROOTDIR) bash -c "cd /usr/src/python-$(CARACAL_PYTHON_VER)/Python-$(CARACAL_PYTHON_PATCH_VER) && ./configure --enable-optimizations"
	$(Q)chroot $(ROOTDIR) bash -c "cd /usr/src/python-$(CARACAL_PYTHON_VER)/Python-$(CARACAL_PYTHON_PATCH_VER) && make altinstall"
	$(Q)umount -l $(ROOTDIR)/dev || true
	$(Q)# ensure python 3.11 is successfully built
	$(Q)chroot $(ROOTDIR) [ -f /usr/local/bin/python$(CARACAL_PYTHON_VER) ]
	$(Q)chroot $(ROOTDIR) [ -f /usr/local/bin/pip$(CARACAL_PYTHON_VER) ]

# set up the execution context for openstack antelope
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p /opt/openstack-antelope
	$(Q)chroot $(ROOTDIR) python3.10 -m venv /opt/openstack-antelope
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && pip install --upgrade pip setuptools"
	$(Q)cp -f $(NEXT_OPENSTACK_PIP_CONSTRAINT) $(ROOTDIR)/opt/openstack-antelope/
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) wheel

# NOTE: setuptools in this venv is pinned to 65.7.0 by the constraints file -- the
# version antelope's own upper-constraints names -- because setuptools 82 deleted
# pkg_resources and the 2023-era services still import it (see cubecos#607/#1080).
#
# That pin does *not* reach pip's PEP-517 build environments. pip builds every sdist
# in a throwaway overlay and resolves the default backend requirement
# "setuptools>=40.8.0" against the live index, so an sdist gets whatever setuptools
# exists today (83.0.0 at the time of writing) no matter what -c says. Verified: with
# PIP_CONSTRAINT set as well, the overlay still installs 83.0.0.
#
# The consequence, for anything installing horizon: nine of its dependencies are
# sdist-only, and seven of those are XStatic packages whose setup.py imports a
# pkg_resources-declared namespace, so they die in the overlay with
# "ModuleNotFoundError: No module named 'pkg_resources'". The fix is
# --no-build-isolation, which builds against this venv's own 65.7.0 instead. It is
# spelled out on each pip install that needs it rather than turned on venv-wide,
# because the requirement is not universal -- mysqlclient 2.2.8 is the counter-example
# and needs a setuptools *newer* than 65.7.0, so it keeps the default isolation.
#
# One ordering caveat: with --no-build-isolation an XStatic sdist can only be built
# while no other XStatic package is installed yet, or the installed pkg_resources
# namespace shadows the source tree and setup.py fails with "cannot import name ...
# from 'xstatic.pkg' (unknown location)". A single pip invocation is fine -- pip
# builds every sdist before installing any of them.

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
HEAVY_COMPONENTS += nvidia
HEAVY_COMPONENTS += yq api ui skyline nginx
HEAVY_COMPONENTS += mysql mongodb ntp rabbitmq memcache etcd ceph pacemaker haproxy grafana
HEAVY_COMPONENTS += influxdb prometheus kapacitor elk telegraf kafka keystone glance nova ironic neutron cinder swift multipath
# note: horizon goes last so its collectstatic/compress sees the dashboard plugins
# that designate, masakari and watcher drop into local/enabled at install time.
# RPM-installed plugins (heat, octavia, ironic, manila) land theirs in the dnf
# phase and are collected either way; the source-installed ones are not.
HEAVY_COMPONENTS += heat octavia barbican manila designate masakari monasca watcher cyborg horizon
HEAVY_COMPONENTS += terraform docker k3s keycloak rancher appfw appctl lachesis

include $(shell for m in $(HEAVY_COMPONENTS); do ls $(COREDIR)/$$m/$$m.mk; done)
$(shell for r in $(LOCKED_DNF); do echo $$r >> $(LOCKED_RPMS); done)
$(shell for r in $(BLKLST_DNF); do echo $$r >> $(BLKLST_RPMS); done)

# Component artifacts baked into the rootfs — prereqs so a component rebuild
# forces a rootfs rebuild (with touch $@ below). Scoped to HEAVY_COMPONENTS, not
# core/main (circular). Not covered: remote dnf/pip + bare-binary/dir deliverables.
HEAVY_DELIVERABLES := $(wildcard $(foreach m,$(HEAVY_COMPONENTS),$(TOP_BLDDIR)/core/$(m)/*.rpm $(TOP_BLDDIR)/core/$(m)/*.tgz))

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

$(HEAVYFS): rootfs.cgz $(HEAVY_DELIVERABLES) $(shell for m in $(HEAVY_COMPONENTS); do find $(COREDIR)/$$m -type f -name '*.mk' -o -name Makefile; done)
	$(call RUN_CMD_TIMED, $(SHELL) $(HEX_SCRIPTSDIR)/mountrootfs -s -D '$(MAKECMD) ROOTDIR=@ROOTDIR@ PROJ_BUILD_LABEL="heavyfs" heavyfs_install' $< $@, "  GEN     $@")
	$(Q)cp -f /etc/resolv.conf $@/etc/resolv.conf
	$(Q)touch $@
else
$(HEAVYFS): $(HEX_FULL_ROOTFS) $(HEAVY_DELIVERABLES) $(shell for m in $(HEAVY_COMPONENTS); do find $(COREDIR)/$$m -type f -name '*.mk' -o -name Makefile; done)
	$(call RUN_CMD_TIMED, $(SHELL) $(HEX_SCRIPTSDIR)/mountrootfs -s -D '$(MAKECMD) ROOTFS_DNF_NOARCH_P1="$(ROOTFS_DNF_NOARCH_P1)" ROOTFS_DNF_DL_FROM="$(ROOTFS_DNF_DL_FROM)" ROOTFS_DNF="$(addsuffix .x86_64,$(ROOTFS_DNF)) $(ROOTFS_DNF_NOARCH)" ROOTFS_PIP="$(ROOTFS_PIP)" ROOTFS_PIP_NC="$(ROOTFS_PIP_NC)" ROOTFS_PIP_DL_FROM="$(ROOTFS_PIP_DL_FROM)" ROOTDIR=@ROOTDIR@ PROJ_BUILD_LABEL="heavyfs" rootfs_install' $< $@, "  GEN     $@")
	$(Q)touch $@
endif

rootfs_install::
	$(Q)[ -d $(OSP_PATCHDIR) ] && cp -rf $(OSP_PATCHDIR)/* $(OSP_SRCDIR)/ || /bin/true
	$(Q)[ -d $(OSP_PATCHDIR) ] && cp -rf $(OSP_PATCHDIR)/* $(OSP_LOCAL_SRCDIR)/ || /bin/true

# /var/update should work irrespective of a functioning cephfs mount
rootfs_install::
	$(Q)umount $(ROOTDIR)/proc || /bin/true
	$(Q)chroot $(ROOTDIR) sh -c "mkdir -p /mnt/cephfs/update"
	$(Q)chroot $(ROOTDIR) sh -c "rm -rf /var/update ; ln -sf /mnt/cephfs/update /var/update"

PKGCLEAN += $(HEAVYFS) $(RPMS_DIR) $(PIPS_DIR) $(ARCS_DIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
