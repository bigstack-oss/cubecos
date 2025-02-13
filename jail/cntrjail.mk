Q	      := @
DOCKER_BIN    := docker
DOCKER_REG    := localhost:5000
DOCKER_FLG    := --privileged --cgroupns=host -it -d --tmpfs=/tmp:exec -v /dev/dri:/dev/dri -v /var/run/dbus:/var/run/dbus --shm-size="1024m" -v /etc/localtime:/etc/localtime:ro
DOCKER_SOC    := /var/run/docker.sock
DOCKER_GITCFG := ~/.gitconfig:/root/.gitconfig
DOCKER_EXTRA  :=
TOP_SRCDIR    := $(shell pwd -L)
TOP_DIR       := $(shell TOP_SRCDIR=$(TOP_SRCDIR); if [ -e /home/jenkins/workspace ]; then echo /home ; else echo $${TOP_SRCDIR%/*} ; fi)
TOP_JAILDIR   := $(TOP_SRCDIR)/jail
IGNORE_ERR    := > /dev/null 2>&1 || true
TOP_WORKDIR   := $(shell if [ -e /home/jenkins/workspace ]; then echo /home ; else echo /root/workspace ; fi)
WEAK_DEP      ?= 0
IPT_LEGACY    ?= 0
PROJECT       ?= centos9-jail

include hex/make/devtools_definitions.mk

centos9-jail: $(TOP_JAILDIR)/jail.ubi9.dockerfile ubi9-base
	$(Q)$(DOCKER_BIN) rm -vf $${PROJECT:-$@} $(IGNORE_ERR)
	$(Q)sudo rm -rf $(PWD)/../$${PROJECT:-$(@F)}
	$(Q)cp $(TOP_SRCDIR)/core/horizon/theme/static/images/cube-icon.png $(TOP_JAILDIR)/vnc/
	$(Q)DOCKER_BUILDKIT=1 $(DOCKER_BIN) build $(DOCKER_BLD_FLG) --progress=plain --build-arg BLDDIR=$${BLDDIR:-/root/workspace/$(@F)} --build-arg PASSPHRASE=$(PASSPHRASE) --build-arg PRIVATE_PEM=$(PRIVATE_PEM) --build-arg PUBLIC_PEM=$(PUBLIC_PEM) --build-arg DIST=$(subst -jail,,$@) --build-arg WEAK_DEP=$(WEAK_DEP) --build-arg IPT_LEGACY=$(IPT_LEGACY) -t $(DOCKER_REG)/$(@F) -f $< $(TOP_JAILDIR) # --target tier1
	$(Q)$(DOCKER_BIN) run -P $(DOCKER_FLG) -h $@ --name $${PROJECT:-$@} -e PROJECT=$${PROJECT:-$@} -v $(TOP_DIR):$(TOP_WORKDIR) -v /usr/lib/modules/$$(uname -r):/usr/lib/modules/$$(uname -r) $(DOCKER_EXTRA) $(DOCKER_REG)/$@
	$(Q)$(DOCKER_BIN) exec $${PROJECT:-$(filter centos%-jail,$(MAKECMDGOALS))} bash -c "git config --global --add safe.directory \$${PWD%/*}/cube"
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

.PHONY: clean-dangling-img
clean-dangling-img:
	$(Q)$(DOCKER_BIN) images | grep "<none>" | awk '{print $$3}' | xargs -i $(DOCKER_BIN) rmi {}

.PHONY: enter
enter:
	$(Q)$(DOCKER_BIN) start $(PROJECT) $(IGNORE_ERR)
	$(Q)$(DOCKER_BIN) exec -ti $(PROJECT) bash -c "../cube/hex/configure; bash"
