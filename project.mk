# Core SDK

# support directory
COREDIR := $(TOP_SRCDIR)/core
CORE_MAINDIR  := $(COREDIR)/main

# core deliverables
CORE_SHIPDIR  := $(TOP_BLDDIR)/core/main/ship
CORE_USB      := $(CORE_SHIPDIR)/../proj.img
CORE_LIVE_USB := $(CORE_SHIPDIR)/../live_proj.img
CORE_PXE      := $(CORE_SHIPDIR)/../proj.pxe.tgz
CORE_PKGDIR   := $(COREDIR)/pkg

# core specific modules
PROJ_MODDIR := $(TOP_BLDDIR)/core/modules

# Node config namespace: the installer (hex) drops the phone-home agent's env
# file here (overrides hex's default).
HEX_AGENT_ENV_DIR := /etc/cube

# The release signer every CubeCOS system checks its next firmware update against (hex's
# projsign.mk installs cosign, Sigstore's trusted root and hex_verify_update into the rootfs, and
# writes these to /etc/settings.sys). They must be the identity the publish job signs releases as
# -- COSIGN_IDENTITY and COSIGN_OIDC_ISSUER in triangle/jenkins/cube_publish.groovy -- or every
# signed update will be refused. Changing them only takes effect for updates *from* a release
# built with the new values.
PROJ_UPDATE_SIGNER_IDENTITY := share@bigstack.co
PROJ_UPDATE_SIGNER_ISSUER := https://github.com/login/oauth

# policy source tree
CORE_POLICYDIR := $(COREDIR)/policies

# Base URL for GitHub *release assets* (the `/<org>/<repo>/releases/download/...` objects we
# wget, not the git remotes we clone).
#
# It is a variable, and only a variable, because those two surfaces have very different
# throughput. Release assets and git-LFS objects are served from GitHub's object CDN, and that
# path has been shaped to ~40-70 KB/s from our build network for weeks -- a 16 MB exporter
# tarball takes ~400s -- while `git clone` against github.com itself still runs at ~2 MB/s.
# Authenticating does not lift it, so it is path shaping rather than an account rate limit and a
# token is not the answer. Measured 2026-09-23 against builds #743/#747/#748/#750, see
# cubecos#1350.
#
# The default is the public host, so a clean checkout builds exactly as it always has and nothing
# here needs to change for anyone outside our CI. A build that has a mirror available overrides it
# from the environment -- like RC and FW_VER, this is never assigned anywhere in this repo, so no
# internal hostname is committed here.
#
# Deliberately NOT used for the `git clone` URLs: git transport is not the bottleneck, and
# rewriting clone remotes would need `url.insteadOf` instead of a URL variable anyway.
GITHUB_DL_BASE ?= https://github.com

# The same idea for every other upstream we fetch binaries from, one variable each rather than a
# single switch. Throttling has shown up on one host at a time -- github.com's object CDN and
# registry.k8s.io, while quay.io and artifacts.opensearch.org stayed fast -- so the useful unit is
# per-host. These carry the scheme+host only; the path and version stay with the component that
# owns them, so a mirror is configured without teaching the CI repo our version numbers.
#
# All default to the public host: unset, the build is byte-identical to what it has always done.
# Routing one of them is a decision to make on evidence, and the evidence is a throughput
# measurement of that host, not a hunch -- the mirror serves cached objects at a few MB/s, which
# is *slower* than several of these upstreams when they are healthy.
APACHE_DL_HOST   ?= https://archive.apache.org
MARIADB_DL_HOST  ?= https://archive.mariadb.org
ELASTIC_DL_HOST  ?= https://artifacts.elastic.co
KOJIHUB_DL_HOST  ?= https://kojihub.stream.centos.org
CBS_DL_HOST      ?= https://cbs.centos.org
# Serves the pinned .gem files that core/elk/elk.mk installs the logstash plugins from.
RUBYGEMS_DL_HOST ?= https://rubygems.org

# PyPI index. Empty by default, so pip resolves against pypi.org exactly as before.
#
# Exported as an environment variable rather than written as a pip.conf into $(ROOTDIR),
# deliberately: most pip installs in this tree run as `chroot $(ROOTDIR) ... pip install`, chroot
# inherits the environment, and one export therefore reaches every one of them -- the ~40 openstack
# service installs, the venv bootstraps, and the ceph binding build -- while leaving nothing inside
# the image that would have to be scrubbed before packing. A pip.conf under $(ROOTDIR)/etc would
# ship; cube-post.mk's guard would catch it, but not creating it is better than catching it.
#
# It also reaches pip's PEP-517 build isolation, which resolves the build backend from the live
# index and ignores `-c` (see the NOTE in core/heavyfs/Makefile) -- the one place a constraint file
# cannot help.
#
# files.pythonhosted.org measured 148 KB/s from the build network on 2026-09-24 against 1.81 MB/s
# for the same wheel from a warm mirror, so this is worth routing. Note the mirror is a
# pull-through proxy: a package it has not seen is fetched from that same slow upstream, so the
# first build after pointing this at a mirror is no faster than before.
PIP_INDEX_URL ?=
PIP_TRUSTED_HOST ?=
ifneq ($(PIP_INDEX_URL),)
export PIP_INDEX_URL
ifneq ($(PIP_TRUSTED_HOST),)
export PIP_TRUSTED_HOST
endif
endif

# cubecos shared build envs
PROJ_NFS_SERVER := 10.32.0.200
PROJ_NFS_CUBECOS_PATH := /volume1/bigstack/cube-images
PROJ_NFS_OPENSTACK_PATH := /volume1/docker/minio/downloads
PROJ_NFS_PATH := /volume1/pxe-server

PROJ_TEST_EXPORTS := "PS4=+[\\t]"

# openstack version
OPENSTACK_RELEASE := epoxy
OPENSTACK_HOME_DIR := /opt/openstack-$(OPENSTACK_RELEASE)
OPS_GITHUB_BRANCH_01 := stable/2025.1
OPS_GITHUB_BRANCH_02 := unmaintained/2025.1
PYTHON_VER := 3.12
PYTHON_PATCH_VER := 3.12.14
OPENSTACK_PIP_CONSTRAINT ?= $(COREDIR)/heavyfs/os-$(OPENSTACK_RELEASE)-pip-upper-constraints.txt
OPENSTACK_INSTALLED_PIP_CONSTRAINT := $(OPENSTACK_HOME_DIR)/os-$(OPENSTACK_RELEASE)-pip-upper-constraints.txt

# The system python 3.9 pip constraint, for the ROOTFS_PIP installs in core/heavyfs
# and friends. Deliberately NOT os-$(OPENSTACK_RELEASE)-pip-upper-constraints.txt any
# more: no openstack package is installed into the system python since the antelope
# migration, and this file has been maintained locally instead -- it carries the CVE
# pins the ROOTFS_PIP lines exist for (pillow 11.3.0, waitress 3.0.2, numpy 1.25.2,
# ansible-core, python-jose, numexpr, xmlsec), none of which the openstack constraint
# files have. Deriving it from the release name would have quietly downgraded pillow
# to 9.2.0 and waitress to 2.1.2 -- straight back into CVE-2023-50447 and
# CVE-2024-49768 -- the moment OPENSTACK_RELEASE moved to antelope, and the same
# holds for every hop after it. This pin does not follow the release name, ever.
PROJ_PIP_CONSTRAINT ?= $(COREDIR)/heavyfs/rootfs-pip-constraints.txt

# openstack next version -- left blank until the next hop, then filled in the way
# epoxy's were while it was NEXT_*: a second venv is built from these, components move
# into it one at a time, and the values are promoted above once the move is done.
NEXT_OPENSTACK_RELEASE :=
NEXT_OPENSTACK_HOME_DIR :=
NEXT_OPS_GITHUB_BRANCH_01 :=
NEXT_OPS_GITHUB_BRANCH_02 :=
NEXT_PYTHON_VER :=
NEXT_PYTHON_PATCH_VER :=
NEXT_OPENSTACK_PIP_CONSTRAINT ?=
NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT :=

# The epoxy hop is complete -- the block above IS epoxy (2025.1, the SLURP release
# after caracal) now, and there is no second runtime. /opt/openstack-epoxy was built
# alongside the caracal venv with a python of its own, 3.12 -- the newest runtime
# 2025.1 is tested on, and what #652 asked for -- and the services moved into it one
# at a time:
#
#   keystone 27.1.0 (#657), glance 30.2.0 (#656), cinder 26.3.0 (#655), nova with
#   placement 31.3.1 / 13.0.0 (#653), neutron 26.0.6 (#654), barbican 20.0.0 (#658),
#   cyborg 14.1.0 (#659), designate 20.0.2 (#660), heat 24.1.1 (#661), ironic with
#   ironic-inspector 29.1.0 / 12.4.0 (#663), manila 20.0.2 (#664), masakari with
#   masakari-monitors 19.1.0 / 19.0.0 (#665), octavia 16.1.0 (#667), watcher 14.1.2
#   (#670), horizon 25.3.2 (#662), and skyline (#668): upstream's skyline-apiserver
#   6.0.1 in place of our fork, and our skyline-console fork unchanged.
#
# #669 moved python-swiftclient (4.7.1) rather than a service, so it takes no place in
# that list.
#
# As on the caracal hop, every service hop left its osc plugin client behind beside
# /usr/bin/openstack -- a plugin is a stevedore entry point, visible only to the
# interpreter that runs the cli -- and horizon's hop (#662) collected them: horizon,
# the eight dashboard plugins, /usr/bin/openstack and its plugin clients moved together.
#
# What was left after the services was not a service: ospurge, moved into this venv by
# #652 -- which is what emptied the caracal venv, allowed its python 3.11 build to go,
# and let these values be promoted from NEXT_* into the block above. Nothing is left on
# 3.11.
#
# $(OPS_GITHUB_BRANCH_02) has no reader in this tree -- the four dashboard clones were
# the last, and #636 took them -- but $(OPS_GITHUB_BRANCH_01) is still what
# core/heavyfs passes to PROJ_INSTALL_PIP, so the pair is left intact. That -b only
# reaches the git clones installpip makes for ROOTFS_PIP_DL_FROM, and nothing in the
# tree sets ROOTFS_PIP_DL_FROM, so the branch is effectively unused there too; it is
# kept because the next hop will want the pair.
