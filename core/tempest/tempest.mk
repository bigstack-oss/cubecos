TEMPEST_VERSIONS := $(SRCDIR)/versions/$(OPENSTACK_RELEASE).mk
ifeq ($(wildcard $(TEMPEST_VERSIONS)),)
$(error no Tempest pins for OPENSTACK_RELEASE=$(OPENSTACK_RELEASE): add core/tempest/versions/$(OPENSTACK_RELEASE).mk)
endif
include $(TEMPEST_VERSIONS)

TEMPEST_REGISTRY ?= localhost:5000
TEMPEST_IMAGE := $(TEMPEST_REGISTRY)/cube-tempest:$(OPENSTACK_RELEASE)-$(TEMPEST_VER)
TEMPEST_CTX := $(BLDDIR)/image
TEMPEST_FILES := Dockerfile tempest.conf.in exclude-cos.txt preflight.py render-conf.sh run.sh teardown.sh

SUITE ?= smoke
CONCURRENCY ?= 2
OUT ?= $(BLDDIR)/tempest-out/$(shell date +%Y%m%d-%H%M%S)

.PHONY: tempest_image tempest_test tempest_preflight
tempest_image:
	$(Q)rm -rf $(TEMPEST_CTX) && mkdir -p $(TEMPEST_CTX)
	$(Q)cp -r $(SRCDIR)/patches $(addprefix $(SRCDIR)/,$(TEMPEST_FILES)) $(TEMPEST_CTX)/
	$(Q)cp $(OPENSTACK_PIP_CONSTRAINT) $(TEMPEST_CTX)/constraints.txt
	$(Q)docker build -t $(TEMPEST_IMAGE) --build-arg TEMPEST_PIP="$(TEMPEST_PIP)" \
		--build-arg OPENSTACK_RELEASE=$(OPENSTACK_RELEASE) --build-arg TEMPEST_VER=$(TEMPEST_VER) $(TEMPEST_CTX)
	$(Q)if [ "$(PUSH)" = 1 ]; then docker push $(TEMPEST_IMAGE); fi

PREFLIGHT ?= 1

# preflight only: cluster check over ssh + the in-container resource checks for SUITE
tempest_preflight: PREFLIGHT_ONLY := 1
tempest_preflight tempest_test:
	$(Q)if [ -z "$(TARGET)" ]; then echo "==> ERROR: TARGET=<vip> is required"; exit 2; fi
	$(Q)docker image inspect $(TEMPEST_IMAGE) >/dev/null 2>&1 || docker pull $(TEMPEST_IMAGE) >/dev/null 2>&1 || \
		{ echo "==> ERROR: no $(TEMPEST_IMAGE): run make tempest_image"; exit 2; }
	$(Q)if [ "$(PREFLIGHT)" = 1 ]; then MIN_HOST_MEM_GB=$(MIN_HOST_MEM_GB) $(SRCDIR)/cluster-check.sh $(TARGET) || exit 3; fi
	$(Q)mkdir -p $(OUT) && chmod 700 $(OUT)
	$(Q)env=$(OUT)/.creds.env; trap 'rm -f '$$env EXIT INT TERM; \
		$(SRCDIR)/creds.sh $(TARGET) $$env || exit 2; \
		docker run --rm --network host --env-file $$env -e VIP=$(TARGET) -e SUITE=$(SUITE) \
			-e REGEX='$(REGEX)' -e CONCURRENCY=$(CONCURRENCY) -e MIN_FIPS=$(MIN_FIPS) \
			-e PREFLIGHT=$(PREFLIGHT) -e PREFLIGHT_ONLY=$(PREFLIGHT_ONLY) -v $(OUT):/work/out $(TEMPEST_IMAGE); \
		rc=$$?; [ "$(PREFLIGHT_ONLY)" = 1 ] || echo "==> results: $(OUT) (rc=$$rc)"; exit $$rc
