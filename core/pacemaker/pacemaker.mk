# Cube SDK
# pacemaker installation

# pacemaker-2.1.8-1.el9 fails to start with info: Connection to CIB manager for crmd failed: Transport endpoint is not connnected
PACEMAKER_VER := 2.1.11-1.el9
PACEMAKER_DNF := pacemaker-$(PACEMAKER_VER) pacemaker-remote-$(PACEMAKER_VER) pacemaker-cli-$(PACEMAKER_VER) pacemaker-cluster-libs-$(PACEMAKER_VER) pacemaker-libs-$(PACEMAKER_VER)
LOCKED_DNF += $(PACEMAKER_DNF) pacemaker-schemas-$(PACEMAKER_VER)
ROOTFS_DNF_NOARCH += pacemaker-schemas-$(PACEMAKER_VER)
ROOTFS_DNF += $(PACEMAKER_DNF) pcs fence-agents-all libqb

# pcs 0.11.12-2.el9, the newest Stream ships, bundles puma 8.0.1 in pcsd's own gem tree
# (GEM_HOME=/usr/lib64/pcsd/vendor/bundle, which pcsd-ruby.service sets), and puma 8.0.1 has known
# vulnerabilities fixed in 8.0.2. pcsd loads its gems from that tree by name, with no lockfile, and
# serves through puma by way of rackup, so 8.0.2 is installed there and 8.0.1 removed. puma's HTTP
# parser is a C extension, so the gem is built in the image against its own ruby, with ruby-devel,
# which core/main/cube-post.mk removes with every other -devel package; ruby's RbConfig flags are
# the hardened ones pcs's own build of puma used. The .gem is pinned by the digest rubygems.org
# publishes, as elk.mk's are.
#
# RHEL's rubygems has quirks this works around. It installs as root into /usr/local/share/gems
# whatever GEM_HOME says, so the tree is named with --install-dir, and the .gem copy it leaves in
# a cache/ the tree does not otherwise have is dropped. It does not resolve a --local install
# against the tree, so puma's one dependency, nio4r (~> 2.0), is not resolved: the tree carries
# the 2.7.5 pcs bundles. Its uninstall needs the tree and the system gems on GEM_PATH (it loads
# rdoc), leaves the build_info behind, and reports a gem it cannot find with status 0, so the
# rule checks for 8.0.1 itself, before and after: a pcs that stops bundling it fails here, the
# cue to revisit. `rpm -V pcs` reports 8.0.1 as missing.
#
# The gem commands run with make's MAKEFLAGS cleared. hex's recursion puts TARGET=<its own target>
# on make's command line, and MAKEFLAGS carries that into the make that builds the parser, where it
# overrides mkmf's TARGET: the parser came out as _full_r.so, not puma_http11.so, and pcsd-ruby
# could not start. The rule loads the parser afterwards, so a misbuilt one stops the build.
ROOTFS_DNF += ruby-devel
PCSD_GEM_HOME := /usr/lib64/pcsd/vendor/bundle
PCSD_GEM_ENV := env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL GEM_HOME=$(PCSD_GEM_HOME) GEM_PATH=$(PCSD_GEM_HOME):/usr/share/gems
PCSD_PUMA_VER := 8.0.2
PCSD_PUMA_OLD := 8.0.1
PCSD_PUMA_GEM := puma-$(PCSD_PUMA_VER).gem
PCSD_PUMA_SHA256 := c8ed871dfbbe66448ea9ffd46692342d9804d4071522b52b5331b7b6e7b686fb

$(ARCS_DIR)/$(PCSD_PUMA_GEM):
	$(Q)wget $(RUBYGEMS_DL_HOST)/downloads/$(PCSD_PUMA_GEM) -O $@.part
	$(Q)echo "$(PCSD_PUMA_SHA256)  $@.part" | sha256sum -c -
	$(Q)mv $@.part $@

rootfs_install:: $(ARCS_DIR)/$(PCSD_PUMA_GEM)
	$(Q)[ -d $(ROOTDIR)$(PCSD_GEM_HOME)/gems/puma-$(PCSD_PUMA_OLD) ] || \
		{ echo "pacemaker.mk: pcs no longer bundles puma $(PCSD_PUMA_OLD)" ; exit 1 ; }
	$(Q)cp -f $< $(ROOTDIR)/tmp/
	$(Q)chroot $(ROOTDIR) $(PCSD_GEM_ENV) gem install --install-dir $(PCSD_GEM_HOME) --local --no-document \
		--ignore-dependencies /tmp/$(PCSD_PUMA_GEM)
	$(Q)chroot $(ROOTDIR) $(PCSD_GEM_ENV) gem uninstall --install-dir $(PCSD_GEM_HOME) puma -v $(PCSD_PUMA_OLD)
	$(Q)rm -f $(ROOTDIR)/tmp/$(PCSD_PUMA_GEM) $(ROOTDIR)$(PCSD_GEM_HOME)/cache/$(PCSD_PUMA_GEM) \
		$(ROOTDIR)$(PCSD_GEM_HOME)/build_info/puma-$(PCSD_PUMA_OLD).info
	$(Q)rmdir $(ROOTDIR)$(PCSD_GEM_HOME)/cache
	$(Q)[ -z "$$(find $(ROOTDIR)$(PCSD_GEM_HOME) -name 'puma-$(PCSD_PUMA_OLD)*')" ] || \
		{ echo "pacemaker.mk: puma $(PCSD_PUMA_OLD) is still in $(PCSD_GEM_HOME)" ; exit 1 ; }
	$(Q)chroot $(ROOTDIR) $(PCSD_GEM_ENV) ruby -e 'gem "puma", "$(PCSD_PUMA_VER)" ; require "puma/puma_http11"' || \
		{ echo "pacemaker.mk: puma $(PCSD_PUMA_VER)'s parser does not load" ; exit 1 ; }

rootfs_install::
	$(Q)chroot $(ROOTDIR) systemctl disable rpcbind nfs-convert || true
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/pacemaker/vaw.service ./lib/systemd/system
	$(Q)$(INSTALL_SCRIPT) -f $(ROOTDIR) $(COREDIR)/pacemaker/vaw ./usr/sbin/vaw
