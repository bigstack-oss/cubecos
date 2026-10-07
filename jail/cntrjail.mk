Q	      := @
DOCKER_BIN    := docker
DOCKER_REG    := localhost:5000
DOCKER_FLG    := --privileged --cgroupns=host -it -d --tmpfs=/tmp:exec -v /dev/dri:/dev/dri -v /var/run/dbus:/var/run/dbus --shm-size="1024m" -v /etc/localtime:/etc/localtime:ro
DOCKER_SOC    := /var/run/docker.sock
# Optional git config fragment, mounted read-only as the container's *system* config
# (/etc/gitconfig). Empty by default, so a normal developer build is unaffected.
#
# It exists so a CI runner can supply `url.<mirror>.insteadOf https://github.com/` from outside
# this repo, without any internal hostname being committed here. /etc/gitconfig rather than
# /root/.gitconfig deliberately: git reads system config first and global second, so the image's
# own /root/.gitconfig (jail/centos9/root/.gitconfig, which carries the safe.directory entries)
# still applies, and the `git config --global --add safe.directory` below still writes to the
# container's own file instead of scribbling on the host's.
#
# Was `~/.gitconfig:/root/.gitconfig` and never referenced by anything; mounting a developer's
# personal config over the image's would have dropped those safe.directory entries.
DOCKER_GITCFG ?=
DOCKER_GITCFG_FLG := $(if $(DOCKER_GITCFG),-v $(DOCKER_GITCFG):/etc/gitconfig:ro,)
DOCKER_EXTRA  :=
TOP_SRCDIR    := $(shell pwd -L)
TOP_DIR       := $(shell TOP_SRCDIR=$(TOP_SRCDIR); if [ -e /home/jenkins/workspace ]; then echo /home ; else echo $${TOP_SRCDIR%/*} ; fi)
TOP_JAILDIR   := $(TOP_SRCDIR)/jail
IGNORE_ERR    := > /dev/null 2>&1 || true
TOP_WORKDIR   := $(shell if [ -e /home/jenkins/workspace ]; then echo /home ; else echo /root/workspace ; fi)
WEAK_DEP      ?= 0
IPT_LEGACY    ?= 0
PROJECT       ?= centos9-jail
# Go module and build caches and pip's cache, kept on the host under JAIL_CACHE/<PROJECT> so they
# survive a jail rebuild and stay off the disk holding docker's data. Inside the container they sat
# in its writable layer under /var/lib/docker: 13 to 19 GiB per jail on bldsrv-200-13, fetched
# again after every rebuild. One directory per PROJECT, so jails of different jobs never share a
# cache. Set only on a Jenkins build host, the same test TOP_DIR uses; elsewhere the caches stay in
# the container. The image itself puts nothing in these paths but pip's own download cache.
JAIL_CACHE    ?= $(shell if [ -e /home/jenkins/workspace ]; then echo /home/jenkins/cache ; fi)
JAIL_CACHE_FLG = $(if $(JAIL_CACHE),-v $(JAIL_CACHE)/$${PROJECT:-$@}/go:/root/go -v $(JAIL_CACHE)/$${PROJECT:-$@}/go-build:/root/.cache/go-build -v $(JAIL_CACHE)/$${PROJECT:-$@}/pip:/root/.cache/pip,)

include hex/make/devtools_definitions.mk

.PHONY: help
help::
	$(Q)echo "PROJECT=XXXX centos9-jail     Create CentOS9 jail"
	$(Q)echo "PROJECT=XXXX enter            Configure and enter jail"
	$(Q)echo "clean-all-cntr                Clean all running containers"
	$(Q)echo "[ALL=1] docker-prune          Prune build cache unused for BUILD_CACHE_KEEP (default 168h), dangling images and anonymous volumes (ALL=1: all build cache, every unused image and volume)"
	$(Q)echo "[DRY=1] jenkins-ws-prune      Remove Jenkins ws-cleanup leftovers older than WS_PRUNE_DAYS (default 1)"

centos9-jail: $(TOP_JAILDIR)/jail.ubi9.dockerfile ubi9-base
	$(Q)$(DOCKER_BIN) rm -vf $${PROJECT:-$@} $(IGNORE_ERR)
	$(Q)sudo rm -rf $(TOP_SRCDIR)/../$${PROJECT:-$(@F)}
	$(Q)cp $(TOP_SRCDIR)/core/horizon/theme/static/images/cube-icon.png $(TOP_JAILDIR)/vnc/
	$(Q)DOCKER_BUILDKIT=1 $(DOCKER_BIN) build $(DOCKER_BLD_FLG) --progress=plain --build-arg BLDDIR=$${BLDDIR:-/root/workspace/$${PROJECT:-$(@F)}} --build-arg PASSPHRASE=$(PASSPHRASE) --build-arg PRIVATE_PEM=$(PRIVATE_PEM) --build-arg PUBLIC_PEM=$(PUBLIC_PEM) --build-arg DIST=$(subst -jail,,$@) --build-arg WEAK_DEP=$(WEAK_DEP) --build-arg IPT_LEGACY=$(IPT_LEGACY) -t $(DOCKER_REG)/$(@F) -f $< $(TOP_JAILDIR) # --target tier1
	$(Q)$(DOCKER_BIN) run -P $(DOCKER_FLG) -h $@ --name $${PROJECT:-$@} -e PROJECT=$${PROJECT:-$@} -v $(TOP_DIR):$(TOP_WORKDIR) -v /usr/lib/modules/$$(uname -r):/usr/lib/modules/$$(uname -r) $(JAIL_CACHE_FLG) $(DOCKER_GITCFG_FLG) $(DOCKER_EXTRA) $(DOCKER_REG)/$@
	$(Q)$(DOCKER_BIN) exec $${PROJECT:-$(filter centos%-jail,$(MAKECMDGOALS))} bash -c "git config --global --add safe.directory \$${PWD%/*}/cubecos"
	$(Q)rm -f $(TOP_JAILDIR)/vnc/cube-icon.png

ubi9-base: _ubi9_base jail/ubi9.tar.gz
	$(Q)echo "check image tech details from quay.io/centos/centos:stream9"

jail/ubi9.tar.gz:
	$(Q)UBI9_ID=$$($(DOCKER_BIN) run -d quay.io/centos/centos:stream9 /usr/bin/true) ; $(DOCKER_BIN) export $$UBI9_ID | pigz -9 > $@ ; $(DOCKER_BIN) rm -f $$UBI9_ID

_ubi9_base:
	$(Q)$(DOCKER_BIN) pull registry.access.redhat.com/ubi9/ubi:latest | grep "Image is up to date" || rm -f jail/ubi9.tar.gz

.PHONY: squid
squid:
	$(Q)docker ps | grep -q $@ || docker rm -vf $@ $(IGNORE_ERR)
	$(Q)docker run $(DOCKER_FLG) --name $@ -p 3128:3128 -v $(TOP_JAILDIR)/squid.conf:/etc/squid/squid.conf ubuntu/squid:latest

.PHONY: openvas
openvas:
	$(Q)docker ps | grep -q $@ || docker rm -vf $@ $(IGNORE_ERR)
	$(Q)docker run $(DOCKER_FLG) --name $@ -p 8833:443 -e OV_PASSWORD=bigstackcoltd atomicorp/openvas

.PHONY: nessus
nessus:
	$(Q)docker ps | grep -q $@ || docker rm -vf $@ $(IGNORE_ERR)
	$(Q)docker run $(DOCKER_FLG) --name $@ -p 8834:8834 -e PASSWORD=bigstackcoltd -e ACTIVATION_CODE=6ZHF-N26L-JWXX-S59T tenable/nessus:latest-ubuntu

.PHONY: clean-jail
clean-jail:
	$(Q)docker rm -vf $(PROJECT) $(IGNORE_ERR)

.PHONY: clean-all-cntr
clean-all-cntr:
	$(Q)docker rm -vf `docker ps -qa` $(IGNORE_ERR)
	$(Q)docker volume prune -f

# Reports the space it freed on the disk holding docker's data, which on a build server is not
# necessarily the one holding TOP_DIR. Each prune runs even if the one before it fails.
#
# Build cache used within BUILD_CACHE_KEEP survives, so the next jail build still hits it. With
# -a and no filter every run emptied the cache, the jail rebuilt with no step cached (807 s
# instead of ~30 s on bldsrv-200-13 #85) and pushed ~3 GB of new layers to the local registry,
# which nothing garbage-collects. BuildKit times `until` from when an entry was last used, not
# created. ALL=1 still empties it.
BUILD_CACHE_KEEP ?= 168h

.PHONY: docker-prune
docker-prune:
	$(Q)R=$$($(DOCKER_BIN) info -f '{{.DockerRootDir}}') ; \
	B=$$(df --output=avail -B1M $$R | tail -1) ; \
	echo "== before ==" ; df -h $$R | tail -1 ; $(DOCKER_BIN) system df ; \
	$(DOCKER_BIN) builder prune -a -f $(if $(ALL),,--filter until=$(BUILD_CACHE_KEEP)) ; \
	$(DOCKER_BIN) image prune $(if $(ALL),-a) -f ; \
	$(DOCKER_BIN) volume prune $(if $(ALL),-a) -f ; \
	echo "== after ==" ; df -h $$R | tail -1 ; $(DOCKER_BIN) system df ; \
	A=$$(df --output=avail -B1M $$R | tail -1) ; \
	awk -v a=$$A -v b=$$B -v r=$$R 'BEGIN { printf "freed on %s: %.1f GiB (%.1f GiB free -> %.1f GiB free)\n", r, (a - b) / 1024, b / 1024, a / 1024 }'

# Jenkins' Workspace Cleanup plugin renames a finished workspace to <name>_ws-cleanup_<epoch ms>
# and deletes it in the background, as the jenkins user. Builds that run as root in a container
# leave root-owned files behind (cubecmp's node_modules, .next, charts), so that delete fails and
# the renamed copy stays forever. Remove those copies once they are older than WS_PRUNE_DAYS --
# nothing references them -- and never the live workspaces, which other jobs read by path.
# DRY=1 lists them without deleting.
JENKINS_WS    ?= /home/jenkins/workspace
WS_PRUNE_DAYS ?= 1

.PHONY: jenkins-ws-prune
jenkins-ws-prune:
	$(Q)W=$(JENKINS_WS) ; \
	[ -d "$$W" ] || { echo "no Jenkins workspace at $$W: nothing to do" ; exit 0 ; } ; \
	L=$$(find "$$W" -mindepth 1 -maxdepth 1 -type d -regextype posix-extended -regex '.*_ws-cleanup_[0-9]+' -mmin +$$(( $(WS_PRUNE_DAYS) * 1440 ))) ; \
	echo "$$(echo "$$L" | grep -c .) ws-cleanup leftovers older than $(WS_PRUNE_DAYS) day(s) in $$W" ; \
	[ -n "$$L" ] || exit 0 ; \
	if [ -n "$(DRY)" ] ; then echo "$$L" ; exit 0 ; fi ; \
	B=$$(df --output=avail -B1M "$$W" | tail -1) ; \
	echo "== before ==" ; df -h "$$W" | tail -1 ; \
	echo "$$L" | grep . | xargs -r -d '\n' sudo -n rm -rf -- ; \
	echo "== after ==" ; df -h "$$W" | tail -1 ; \
	A=$$(df --output=avail -B1M "$$W" | tail -1) ; \
	awk -v a=$$A -v b=$$B -v r="$$W" 'BEGIN { printf "freed on %s: %.1f GiB (%.1f GiB free -> %.1f GiB free)\n", r, (a - b) / 1024, b / 1024, a / 1024 }'

.PHONY: enter
enter:
	$(Q)$(DOCKER_BIN) start $(PROJECT) $(IGNORE_ERR)
	$(Q)$(DOCKER_BIN) exec $(PROJECT) sed -i '/^#/! s/^/#/' /root/.bash_env
	$(Q)$(DOCKER_BIN) exec -ti $(PROJECT) bash -c "../cubecos/hex/configure; bash"
