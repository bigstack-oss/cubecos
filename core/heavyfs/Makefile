# Cube SDK
# Openstack + most heavy lifting installs (dnf/rpm, pip, git)
# Output is heavyfs.cgz which is dependent upon by rootfs

include ../../build.mk

PROJ_HEAVYFS_INSTALL := 1
RPMS_DIR := $(CURDIR)/RPMS
PIPS_DIR := $(CURDIR)/PIPS
ARCS_DIR := $(CURDIR)/ARCS
HEAVYFS = $(CURDIR)/heavy_rootfs
HEAVY_BASE = $(CURDIR)/heavy_base

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
# python-jose is no longer installed into the system python. The line that put it
# there upgraded a yoga-era copy; skyline, its only user, now runs in the openstack
# venv with its own copy, and nothing else in the image imports jose.
# CVE-2022-2996. The rpm stays blacklisted; the ROOTFS_PIP entry that used to
# replace it with 0.12.0 is gone. scciclient backs ironic's iRMC driver, ironic runs
# in the openstack venv, and core/ironic deliberately does not install it there --
# so the system python 3.9 copy had no importer left. Nothing in the image carries
# scciclient at all now, which is the stronger answer to the CVE.
BLKLST_DNF += python3-scciclient
# pillow is no longer installed into the system python either. The line that put it
# there replaced the blacklisted python3-pillow, but nothing in the image imports PIL:
# no installed package or rpm requires it, and neither the tree nor ceph-mgr's modules
# use it. The rpm stays blacklisted.
BLKLST_DNF += python3-pillow    # CVE-2023-50447
ROOTFS_PIP += waitress          # CVE-2024-49768 Upgrade to version: 3.0.1
BLKLST_DNF += python3-numexpr   # Remove DNF managed package
ROOTFS_PIP += numexpr           # CVE-2023-39631 Upgrade to version: 2.8.5
BLKLST_DNF += ansible ansible-core # CVE-2025-58367 Remove DNF managed package
# JavaScriptCore comes in only for libproxy's PAC-script plugin: glib-networking
# recommends libproxy-webkitgtk4 (a weak dependency), and that plugin is the only
# package requiring libjavascriptcoregtk. Nothing in the image runs JavaScript or
# points GLib at a PAC proxy URL. dnf pulls a weak dependency back from the repo even
# after installdnf drops its rpm, so both stay in until cube-post erases the
# blocklist (removed_rpms.txt); nothing requires either once they are gone.
BLKLST_DNF += libproxy-webkitgtk4 webkit2gtk3-jsc

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
	$(Q)# The keys the components pin go into the keyring before anything is installed: dnf -y
	$(Q)# would otherwise import a repository's key from its gpgkey= unchecked
	$(Q)$(IMPORT_RPM_KEYS) $(ROOTDIR) $(RPM_KEYS)
	$(Q)chroot $(ROOTDIR) dnf clean all
	$(Q)echo "Add to $(ROOTDIR) repos: $(INFLUXDB_REPO) $(CEPH_REPO) $(DOCKER_REPO)"
	$(Q)mkdir -p $(RPMS_DIR) $(PIPS_DIR) $(ARCS_DIR)

# The release rpms come from CentOS's extras-common repository, signed with the Extras SIG's key, and
# the openstack repository they add is signed with the Cloud SIG's. The SHA512 copy of the Extras key:
# its SHA1-signed copy carries the same key, and the build host's crypto policy cannot load it.
GPGKEY_DNF += $(COREDIR)/heavyfs/RPM-GPG-KEY-CentOS-SIG-Extras-SHA512 363FC0972F64B699AED3968E1FF6A2171D997668
GPGKEY_DNF += $(COREDIR)/heavyfs/RPM-GPG-KEY-CentOS-SIG-Cloud 736AF5116D9C40E2AF6B074BF9B9FEE7764429E6

rootfs_install::
	$(Q)chroot $(ROOTDIR) dnf -y install centos-release-openstack-$(OPENSTACK_RELEASE)
	$(Q)# The release rpm pulls a ceph release rpm with it, and which one follows the
	$(Q)# openstack release: antelope required centos-release-ceph-quincy, caracal and
	$(Q)# epoxy both require centos-release-ceph-reef. core/ceph pins squid, so the
	$(Q)# squid release rpm is installed on top and the reef repo it arrives with is
	$(Q)# disabled. (epoxy's also requires the same cloud, nfv-openvswitch and
	$(Q)# rabbitmq-38 release rpms caracal's did.)
	$(Q)#
	$(Q)# Disabled, not erased: `rpm -e --nodeps` would leave epoxy's release rpm with an
	$(Q)# unsatisfied dependency and `dnf check` complaining for the life of the image,
	$(Q)# which is exactly what the quincy handling under antelope ran into. And not left
	$(Q)# enabled either: the reef and squid release rpms own differently-named
	$(Q)# CentOS-Ceph-*.repo files and neither Obsoletes the other, so dnf would see
	$(Q)# 18.2.z and 19.2.z at once and any *unpinned* ceph dependency could resolve from
	$(Q)# the wrong release -- on the build and on a customer node's `dnf update` alike.
	$(Q)#
	$(Q)# The disable runs after the openstack release rpm is in, so centos-ceph-reef
	$(Q)# always exists by then; `dnf config-manager --set-disabled` on a repo that does
	$(Q)# not exist exits 1 ("No matching repo to modify"), which is how the quincy line
	$(Q)# had to go when caracal stopped installing it. An openstack release that pairs
	$(Q)# with squid itself makes this line fail the build rather than no-op, which is the
	$(Q)# signal to drop it.
	$(Q)#
	$(Q)# What the openstack repo itself still supplies, now that no service comes
	$(Q)# from an rpm, is the openvswitch glue rdo-ovn needs and part of the system
	$(Q)# python 3.9 rpm set. The glue changes between releases -- epoxy's
	$(Q)# rdo-openvswitch is 3.4 and Obsoletes the openvswitch3.3 core/neutron pins --
	$(Q)# which is why core/neutron fetches the 3.3 builds from koji instead.
	$(Q)chroot $(ROOTDIR) dnf -y install centos-release-ceph-squid
	$(Q)# The squid release rpm writes its repo with gpgcheck=0, so a node's own dnf would install
	$(Q)# from it unchecked
	$(Q)chroot $(ROOTDIR) dnf config-manager --save --setopt=centos-ceph-squid.gpgcheck=1
	$(Q)chroot $(ROOTDIR) dnf config-manager --set-disabled centos-ceph-reef
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

# The jail's kernel rpms, which the Kmods SIG builds and signs (jail/jail.ubi9.dockerfile)
GPGKEY_DNF += $(TOP_SRCDIR)/jail/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-Kmods 48EF712EC5DDB68B5280BE455B8E1A767AE06D54
KERNEL_PKGS := kernel-$(KERNEL_VERS) kernel-core-$(KERNEL_VERS) kernel-devel-$(KERNEL_VERS) kernel-modules-$(KERNEL_VERS)
rootfs_install::
	$(Q)$(CHECK_RPMS) $(ROOTDIR) /kernel-$(KERNEL_VERS)
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
# Both hold again for -23 -> -24, the Epoxy hop's move. Its delta is RHEL-216952
# alone, qemu's stable-branch block and storage fixes (curl, nvme, qcow2 discard and
# zero-write corruption, mirror, commit drain, throttle groups, virtio-scsi,
# virtio-blk, ide), whose one migration-side change is qed no longer flushing during
# incoming migration. q35 still aliases pc-q35-rhel9.8.0, and pc-q35-rhel9.6.0 still
# ships. Verified on accept-3cc as a roll -- each node drained by live migration and
# its nova-compute disabled, qemu bumped, virtqemud and nova-compute restarted, the
# node re-enabled and its guests migrated back -- in both directions, including a
# guest first booted under -24 and one dirtying RAM fast enough to force post-copy;
# and on jim-1cc, where a running guest kept its -23 process through the bump and came
# back on -24 from a hard reboot.
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
QEMU_VER := -10.1.0-24.el9
# Filename NVR (no epoch); kojihub keeps builds the c9s mirror rotates away, so an
# air-gapped rebuild resolves the exact NVR (same pattern as mysql.mk).
QEMU_NVR := 10.1.0-24.el9
QEMU_URL := $(KOJIHUB_DL_HOST)/kojifiles/packages/qemu-kvm/10.1.0/24.el9/x86_64
QEMU_PKGS := qemu-kvm qemu-kvm-device-display-virtio-gpu-pci qemu-kvm-device-display-virtio-gpu
QEMU_PKGS += qemu-kvm-device-display-virtio-vga qemu-kvm-device-usb-redirect qemu-kvm-device-usb-host
QEMU_PKGS += qemu-guest-agent qemu-kvm-block-rbd qemu-kvm-block-blkio qemu-kvm-common qemu-kvm-core
QEMU_PKGS += qemu-img qemu-kvm-audio-pa qemu-pr-helper qemu-kvm-tools qemu-kvm-ui-egl-headless
QEMU_PKGS += qemu-kvm-ui-opengl qemu-kvm-docs
QEMU_LOCKED_RPMS := $(foreach p,$(QEMU_PKGS),$(p)$(QEMU_VER))
LOCKED_DNF += $(QEMU_LOCKED_RPMS)
$(foreach p,$(QEMU_PKGS),$(eval ROOTFS_DNF_DL_FROM += $(QEMU_URL)/$(p)-$(QEMU_NVR).x86_64.rpm))

# rsync is Rocky 9's build, not Stream's. RHEL 9.8 fixed sixteen Important CVEs by rebasing to
# 3.2.7 (rsync-3.2.7-1.el9_8); Stream 9 has not shipped that rebase -- its newest build is
# 3.2.5-9, and the 3.2.5-10 draft fixes a different one. Rocky rebuilds the errata from the same
# source rpm. Fetched here, it sits beside the 3.2.5-9 that the plain "rsync" in ROOTFS_DNF pulls,
# and installdnf's duplicate pass keeps the higher version, so Stream's own build takes over the
# day one sorts above it. No Rocky key goes into the image, since a node has no other reason to trust
# it: each Rocky download is pinned by its sha256 instead, taken from a copy that verified against
# Rocky 9's release key (21CB256AE16FC54C6E652949702D426D350D275D).
#
# ROCKY_PATH is where every Rocky download in this file comes from. Rocky keeps only its current
# minor release under pub/, so once Rocky 9.9 ships these downloads fail loudly rather than quietly.
# 9.8's tree then moves to vault/rocky/9.8, with the same files and so the same pins: pointing
# ROCKY_PATH there is the one-line fix, until the entries are taken from 9.9 or Stream catches up.
ROCKY_PATH := pub/rocky/9.8
RSYNC_NVR := 3.2.7-1.el9_8
ROOTFS_DNF_DL_FROM += $(ROCKY_DL_HOST)/$(ROCKY_PATH)/BaseOS/x86_64/os/Packages/r/rsync-$(RSYNC_NVR).x86_64.rpm
PINNED_DNF += c10dd298e3d664a0dcc18fc3aeb3273745ef55d9745f1b73e8f35e5a90c6e245 rsync-$(RSYNC_NVR).x86_64.rpm

# pcre2, librabbitmq, python3-tornado, sqlite, libevent, gnupg2, protobuf, python3-urllib3,
# python3-lxml, libreswan, ruby and brotli come from Rocky 9 the same way. RHEL fixed a known
# vulnerability in each in a z-stream build -- el9_8 (el9_8.1 for brotli), or el9_7 for gnupg2 and
# protobuf -- and Stream's newest builds carry the same version and release without that suffix
# (pcre2 10.40-7.el9 against 10.40-7.el9_8), which sorts below it. Every installed subpackage moves
# together, i686 copies included, since they require each other's exact version, the -devel
# packages the build has until cube-post.mk removes them included. protobuf-compiler is in Rocky's
# CRB. Entries are <repo>/<first letter>/<rpm>.
#
# Stream's own build takes over once its release passes RHEL's: installdnf's duplicate pass keeps
# the higher of the copies in the download directory, and drops a downloaded copy older than the
# build the rootfs already has. An entry can come out then. openssl was here until Stream's
# 3.5.9-1.el9, a rebase onto OpenSSL 3.5.9, which carries the fix RHEL had backported into
# 3.5.8-2.el9_8. Each entry has its PINNED_DNF line below, as rsync has.
ROCKY_ERRATA_RPMS := \
	BaseOS/p/pcre2-10.40-7.el9_8.x86_64 \
	BaseOS/p/pcre2-syntax-10.40-7.el9_8.noarch \
	AppStream/p/pcre2-utf16-10.40-7.el9_8.x86_64 \
	AppStream/p/pcre2-utf32-10.40-7.el9_8.x86_64 \
	AppStream/p/pcre2-devel-10.40-7.el9_8.x86_64 \
	AppStream/l/librabbitmq-0.11.0-7.el9_8.1.x86_64 \
	AppStream/p/python3-tornado-6.5.10-1.el9_8.1.x86_64 \
	AppStream/s/sqlite-3.34.1-11.el9_8.x86_64 \
	AppStream/s/sqlite-devel-3.34.1-11.el9_8.x86_64 \
	BaseOS/s/sqlite-libs-3.34.1-11.el9_8.x86_64 \
	BaseOS/s/sqlite-libs-3.34.1-11.el9_8.i686 \
	BaseOS/l/libevent-2.1.13-1.el9_8.x86_64 \
	BaseOS/g/gnupg2-2.3.3-5.el9_7.x86_64 \
	AppStream/p/protobuf-3.14.0-17.el9_7.x86_64 \
	CRB/p/protobuf-compiler-3.14.0-17.el9_7.x86_64 \
	AppStream/p/python3-protobuf-3.14.0-17.el9_7.noarch \
	BaseOS/p/python3-urllib3-1.26.5-8.el9_8.noarch \
	AppStream/p/python3-lxml-4.6.5-3.el9_8.1.x86_64 \
	AppStream/l/libreswan-4.15-10.el9_8.x86_64 \
	AppStream/r/ruby-3.0.7-168.el9_8.x86_64 \
	AppStream/r/ruby-3.0.7-168.el9_8.i686 \
	AppStream/r/ruby-devel-3.0.7-168.el9_8.x86_64 \
	AppStream/r/ruby-libs-3.0.7-168.el9_8.x86_64 \
	AppStream/r/ruby-libs-3.0.7-168.el9_8.i686 \
	AppStream/r/ruby-default-gems-3.0.7-168.el9_8.noarch \
	AppStream/r/rubygems-3.2.33-168.el9_8.noarch \
	AppStream/r/rubygem-bigdecimal-3.0.0-168.el9_8.x86_64 \
	AppStream/r/rubygem-bundler-2.2.33-168.el9_8.noarch \
	AppStream/r/rubygem-io-console-0.5.7-168.el9_8.x86_64 \
	AppStream/r/rubygem-json-2.5.1-168.el9_8.x86_64 \
	AppStream/r/rubygem-psych-3.3.2-168.el9_8.x86_64 \
	AppStream/r/rubygem-rdoc-6.3.4.1-168.el9_8.noarch \
	AppStream/r/rubygem-rexml-3.2.5-168.el9_8.noarch \
	BaseOS/l/libbrotli-1.0.9-10.el9_8.1.x86_64 \
	AppStream/b/brotli-1.0.9-10.el9_8.1.x86_64 \
	AppStream/b/brotli-devel-1.0.9-10.el9_8.1.x86_64
rocky_rpm_url = $(ROCKY_DL_HOST)/$(ROCKY_PATH)/$(word 1,$(subst /, ,$(1)))/x86_64/os/Packages/$(word 2,$(subst /, ,$(1)))/$(word 3,$(subst /, ,$(1))).rpm
ROOTFS_DNF_DL_FROM += $(foreach p,$(ROCKY_ERRATA_RPMS),$(call rocky_rpm_url,$(p)))
PINNED_DNF += dc350245c7781a0ac2ffce92e088a22c3741bf967ce7c551d0420cea9ae085eb pcre2-10.40-7.el9_8.x86_64.rpm
PINNED_DNF += aaff0127ff9456106ca5b4139f93881e75c16502499d378021fba649730ee174 pcre2-syntax-10.40-7.el9_8.noarch.rpm
PINNED_DNF += 76ff9a22021791c37c87d32ba8037402dc7f5242560c74f479c990aae860b271 pcre2-utf16-10.40-7.el9_8.x86_64.rpm
PINNED_DNF += dbc674d263c71d34a35fd4e87d384ff528183344901cbac977fd01118d4e5d84 pcre2-utf32-10.40-7.el9_8.x86_64.rpm
PINNED_DNF += 892b094be072d15dab5f2f29c16586730b918b5d3bf52d94d09e7341643febd0 pcre2-devel-10.40-7.el9_8.x86_64.rpm
PINNED_DNF += 4bfe6fa6d1834f712db7343a26abc74919fb76db5820624ab741f43bc7db9988 librabbitmq-0.11.0-7.el9_8.1.x86_64.rpm
PINNED_DNF += 9c8562e43c43ccc35cd614ab5f63342e4cbfa97f53a1d2d824d19d7db7cf8630 python3-tornado-6.5.10-1.el9_8.1.x86_64.rpm
PINNED_DNF += afaf7567658d1c4dc70c682fe95b686a0986b0a85f3e2caa7a4bbf5eeeee5300 sqlite-3.34.1-11.el9_8.x86_64.rpm
PINNED_DNF += 8a60c4a6c3b5931fe7a4151e507d716acc5482d8182d567f67b26c89e6ab6d48 sqlite-devel-3.34.1-11.el9_8.x86_64.rpm
PINNED_DNF += 7150f09994a94181f9c6d3fce29abf922c20ae3d90683d2f0e535fa72ec04876 sqlite-libs-3.34.1-11.el9_8.x86_64.rpm
PINNED_DNF += 4d6ddf6805b679f75b7182d986dbb71acea7e3cd4959e5604c5fede82e1b45ab sqlite-libs-3.34.1-11.el9_8.i686.rpm
PINNED_DNF += 3f5dec4cb901f21e0cd20bdca2a7a30cf2cc1973faa79896c19676dcb75e563b libevent-2.1.13-1.el9_8.x86_64.rpm
PINNED_DNF += 47ecef51db73418e387d06247eb44e440f62d65e193673f3d2712d73bc569fa4 gnupg2-2.3.3-5.el9_7.x86_64.rpm
PINNED_DNF += fa56a95f91886936b60bbf3264f2374ffe991efa16963c63eb6be949ee5c552f protobuf-3.14.0-17.el9_7.x86_64.rpm
PINNED_DNF += d5f5a321ef0334332542a8c527eef85a7a2cbe382c8a7a4f131142e0d4cf3ff4 protobuf-compiler-3.14.0-17.el9_7.x86_64.rpm
PINNED_DNF += 6390cb4e53898aa27737bd0bb6a100cd8d3526bc77b074a8faa9f31b9bff2477 python3-protobuf-3.14.0-17.el9_7.noarch.rpm
PINNED_DNF += 25d9b56cfee5643e1057c014cf6e7182647b84656821af837ad99c8f87c20ae0 python3-urllib3-1.26.5-8.el9_8.noarch.rpm
PINNED_DNF += 30dcacac3537f4f6bfb31d1986c7dbe54e15e255fadc2f08e26d0b1cfffec98c python3-lxml-4.6.5-3.el9_8.1.x86_64.rpm
PINNED_DNF += 9782b5ad185103c56035eff353065f3e77019567f268ec15073532c874c27726 libreswan-4.15-10.el9_8.x86_64.rpm
PINNED_DNF += 5b22820c933fddbee9d2a64fb3122c2dcd7055c5c12c9ace0a4cc1a8a3eab66a ruby-3.0.7-168.el9_8.x86_64.rpm
PINNED_DNF += 7553b1199368a94ab48ab2dd5ce5767e71e1ce9e711035bc9379e497a7911322 ruby-3.0.7-168.el9_8.i686.rpm
PINNED_DNF += aab2a81b617f966d53a2f5053afae97abb486c36b73e00f933b860ca4bd133dc ruby-devel-3.0.7-168.el9_8.x86_64.rpm
PINNED_DNF += 9855eb9987baff924d46ac842791cf45c8880db2d6ae20c4a93956ed5272db53 ruby-libs-3.0.7-168.el9_8.x86_64.rpm
PINNED_DNF += c37eb7e1734cee80ce5bc46eee43c13010b4b49b370d2dcca1527729fc569bd5 ruby-libs-3.0.7-168.el9_8.i686.rpm
PINNED_DNF += 6b25417e9360b96812b73e8a589aba626f05961ffad2068668cbb8ad14a76293 ruby-default-gems-3.0.7-168.el9_8.noarch.rpm
PINNED_DNF += f067f26d8a331653367d074a5bbcf876a0c4d9c4f03074c19a5afa50292025b4 rubygems-3.2.33-168.el9_8.noarch.rpm
PINNED_DNF += e5e84c2b4df9f7ed09526e93592fcedcdb13cba4d25d653c069076e6b0b4044d rubygem-bigdecimal-3.0.0-168.el9_8.x86_64.rpm
PINNED_DNF += 03ae44cee6ddccb18da76dccccded08c605093b18919a4fd3e4d6ea5c9d3018e rubygem-bundler-2.2.33-168.el9_8.noarch.rpm
PINNED_DNF += 41b62e4d96053fbc396d40bbb5184a1f7b09cd3c9601e4310edd671c0687ff0a rubygem-io-console-0.5.7-168.el9_8.x86_64.rpm
PINNED_DNF += a2aed941d6bf4f12bb2779ed779036368735ca92d6de93d8a11c119b9c6ad7ca rubygem-json-2.5.1-168.el9_8.x86_64.rpm
PINNED_DNF += 6a79fd9ac0824f84a0c8525374688480b513d45882bb9bb611b3de8222a99f74 rubygem-psych-3.3.2-168.el9_8.x86_64.rpm
PINNED_DNF += 6592b5fe5e5f18261213c4257c15f7f553e18a797704c126ea5c40d947006f20 rubygem-rdoc-6.3.4.1-168.el9_8.noarch.rpm
PINNED_DNF += e21ed4007fe4f3ac53a477b23f2d77c8670faa01a5d600a9bb77389fb094b438 rubygem-rexml-3.2.5-168.el9_8.noarch.rpm
PINNED_DNF += ce72c3ec1513fe852bb654ab141f4014286e09a0ab09c7dd7d79805af1f42200 libbrotli-1.0.9-10.el9_8.1.x86_64.rpm
PINNED_DNF += a8bf13944227fa8e81cbb1ce311a74414d6cdedd850090372f30189d085bb4b8 brotli-1.0.9-10.el9_8.1.x86_64.rpm
PINNED_DNF += b51b4abfdc0086162e1c00c5dfb3165fd06687dbc03be2610325913892f4657c brotli-devel-1.0.9-10.el9_8.1.x86_64.rpm

$(call PROJ_INSTALL_DNF_NOARCH,,$(LOCKED_DNF))

rootfs_install::
	$(Q)chroot $(ROOTDIR) dnf update -y systemd

# python3-xmlsec
PYTHON3_SAML_REQUIRE := libxml2-devel xmlsec1-devel xmlsec1-openssl-devel libtool-ltdl-devel python-xmlsec

# The install below names ruby by its full version so that dnf takes the base 3.0 build:
# ruby-3.1.2-141.module_el9+156+2e0939d1 has no i686 and conflicts with ruby-3.0.4-161.el9.i686.rpm.
# It is not in LOCKED_DNF. Rocky's 3.0.7-168.el9_8 replaces it (ROCKY_ERRATA_RPMS), and a lock
# makes installdnf's duplicate pass keep this copy and delete Rocky's, leaving ruby at el9 beside
# ruby-libs and the gems at el9_8. installdnf matches a lock as a substring of the rpm's name, so
# a lock on ruby-3.0.7-168.el9_8 would also match ruby-3.0.7-168.el9 and do the same.
RUBY := ruby-3.0.7-168.el9

# python3-numpy-1:1.23.5-1.el9.x86_64 from @commandline and python3-numpy-1:1.20.1-5.el9.x86_64 from appstream
# PYTHON3-NUMPY := python3-numpy-1:1.20.1-5.el9
# PYTHON3-NUMPY-F2PY := python3-numpy-f2py-1:1.20.1-5.el9
# LOCKED_DNF += $(PYTHON3-NUMPY-F2PY)

# bash-completion is the loader: the /etc/profile.d hook and the script that reads
# /etc/bash_completion.d and /usr/share/bash-completion/completions. It was never
# named here before -- it arrived as a Recommends of the python3-openstackclient
# rpm, which dnf honours by default, and it left with that rpm when #609 moved the
# cli into a venv. From 3.1.10 on nothing read those directories, so the ceph, rbd,
# ovs-vsctl, systemctl and git completions still on disk went dead along with
# openstack's (#1611). Naming it is what keeps it from leaving with a package again.
#
# The system JDK runs Kafka and the ZooKeeper bundled with it, and nothing else: OpenSearch and
# Logstash carry their own. It is the newest LTS, 25, because Stream 9 stopped updating
# java-11-openjdk at 11.0.20.1, which carries known vulnerabilities.
$(call PROJ_INSTALL_DNF_NOARCH,-w ,"curl wget jq tcpdump util-linux uuid git python3-devel gcc java-25-openjdk-headless $(RUBY) $(ROOTFS_DNF_NOARCH_P1) edk2-ovmf python3-pip python3-six python3-lasso sos emacs-nox expect tcl $(PYTHON3_SAML_REQUIRE) arp-scan bash-completion")

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

# install python 3.12 for openstack epoxy
#
# NOTE: why the build and the install are two separate make invocations.
#
# With --enable-optimizations, a one-shot `make altinstall` does not install the PGO
# binary. CPython's altbininstall depends on $(BUILDPYTHON) directly, so it builds a
# plain -O3 python first and installs it; libinstall then depends on `all`, which runs
# the profile-opt cycle (instrumented build, profile run, clean, rebuild) only after
# the binary is already in /usr/local. The PGO result stays in the build tree. Adding
# -j to the one-shot form is worse: the profile-opt `make clean` races altbininstall's
# link and fails with "ld: cannot find Python/thread.o".
#
# Running `make -j8` first finishes the whole profile-opt cycle, and the following
# `make altinstall` finds everything up to date and installs that binary without
# recompiling. With identical inputs, -j8 and -j1 produce byte-identical objects; the
# PGO binary still differs from build to build because the profile run is not
# deterministic, with or without -j.
rootfs_install::
	$(Q)# we need to mount /dev into the chroot environment because building cpython would write to /dev/null, a character device
	$(Q)mount -o bind /dev $(ROOTDIR)/dev || true
	$(Q)chroot $(ROOTDIR) dnf -y install git pkg-config
	$(Q)chroot $(ROOTDIR) dnf -y install dnf-plugins-core
	$(Q)chroot $(ROOTDIR) dnf -y builddep python3
	$(Q)chroot $(ROOTDIR) mkdir -p /usr/src/python-$(PYTHON_VER)
	$(Q)chroot $(ROOTDIR) wget -O /usr/src/python-$(PYTHON_VER)/Python-$(PYTHON_PATCH_VER).tgz https://www.python.org/ftp/python/$(PYTHON_PATCH_VER)/Python-$(PYTHON_PATCH_VER).tgz
	$(Q)chroot $(ROOTDIR) tar -xvzf /usr/src/python-$(PYTHON_VER)/Python-$(PYTHON_PATCH_VER).tgz -C /usr/src/python-$(PYTHON_VER)
	$(Q)chroot $(ROOTDIR) bash -c "cd /usr/src/python-$(PYTHON_VER)/Python-$(PYTHON_PATCH_VER) && ./configure --enable-optimizations"
	$(Q)chroot $(ROOTDIR) bash -c "cd /usr/src/python-$(PYTHON_VER)/Python-$(PYTHON_PATCH_VER) && make -j8 && make altinstall"
	$(Q)umount -l $(ROOTDIR)/dev || true
	$(Q)# ensure python 3.12 is successfully built
	$(Q)chroot $(ROOTDIR) [ -f /usr/local/bin/python$(PYTHON_VER) ]
	$(Q)chroot $(ROOTDIR) [ -f /usr/local/bin/pip$(PYTHON_VER) ]

# NOTE: why the setuptools pin is applied at venv creation, below, rather than being
# left to whichever later `pip install -c` happens to pull setuptools in as a
# dependency. (Which version, and why that number, is the NOTE after the venv block.)
#
# It used to be: `pip install --upgrade pip setuptools` put the *current* setuptools in
# the venv and nothing constrained it until some service install further down resolved
# the pinned version and downgraded it. Everything installed in between ran against a
# setuptools with no pkg_resources -- and core/ceph/ceph.mk is in between, because ceph
# sits ahead of keystone in HEAVY_COMPONENTS. Its rados/rbd bindings are a
# `setup.py install`, whose egg_info step loads pbr's entry point, and pbr imports
# pkg_resources: "ModuleNotFoundError: No module named 'pkg_resources'". Note also that
# this only broke once setuptools 82 shipped, so it fails on a date, not on a commit --
# pinning at creation is what removes that.
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
# --no-build-isolation, which builds against this venv's own pinned setuptools
# instead. It is
# spelled out on each pip install that needs it rather than turned on venv-wide,
# because the requirement is not universal -- mysqlclient 2.2.8 is the counter-example
# and needs a setuptools newer than the pin, so it keeps the default isolation.
#
# One ordering caveat: with --no-build-isolation an XStatic sdist can only be built
# while no other XStatic package is installed yet, or the installed pkg_resources
# namespace shadows the source tree and setup.py fails with "cannot import name ...
# from 'xstatic.pkg' (unknown location)". A single pip invocation is fine -- pip
# builds every sdist before installing any of them.
#
# The service installs now run through uv rather than pip (OPENSTACK_PIP_INSTALL in
# project.mk), and all of the above was written against pip. It still holds under uv:
# uv's build isolation does not apply -c either, and a single uv invocation also builds
# before it installs. Shown by the first two uv builds (2026-10-17): horizon's XStatic
# sdists built under --no-build-isolation, mysqlclient built in isolation, and the
# venv's pip freeze matched pip-built develop's.

# set up the execution context for openstack epoxy
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(OPENSTACK_HOME_DIR)
	$(Q)chroot $(ROOTDIR) python$(PYTHON_VER) -m venv $(OPENSTACK_HOME_DIR)
	$(Q)cp -f $(OPENSTACK_PIP_CONSTRAINT) $(ROOTDIR)$(OPENSTACK_HOME_DIR)/
	$(Q)chroot $(ROOTDIR) bash -c "source $(OPENSTACK_HOME_DIR)/bin/activate && pip install --upgrade pip"
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install --upgrade -c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) setuptools wheel

# uv for the service installs into the venv above (see OPENSTACK_PIP_INSTALL in
# project.mk). It lives in a venv of its own under /var/tmp, which the block below the
# component include removes, cache and all.
rootfs_install::
	$(Q)chroot $(ROOTDIR) python$(PYTHON_VER) -m venv $(OPENSTACK_UV_HOME)/venv
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_UV_HOME)/venv/bin/pip install uv==$(UV_VER)

# NOTE: os-epoxy-pip-upper-constraints.txt is upstream's stable/2025.1
# upper-constraints.txt copied down, save for local deltas: libvirt-python, raised to
# 11.10.0 to match the libvirt-devel headers core/nova/nova.mk holds; setuptools, which
# upstream does not pin; and the packages raised past upstream's pin to clear a
# vulnerability, each with its reasons in the commit that raised it. setuptools is
# pinned at venv creation above for the reason the NOTE before the venv block gives.
#
# The pin has one ceiling: below 82 (2026-02-08), which deleted pkg_resources. On
# caracal that was a runtime requirement as well as a build one: keystonemiddleware
# 10.6.0 did `import pkg_resources`, so every keystone gunicorn worker died at import
# (#631). The runtime half has gone -- keystonemiddleware 10.9.1 no longer imports it,
# and pbr 7.0.0 reaches for it only when importlib.metadata is missing, which it never
# is on 3.12, so keystone's whole import chain loads with pkg_resources blocked. The
# build half has not: every --no-build-isolation install in this venv builds against
# this setuptools, and four of the sdists horizon 25.3.2 pulls in are XStatic packages
# whose setup.py imports a pkg_resources-declared namespace. Built without pip's wheel
# cache, all four fail under setuptools 82.0.0 with "No module named 'pkg_resources'"
# and build under 81.0.0.
#
# Below 80 was a second ceiling until 81.0.0 was needed: the jaraco.context and wheel
# that setuptools vendors carried known vulnerabilities up to 80.x, and 81.0.0 is the
# first to vendor fixed releases. What 80 and 81 removed is the easy_install command and
# module, package_index, the sandbox and setup.py's --dry-run; `setup.py install` itself
# is only deprecated. Nothing uses any of them: ceph's bindings build in their own venv
# with `pip wheel` (see core/ceph/ceph.mk), skyline moved to `pip install` too, #636
# turned the last four dashboards from a git clone into a pinned pip install, and no
# package in this venv imports the removed modules.
#
# The number is the newest release below 82: 81.0.0. Python 3.12 sets a floor rather
# than a ceiling -- it removed pkgutil.ImpImporter, which pkg_resources references
# unconditionally before setuptools 66.1 -- and 81.0.0 clears it.

# install the openstack cli inside the python 3.12 virtual environment
#
# /usr/bin/openstack was the python3-openstackclient rpm, so it ran as
# `#!/usr/bin/python3` (3.9). That shebang is what pinned half a dozen osc plugins
# to the system python: a plugin is an [openstack.cli.extension] stevedore entry
# point, and entry points are only visible to the interpreter they were installed
# under, so the copies pip put in a venv were invisible to the cli and every plugin
# had to be held in 3.9 as well -- as an rpm (designate, heat, manila, octavia) or as
# a second pip install (cyborg and watcher). #609 moved the cli into the
# antelope venv and every plugin followed it there; #636 moved it into the caracal
# venv and #662 into the epoxy one, and the plugins followed it each time.
#
# Every move is the same mechanism, so the same rule decides where each plugin goes:
# next to whichever interpreter runs /usr/bin/openstack. Each component installs its
# own -- see core/{heat,manila,octavia,designate,masakari,watcher,cyborg,barbican,
# ironic}, and core/nova for osc-placement.
#
# Measured on jim-1cc: 977 commands under the 3.9 cli against 1574 under the antelope
# one, because a venv resolves plugins 3.9 never had -- `openstack baremetal ...`
# among them, which used to fall through to osc's did-you-mean list.
#
# No version is pinned. python-openstackclient is a client, so
# os-epoxy-pip-upper-constraints.txt already carries it (7.5.1) and naming it again
# here could only drift from that file. This block has to stay below the epoxy venv
# bootstrap above: double-colon rules run in file order.
#
# The rpm also owned /usr/bin/openstack-3, the Fedora python3 alias. Nothing in this
# tree calls it and no other venv console script is aliased that way, so it is not
# recreated.
rootfs_install::
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_PIP_INSTALL) \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-openstackclient
	$(Q)# Link the cli. hex_sdk reaches it by absolute path ($$OPENSTACK in
	$(Q)# core/sdk_sh/modules.pre/sdk_01-var-static.sh is /usr/bin/openstack), so
	$(Q)# this symlink is what carries every caller over.
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/openstack /usr/bin/openstack

# Allow admin to be sudoers
rootfs_install::
	$(Q)mkdir -p $(ROOTDIR)/etc/sudoers.d
	$(Q)echo "admin ALL=(root) NOPASSWD: ALL" > $(ROOTDIR)/etc/sudoers.d/admin

# The advisor console account escalates through sudo so that it is logged.
# hex_cli is setuid root and world-executable, so withholding sudo would not
# confine the account -- it would only remove the auditable path.
rootfs_install::
	$(Q)mkdir -p $(ROOTDIR)/etc/sudoers.d
	$(Q)echo "advisor ALL=(root) NOPASSWD: ALL" > $(ROOTDIR)/etc/sudoers.d/advisor

# Default systemd service stop timeout
rootfs_install::
	$(Q)sed -i 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=90s/' $(ROOTDIR)/etc/systemd/system.conf
	$(Q)sed -i 's/#DefaultTimeoutStartSec.*/DefaultTimeoutStartSec=300s/' $(ROOTDIR)/etc/systemd/system.conf
	# $(Q)find  $(ROOTDIR)/usr/lib/systemd/system/ -type f | grep -v crpytsetup.slice | xargs sed -i "s/^TimeoutStopSec.*//"
	$(Q)chroot $(ROOTDIR) systemctl mask systemd-journal-flush

# Bond aggregator watchdog. Installed with no extension: cron.d ignores files
# whose names contain a dot.
rootfs_install::
	$(Q)mkdir -p $(ROOTDIR)/etc/cron.d
	$(Q)cp -f $(TOP_SRCDIR)/core/heavyfs/bond_watchdog.cron $(ROOTDIR)/etc/cron.d/bond_watchdog
	$(Q)chmod 0644 $(ROOTDIR)/etc/cron.d/bond_watchdog

# Disable USB storage drivers
rootfs_install::
	$(Q)echo "blacklist uas" >> $(ROOTDIR)/etc/modprobe.d/usb.conf
	$(Q)echo "blacklist usb_storage" >> $(ROOTDIR)/etc/modprobe.d/usb.conf
	$(Q)echo "install usb_storage /bin/true" >> $(ROOTDIR)/etc/modprobe.d/usb.conf

# note: skyline went first when it did not follow the constraints the rest of the rootfs
# did. It follows the epoxy ones like every service now (#668), and the packages it caps
# -- fastapi, pydantic, starlette, uvicorn, loguru -- are ones nothing else in that venv
# installs, so its place in this list no longer matters.
HEAVY_COMPONENTS += nvidia
HEAVY_COMPONENTS += yq api ui skyline nginx
HEAVY_COMPONENTS += mysql mongodb ntp rabbitmq memcache etcd ceph pacemaker haproxy grafana
HEAVY_COMPONENTS += influxdb prometheus thanos exporters kapacitor elk telegraf kafka keystone glance nova ironic neutron cinder swift multipath
# note: horizon goes last so its collectstatic/compress sees the dashboard plugins
# that designate, masakari and watcher drop into local/enabled at install time.
# RPM-installed plugins (heat, octavia, ironic, manila) land theirs in the dnf
# phase and are collected either way; the source-installed ones are not.
HEAVY_COMPONENTS += heat octavia barbican manila designate masakari watcher cyborg horizon
HEAVY_COMPONENTS += terraform docker k3s keycloak rancher appfw appctl lachesis

include $(shell for m in $(HEAVY_COMPONENTS); do ls $(COREDIR)/$$m/$$m.mk; done)
$(shell for r in $(LOCKED_DNF); do echo $$r >> $(LOCKED_RPMS); done)
$(shell for r in $(BLKLST_DNF); do echo $$r >> $(BLKLST_RPMS); done)
# Every rpm installdnf installs must carry a signature that verifies against a key a component
# pins, GPGKEY_DNF's '<key file> <fingerprint>' pairs, or have the sha256 PINNED_DNF's
# '<sha256> <rpm file name>' pairs give it (hex's scripts/importrpmkeys and scripts/checkrpms).
# Only inside the rootfs: the parse outside it has no ROOTDIR.
ifneq ($(ROOTDIR),)
$(shell printf '%s %s\n' $(GPGKEY_DNF) >> $(RPM_KEYS))
$(shell printf '%s %s\n' $(PINNED_DNF) >> $(PINNED_RPMS))
endif

# Every component's rootfs_install has run by now, so the last openstack venv install
# is behind us: drop uv and its cache before they ship.
rootfs_install::
	$(Q)rm -rf $(ROOTDIR)$(OPENSTACK_UV_HOME)

# And every dnf: the keyring holds only keys that hex or a component pins. Checked again after the
# second pass (below), whose dnf installs pull their dependencies from the repositories.
rootfs_install::
	$(Q)$(IMPORT_RPM_KEYS) -c $(ROOTDIR) $(RPM_KEYS)

heavy_components_install::
	$(Q)$(IMPORT_RPM_KEYS) -c $(ROOTDIR) $(RPM_KEYS)

# Component artifacts baked into the rootfs — prereqs so a component rebuild
# forces a rootfs rebuild (with touch $@ below). Scoped to HEAVY_COMPONENTS, not
# core/main (circular). Not covered: remote dnf/pip + bare-binary/dir deliverables.
HEAVY_DELIVERABLES := $(wildcard $(foreach m,$(HEAVY_COMPONENTS),$(TOP_BLDDIR)/core/$(m)/*.rpm $(TOP_BLDDIR)/core/$(m)/*.tgz))
# the offline registry is a directory; its stamp is rewritten after every successful copy
HEAVY_DELIVERABLES += $(wildcard $(TOP_BLDDIR)/core/docker/.registry-copied)

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
# NOTE: heavy_rootfs is built in two passes, so that most of it is built while the
# components heavyfs comes after are still building.
#
# heavy_base runs every rootfs_install fragment, and none of those reads another
# component's build output. That is what lets core/Makefile's heavy_overlap start it
# alongside those components instead of after them. heavy_rootfs then runs the
# heavy_components_install fragments -- the ones that do read that output (yq, api,
# ui, etcd, exporters, terraform, docker, k3s, keycloak, rancher, appfw, appctl,
# lachesis), in include order -- on top of heavy_base. A new fragment that reads
# $(TOP_BLDDIR) belongs in heavy_components_install: as rootfs_install it would race
# the component that produces the file, and fail or pick up a stale copy.
#
# mountrootfs moves heavy_base into heavy_rootfs rather than copying it, so after a
# build heavy_base is gone. .SECONDARY tells make that is expected: a missing
# heavy_base is rebuilt only when heavy_rootfs has to be, which costs the same full
# rebuild a heavy_rootfs change always has.
#
# heavy_base runs in a private mount namespace because it overlaps hex's initramfs
# mountrootfs runs. Each of those starts with `umount proc`, which unmounts the most
# recently mounted proc on the system, and that would be heavy_base's. Without /proc,
# rpm closes fds one by one up to the container's 1G nofile limit before every
# scriptlet (about 2 minutes each), and the scriptlets themselves run without /proc.
#
# docker.mk's DOCKER_FLOAT_CHECK goes first, so that a docker package that has floated past the
# version docker.mk rebuilds stops the build before heavy_base is spent on it. A clean build has
# run it already, from docker_float_check below; this covers a rebuild of heavy_base alone.
$(HEAVY_BASE): $(HEX_FULL_ROOTFS) $(shell for m in $(HEAVY_COMPONENTS); do find $(COREDIR)/$$m -type f -name '*.mk' -o -name Makefile; done)
	$(Q)$(DOCKER_FLOAT_CHECK)
	$(call RUN_CMD_TIMED, unshare -m --propagation private $(SHELL) $(HEX_SCRIPTSDIR)/mountrootfs -s -D '$(MAKECMD) ROOTFS_DNF_NOARCH_P1="$(ROOTFS_DNF_NOARCH_P1)" ROOTFS_DNF_DL_FROM="$(ROOTFS_DNF_DL_FROM)" ROOTFS_DNF="$(addsuffix .x86_64,$(ROOTFS_DNF)) $(ROOTFS_DNF_NOARCH)" ROOTFS_PIP="$(ROOTFS_PIP)" ROOTFS_PIP_NC="$(ROOTFS_PIP_NC)" ROOTFS_PIP_DL_FROM="$(ROOTFS_PIP_DL_FROM)" ROOTDIR=@ROOTDIR@ PROJ_BUILD_LABEL="heavyfs" rootfs_install' $< $@, "  GEN     $@")
	$(Q)touch $@

# A rebuild after a build finds heavy_base gone (moved into heavy_rootfs); rebuild it
# first, or the components would be layered onto nothing.
$(HEAVYFS): $(HEAVY_BASE) $(HEAVY_DELIVERABLES)
	$(Q)[ -d $(HEAVY_BASE) ] || { rm -rf $@ && $(MAKE) $(HEAVY_BASE); }
	$(call RUN_CMD_TIMED, $(SHELL) $(HEX_SCRIPTSDIR)/mountrootfs -s -D '$(MAKECMD) ROOTDIR=@ROOTDIR@ PROJ_BUILD_LABEL="heavyfs" heavy_components_install' $< $@, "  GEN     $@")
	$(Q)touch $@

.SECONDARY: $(HEAVY_BASE)

# For core/Makefile's heavy_overlap: build heavy_base early, but only when there is
# no heavy_rootfs yet, i.e. on a clean build. Anything else is left to the rule
# above, so a rebuild with nothing changed stays a no-op.
.PHONY: heavy_base_early
heavy_base_early:
	$(Q)[ -e $(HEAVYFS) ] || $(MAKE) $(HEAVY_BASE)

# For the top Makefile's critical_overlap, which runs it before anything else, on heavy_base_early's
# condition: a failure inside the overlap waits for both of its lines to finish.
.PHONY: docker_float_check
docker_float_check:
	$(Q)[ -e $(HEAVYFS) ] || { $(DOCKER_FLOAT_CHECK) ; }
endif

# openstacksdk 4.4.1, epoxy's pin and the cli's dependency, sends server create's
# hypervisor_hostname under its response name, OS-EXT-SRV-ATTR:hypervisor_hostname,
# and nova's 2.74 schema rejects that with a 400. osc 7 creates servers through the
# sdk where 6.6.1 went through novaclient, so since the cli moved to epoxy every
# `server create --hypervisor-hostname` has failed, hex_sdk's diagnostics server
# launch among them (prod #757). Upstream fixed it in 7fe116e19 (4.19.0); this carries
# that hunk as a .patch against the pristine 4.4.1 file beside it -- per file, not the
# whole-tree copy the note at the top retired. It sits below the component include
# because appfw and nova pip-install openstacksdk too. Once the constraints reach
# 4.19.0 the hunk is already there, patch --forward exits 1 and the build stops: drop
# this block and core/heavyfs/epoxy_patch/openstack then.
OPENSTACKSDK_SRCDIR := $(ROOTDIR)$(OPENSTACK_HOME_DIR)/lib/python$(PYTHON_VER)/site-packages
OPENSTACKSDK_PATCHDIR := $(COREDIR)/heavyfs/$(OPENSTACK_RELEASE)_patch

rootfs_install::
	$(Q)patch --forward --no-backup-if-mismatch -r - $(OPENSTACKSDK_SRCDIR)/openstack/compute/v2/server.py \
		< $(OPENSTACKSDK_PATCHDIR)/openstack/compute/v2/server.py.patch

# Tab completion for the openstack cli. The python3-openstackclient rpm wrote
# /etc/bash_completion.d/osc.bash_completion from its %post, so the file was never
# packaged and the pip install that replaced the rpm writes nothing (#1611). This
# generates it the way the rpm did, sed included -- it drops anything printed ahead
# of the function -- and has to sit below the component include: `openstack
# complete` lists only the commands of the plugins it can see, and heat, octavia,
# manila, designate and the rest install theirs there. It goes in bash-completion's
# own directory, named for the command, so it loads on the first TAB rather than
# being sourced into every interactive shell. pipefail makes a cli that cannot
# start fail the build instead of leaving an empty file.
rootfs_install::
	$(Q)chroot $(ROOTDIR) bash -c "set -o pipefail && /usr/bin/openstack complete | \
		sed -n '/_openstack/,\$$p' > /usr/share/bash-completion/completions/openstack"

# /var/update should work irrespective of a functioning cephfs mount
rootfs_install::
	$(Q)umount $(ROOTDIR)/proc || /bin/true
	$(Q)chroot $(ROOTDIR) sh -c "mkdir -p /mnt/cephfs/update"
	$(Q)chroot $(ROOTDIR) sh -c "rm -rf /var/update ; ln -sf /mnt/cephfs/update /var/update"

PKGCLEAN += $(HEAVYFS) $(HEAVY_BASE) $(RPMS_DIR) $(PIPS_DIR) $(ARCS_DIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
