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
GOLANG_VERSION := 1.24.2
PROJ_NFS_SERVER := 10.32.0.200
PROJ_NFS_CUBECOS_PATH := /volume1/bigstack/cube-images
PROJ_NFS_OPENSTACK_PATH := /volume1/docker/minio/downloads
PROJ_NFS_PATH := /volume1/pxe-server

PROJ_TEST_EXPORTS := "PS4=+[\\t]"

# openstack version
OPENSTACK_RELEASE := caracal
OPENSTACK_HOME_DIR := /opt/openstack-$(OPENSTACK_RELEASE)
OPS_GITHUB_BRANCH_01 := stable/2024.1
OPS_GITHUB_BRANCH_02 := unmaintained/2024.1
PYTHON_VER := 3.11
PYTHON_PATCH_VER := 3.11.15
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

# openstack next version -- filled in the way antelope's were while it was NEXT_*: a
# second venv is built from these, components move into it one at a time, and the
# values are promoted above once the move is done.
#
# The next hop is epoxy (2025.1), the SLURP release after caracal. It gets its own
# python rather than sharing the caracal venv's 3.11: 3.12 is the newest runtime
# 2025.1 is tested on, and #652 moves CubeCOS to it. keystone (27.1.0) is the first
# occupant (#657), glance (30.2.0) the second (#656), cinder (26.3.0) the third (#655),
# nova with placement (31.3.1 / 13.0.0) the fourth (#653), neutron (26.0.6) the
# fifth (#654), barbican (20.0.0) the sixth (#658), cyborg (14.1.0) the seventh
# (#659) and designate (20.0.2) the eighth (#660).
NEXT_OPENSTACK_RELEASE := epoxy
NEXT_OPENSTACK_HOME_DIR := /opt/openstack-$(NEXT_OPENSTACK_RELEASE)
NEXT_OPS_GITHUB_BRANCH_01 := stable/2025.1
NEXT_OPS_GITHUB_BRANCH_02 := unmaintained/2025.1
NEXT_PYTHON_VER := 3.12
NEXT_PYTHON_PATCH_VER := 3.12.14
NEXT_OPENSTACK_PIP_CONSTRAINT ?= $(COREDIR)/heavyfs/os-$(NEXT_OPENSTACK_RELEASE)-pip-upper-constraints.txt
NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT := $(NEXT_OPENSTACK_HOME_DIR)/os-$(NEXT_OPENSTACK_RELEASE)-pip-upper-constraints.txt

# The caracal hop is complete -- the "openstack version" block IS caracal now, and the
# antelope runtime is gone. /opt/openstack-caracal on python 3.11 was built alongside
# the antelope venv so that caracal-era components would not drag their dependency
# versions into the 2023.1 services, and the services moved into it one at a time:
#
#   skyline (first, its forks branch off upstream master at 4.0.1 / 4.0.0.0rc1, i.e.
#   caracal rather than antelope), keystone 25.0.0 (#631), glance 28.2.0 (#630),
#   cinder 24.5.0 (#629), nova with placement 29.4.0 / 11.0.1 (#627),
#   neutron 24.2.2 (#628), manila 18.3.0 (#638), octavia 14.0.2 (#640),
#   barbican 18.0.0 (#632), cyborg 12.0.0 (#633), designate 18.0.0 (#634),
#   heat 22.0.1 (#635), ironic with ironic-inspector 24.1.5 / 12.1.1 (#637),
#   masakari with masakari-monitors 17.0.0 / 17.0.1 (#639), watcher 12.1.0 (#643)
#   and horizon 24.0.2 (#636), which took the eight dashboard plugins and the
#   openstack cli with it.
#
# The ordinals are merge order into develop; #642 moved python-swiftclient rather than
# a service, so it takes no place in that count.
#
# Several hops had to leave a piece behind: an osc plugin is a stevedore entry point,
# visible only to the interpreter that runs /usr/bin/openstack, so barbican, designate,
# masakari, octavia, watcher, cyborg, heat and manila each left their client in the
# antelope venv, and designate, masakari, watcher and neutron-vpnaas left their horizon
# dashboard plugin there too. #636 collected all of it: horizon, the eight dashboard
# plugins, /usr/bin/openstack and the eight clients moved together.
#
# What was left after the services was not a service at all: monasca, retired by #672
# phase 4, and ospurge, moved into this venv by #625 -- which is what emptied the
# antelope venv, allowed its python 3.10 build to go, and let these values be promoted
# from CARACAL_* into the block above. Nothing is left on 3.10.
#
# $(OPS_GITHUB_BRANCH_02) has no reader in this tree -- the four dashboard clones were
# the last, and #636 took them -- but $(OPS_GITHUB_BRANCH_01) is still what
# core/heavyfs passes to PROJ_INSTALL_PIP, so the pair is left intact. Note that the
# ROOTFS_PIP entries it applies to name their own refs, so the branch is effectively
# unused there too; it is kept because the next hop will want the pair.
