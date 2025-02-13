# CUBE SDK

ifndef ANSIBLE_HOST
ANSIBLE_HOST := 127.0.0.1
endif

ENV := SRCDIR=$(SRCDIR) BLDDIR=$(BLDDIR) ANSIBLE_HOST_KEY_CHECKING=False
ANSIBLE_CMD := $(ENV) ansible-playbook

ifneq ($(VERBOSE),0)
ANSIBLE_CMD := $(ANSIBLE_CMD) -vvvvv
endif

deploy_prepare:
	$(Q)cp $(SRCDIR)/ansible/staging.in $(BLDDIR)/staging
	$(Q)sed -i -e "s/@ANSIBLE_HOST@/$(ANSIBLE_HOST)/" $(BLDDIR)/staging

help::
	@echo "deploy       deploy changes to lmi and rproxy (env ANSIBLE_HOST)"

deploy: deploy_prepare
	$(Q)cd $(SRCDIR)/ansible && $(ANSIBLE_CMD) -i $(BLDDIR)/staging site.yml

help::
	@echo "deploy_lmi   deploy changes to lmi (env ANSIBLE_HOST)"

deploy_lmi: deploy_prepare
	$(Q)cd $(SRCDIR)/ansible && $(ANSIBLE_CMD) -i $(BLDDIR)/staging lmi.yml

help::
	@echo "deploy_rp    deploy changes to rproxy (env ANSIBLE_HOST)"

deploy_rp: deploy_prepare
	$(Q)cd $(SRCDIR)/ansible && $(ANSIBLE_CMD) -i $(BLDDIR)/staging rproxy.yml
