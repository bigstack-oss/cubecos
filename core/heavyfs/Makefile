# Cube SDK
# Openstack + most heavy lifting installs (dnf/rpm, pip, git)
# Output is heavyfs.cgz which is dependent upon by rootfs

include ../../build.mk

PROJ_HEAVYFS_INSTALL := 1
RPMS_DIR := $(CURDIR)/RPMS
PIPS_DIR := $(CURDIR)/PIPS
ARCS_DIR := $(CURDIR)/ARCS
HEAVYFS = $(CURDIR)/heavy_rootfs

# NOTE: this used to define OSP_SRCDIR, OSP_LOCAL_SRCDIR and OSP_PATCHDIR and copy
# $(OPENSTACK_RELEASE)_patch over both python 3.9 site-packages trees. The tree held
# two backports, and upstream has since absorbed both -- oslo_log's
# _fix_eventlet_logging (eventlet#432) is in oslo.log 5.2.1, and pyroute2 0.7.3
# already resolves RTM_DELLINK to flags_req, RTM_DELNEIGH to flags_base, and carries
# no NLM_F_EXCL in flush_addr/flush_rules at all. Both targets were python 3.9
# copies, which no openstack service has used since the antelope migration, so the
# patches applied to an interpreter that no longer runs the code they fixed.

ROOTFS_PIP += numpy
BLKLST_DNF += iptables-legacy iptables-legacy-libs python3-django3 ceph-mgr-k8sevents
BLKLST_DNF += python3-PyMySQL   # CVE-2024-36039 Upgrade to version: 1.1.1
BLKLST_DNF += python3-django    # CVE-2022-28347, CVE-2023-31047, CVE-2025-64459 CVE-2023-46695, CVE-2023-43665, CVE-2022-36359 Upgrade to version: 3.2.23
ROOTFS_PIP += python-jose       # CVE-2024-33663 Upgrade to version: 3.4.0
BLKLST_DNF += python3-monascaclient # Remove DNF managed package
# CVE-2022-2996. The rpm stays blacklisted; the ROOTFS_PIP entry that used to
# replace it with 0.12.0 is gone. scciclient backs ironic's iRMC driver, ironic runs
# in the antelope venv now, and core/ironic deliberately does not install it there --
# so the system python 3.9 copy had no importer left. Nothing in the image carries
# scciclient at all now, which is the stronger answer to the CVE.
BLKLST_DNF += python3-scciclient
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
	$(Q)echo "Add to $(ROOTDIR) repos: $(INFLUXDB_REPO) $(CEPH_REPO) $(PROMETHEUS_REPO) $(DOCKER_REPO)"
	$(Q)mkdir -p $(RPMS_DIR) $(PIPS_DIR) $(ARCS_DIR)

rootfs_install::
	$(Q)chroot $(ROOTDIR) dnf -y install centos-release-openstack-$(OPENSTACK_RELEASE)
	$(Q)# centos-release-openstack-antelope *requires* centos-release-ceph-quincy, so the
	$(Q)# line above installs it every build and it cannot simply be erased: `rpm -e
	$(Q)# --nodeps` leaves antelope with an unsatisfied dependency, which `dnf check`
	$(Q)# reports for the life of the image ("has missing requires of
	$(Q)# centos-release-ceph-quincy").
	$(Q)#
	$(Q)# Disabling the repo gets what we actually want -- 17.2.z out of dnf's view --
	$(Q)# while leaving the package installed, the dependency satisfied and the rpm
	$(Q)# database clean. It matters because the quincy and reef release rpms own
	$(Q)# differently-named CentOS-Ceph-*.repo files and neither Obsoletes the other, so
	$(Q)# without this dnf sees 17.2.z and 18.2.z at once. The pinned NVRs in
	$(Q)# core/ceph/ceph.mk would still resolve correctly, but any *unpinned* dependency
	$(Q)# could be satisfied from the wrong release.
	$(Q)chroot $(ROOTDIR) dnf -y install centos-release-ceph-reef
	$(Q)chroot $(ROOTDIR) dnf config-manager --set-disabled centos-ceph-quincy
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
#
# What made 9.1.0-20 and -27 incompatible was 9.1.0-21's
# kvm-hw-i386-Fix-machine-type-compatibility.patch [RHEL-91307], which rewrites the
# x86 machine-type compat property tables -- so the same pc-q35-rhel9.N.0 name
# describes a different guest on either side and the migration stream does not match.
# That gives the rule for moving this pin: a z-stream bump is live-migration-safe when
# `dnf repoquery --changelogs` over the delta shows no hw-i386 machine-type/compat
# patch and `qemu-kvm -M help` still resolves q35 to the same pc-q35-rhel9.N.0. Both
# hold for -22 -> -23, whose delta is scsi reservations, an ide/block drain deadlock,
# MIGRATION_STATUS_FAILING and s390x hardening; -23 also fixes three migration bugs of
# its own (RHEL-158244, RHEL-190701, RHEL-45628). Verified on accept-3cc in every
# direction -- -22 -> -23, -23 -> -22, and a guest first booted under -23 migrated to
# a -22 node and back -- all completed with no error in any nova-compute log.
#
# There is no qemu-kvm 11.x to move to: the CentOS Stream koji carries 10.0.0 and
# 10.1.0 and nothing above, for el9 and el10 alike, all at epoch 17.
#
# No epoch, even though every qemu build carries Epoch 17. LOCKED_DNF is only ever
# matched as a *string* against rpm filenames, and a filename never carries an epoch:
# installdnf derives qemu-img-10.1.0-22.el9 from the file and greps locked_rpms.txt
# for it, so a locked_rpms.txt line reading qemu-img-17:10.1.0-22.el9 never matched.
# The duplicate pass then saw the pinned rpm as nothing but the older of the pair and
# deleted it -- 17 of the 18 packages, leaving builds on build-day c9s (10.1.0-23 on
# prod and jim, 2026-08-15) with qemu-guest-agent-10.1.0-22 stranded beside them,
# which is the drift #1150 pinned against. The same colon truncated the archive
# lookup to `qemu-img*` (qemu-img-17 -> qemu-img), so a workspace holding a retired
# 9.1.0 set got it copied in as a third version and installdnf, which only resolves
# duplicates in pairs, failed the build outright with "Unhandled pkg duplicates".
# Dropping the epoch changes no resolution -- every candidate in c9s is epoch 17, and
# dnf takes the NVR without it -- and it puts qemu on the same form as libvirt in
# core/nova/nova.mk and pacemaker, whose locks hold for exactly that reason.
QEMU_VER := -10.1.0-23.el9
# Filename NVR (no epoch); kojihub keeps builds the c9s mirror rotates away, so an
# air-gapped rebuild resolves the exact NVR (same pattern as mysql.mk).
QEMU_NVR := 10.1.0-23.el9
QEMU_URL := https://kojihub.stream.centos.org/kojifiles/packages/qemu-kvm/10.1.0/23.el9/x86_64
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

$(call PROJ_INSTALL_DNF_NOARCH,-w ,"curl wget jq tcpdump util-linux uuid git python3-devel gcc java-11-openjdk-headless $(RUBY) $(ROOTFS_DNF_NOARCH_P1) edk2-ovmf python3-pip python3-six python3-lasso sos emacs-nox expect tcl $(PYTHON3_SAML_REQUIRE) perf arp-scan")

rootfs_install::
	$(Q)chroot $(ROOTDIR) python3 -m pip install -U pip
	$(Q)chroot $(ROOTDIR) dnf install -y liburing

# ceph dashboard sso needs python3-saml which complains LookupError: unknown encoding: cp437
rootfs_install::
	$(Q)wget https://raw.githubusercontent.com/python/cpython/main/Lib/encodings/cp437.py -P $(ROOTDIR)/usr/lib64/python3.9/encodings/

# NOTE: this used to carry
#   LOCKED_DNF += python3-google-auth-1.30.0-1.el9s
# to settle "cannot install both python3-google-auth-1:2.28.0-1.el9.noarch from
# @commandline and python3-google-auth-1:1.30.0-1.el9s.noarch from
# centos-openstack-yoga". 1.30.0-1.el9s was a *yoga repo* build and no longer exists
# in any enabled repo -- antelope carries 1:2.12.0-1.el9s -- so the pin matched
# nothing and installdnf's duplicate pass fell through to plain version comparison
# anyway. Nothing requires the package (`rpm -q --whatrequires` is empty), and the
# newest candidate is epel's 1:2.45.0-1.el9, which is what jim-1cc already runs.

$(call PROJ_INSTALL_DNF_NOARCH,-d "$(ROOTFS_DNF_DL_FROM)","$(ROOTFS_DNF)")
# $(call PROJ_INSTALL_DNF_NOARCH,-n,"$(ROOTFS_DNF_NS)")

# install no constraint packages first
$(call PROJ_INSTALL_PIP_NC,,$(ROOTFS_PIP_NC))
$(call PROJ_INSTALL_PIP,-b "$(OPS_GITHUB_BRANCH_01)" -d "$(ROOTFS_PIP_DL_FROM)",$(ROOTFS_PIP))

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
	$(Q)cp -f $(OPENSTACK_PIP_CONSTRAINT) $(ROOTDIR)/opt/openstack-antelope/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && pip install --upgrade pip"
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install --upgrade -c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) setuptools wheel

# NOTE: setuptools in this venv is pinned to 65.7.0 by the constraints file -- the
# version antelope's own upper-constraints names -- because setuptools 82 deleted
# pkg_resources and the 2023-era services still import it (see cubecos#607/#1080).
#
# The pin is applied here, at creation, rather than being left to whichever later
# `pip install -c` happens to pull setuptools in as a dependency. It used to be:
# `pip install --upgrade pip setuptools` put the *current* setuptools in the venv
# (84.0.0 as of this writing) and nothing constrained it until some service install
# further down resolved setuptools==65.7.0 and downgraded it. Everything installed in
# between ran against a setuptools with no pkg_resources -- and core/ceph/ceph.mk is
# in between, because ceph sits ahead of keystone in HEAVY_COMPONENTS. Its rados/rbd
# bindings are a `setup.py install`, whose egg_info step loads pbr's entry point, and
# pbr imports pkg_resources: "ModuleNotFoundError: No module named 'pkg_resources'".
# Note also that this only broke once setuptools 82 shipped, so it fails on a date,
# not on a commit -- pinning at creation is what removes that.
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

# set up the execution context for openstack caracal
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(CARACAL_OPENSTACK_HOME_DIR)
	$(Q)chroot $(ROOTDIR) python$(CARACAL_PYTHON_VER) -m venv $(CARACAL_OPENSTACK_HOME_DIR)
	$(Q)cp -f $(CARACAL_OPENSTACK_PIP_CONSTRAINT) $(ROOTDIR)$(CARACAL_OPENSTACK_HOME_DIR)/
	$(Q)chroot $(ROOTDIR) bash -c "source $(CARACAL_OPENSTACK_HOME_DIR)/bin/activate && pip install --upgrade pip"
	$(Q)chroot $(ROOTDIR) $(CARACAL_OPENSTACK_HOME_DIR)/bin/pip install --upgrade -c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) setuptools wheel

# NOTE: os-caracal-pip-upper-constraints.txt is upstream's unmaintained/2024.1
# upper-constraints.txt copied down verbatim, save for one local delta -- unlike the
# antelope file, which carries six. Upstream does not pin setuptools, so this venv used
# to land on whatever was current (84.0.0), which was fine while skyline was the only
# occupant. keystone is not: keystonemiddleware 10.6.0 does `import pkg_resources` in
# _common/config.py, and setuptools 82 deleted pkg_resources, so every gunicorn worker
# died at import with ModuleNotFoundError and openstack-keystone never came up (#631).
#
# The pin is therefore settled now, as the same one line in the constraints file that
# antelope uses -- but at 75.6.0, not antelope's 65.7.0. The two venvs have different
# reasons for their numbers: antelope's is the version its own upper-constraints
# names, while caracal's is a local delta with no upstream value to match, so it takes
# the newest release that clears both ceilings rather than a 2023 one inherited by
# habit. 75.6.0 is the last setuptools of 2024 (2024-11-20), which puts it in the same
# year as the release this venv carries.
#
# The two ceilings, both still honoured:
#   - below 82 (2026-02-08), which deleted pkg_resources. That is the hard one, and
#     it is a runtime requirement as much as a build one -- keystonemiddleware above,
#     plus pbr's egg_info writer on every --no-build-isolation build in this venv.
#   - below 80 (2025-04-27), which removed `setup.py install`. Nothing anywhere in
#     the tree invokes that command any more: ceph's bindings moved to `pip install`
#     (see core/ceph/ceph.mk), skyline's did too, and #636 converted the last four --
#     the designate, masakari, watcher and neutron-vpnaas dashboards -- from a git
#     clone to a pinned pip install as they followed horizon here. The ceiling is
#     kept anyway: it costs nothing, and it is what makes a future `setup.py`
#     install fail on review rather than on build day.
#
# Verified in a python 3.11 venv before the bump: horizon 24.0.2's six sdists build
# under --no-build-isolation, ceph's rados and rbd bindings produce the same flat
# .so + .dist-info layout as under 65.7.0 and import, and pkg_resources is present.

# install the openstack cli inside the python 3.11 virtual environment
#
# /usr/bin/openstack was the python3-openstackclient rpm, so it ran as
# `#!/usr/bin/python3` (3.9). That shebang is what pinned half a dozen osc plugins
# to the system python: a plugin is an [openstack.cli.extension] stevedore entry
# point, and entry points are only visible to the interpreter they were installed
# under, so the copies pip put in a venv were invisible to the cli and every plugin
# had to be held in 3.9 as well -- as an rpm (designate, heat, manila, octavia) or as
# a second pip install (cyborg, watcher, monasca). #609 moved the cli into the
# antelope venv and every plugin followed it there; #636 moves it again, into the
# caracal venv, and the plugins follow it a second time.
#
# The second move is the same mechanism as the first, so the same rule decides where
# each plugin goes: next to whichever interpreter runs /usr/bin/openstack. Each
# component installs its own -- see core/{heat,manila,octavia,designate,masakari,
# watcher,cyborg,barbican,monasca}. python-ironicclient needs no line of its own:
# ironic-ui and python-watcher both declare it and both are in this venv.
#
# Measured on jim-1cc: 977 commands under the 3.9 cli against 1574 under the antelope
# one, because a venv resolves plugins 3.9 never had -- `openstack baremetal ...`
# among them, which used to fall through to osc's did-you-mean list.
#
# No version is pinned. python-openstackclient is a client, so
# os-caracal-pip-upper-constraints.txt already carries it (6.6.1) and naming it again
# here could only drift from that file.
#
# The rpm also owned /usr/bin/openstack-3, the Fedora python3 alias. Nothing in this
# tree calls it and no other venv console script is aliased that way, so it is not
# recreated.
rootfs_install::
	$(Q)chroot $(ROOTDIR) $(CARACAL_OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-openstackclient
	$(Q)# Link the cli. hex_sdk reaches it by absolute path ($$OPENSTACK in
	$(Q)# core/sdk_sh/modules.pre/sdk_01-var-static.sh is /usr/bin/openstack), so
	$(Q)# this symlink is what carries every caller over.
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/openstack /usr/bin/openstack

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

# /var/update should work irrespective of a functioning cephfs mount
rootfs_install::
	$(Q)umount $(ROOTDIR)/proc || /bin/true
	$(Q)chroot $(ROOTDIR) sh -c "mkdir -p /mnt/cephfs/update"
	$(Q)chroot $(ROOTDIR) sh -c "rm -rf /var/update ; ln -sf /mnt/cephfs/update /var/update"

PKGCLEAN += $(HEAVYFS) $(RPMS_DIR) $(PIPS_DIR) $(ARCS_DIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
