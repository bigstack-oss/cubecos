# CUBE SDK

include ../../../build.mk

VERSION := 1.0.0
IMG := localhost:5080/bigstack/cluster-autodeploy:$(VERSION)

prometheus-am-executor:
	$(call RUN_CMD_TIMED, git clone https://github.com/imgix/prometheus-am-executor.git,"  CLONE   prometheus-am-executor")
	$(call RUN_CMD_TIMED, (cd prometheus-am-executor && go build),"  BUILD   prometheus-am-executor")

.PHONY: build-image
build-image: prometheus-am-executor
	$(call RUN_CMD_TIMED, \
		podman image inspect $(IMG) >/dev/null || sh -x $(SRCDIR)/buildah.sh $(IMG) \
		,"  BUILD   $(IMG)")

.PHONY: copy-image
copy-image:
	$(call RUN_CMD_TIMED, \
		sh -x $(TOP_SRCDIR)/core/docker/copy-images.sh containers-storage:$(IMG) \
		,"  COPY   cluster-autodeploy image")

.PHONY: push-image
push-image: build-image
	$(Q)make push-image -C $(TOP_BLDDIR)/core/docker IMG=$(IMG)

.PHONY: save-image
save-image:
	$(Q)podman save $(IMG) > cluster-autodeploy.tar

clean::
	$(Q)podman image rm -f $(IMG) 2>/dev/null || true


BUILD += push-image
BUILDCLEAN += prometheus-am-executor cluster-autodeploy.tar

include $(HEX_MAKEDIR)/hex_sdk.mk
