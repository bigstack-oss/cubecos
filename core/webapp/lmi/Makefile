# CUBE SDK

include ../../../build.mk

APP_DEP := $(shell find $(SRCDIR) -type f -name "*.js" 2>/dev/null)
SRC_LKDIR := $(BLDDIR)/srclinks

$(SRC_LKDIR): $(APP_DEP)
	$(call RUN_CMD_TIMED, rm -rf $(SRC_LKDIR) && cp -rf $(SRCDIR) $(SRC_LKDIR) && cd $(SRC_LKDIR) && npm install && npm run build,"  GEN     $@")

$(SRCDIR)/node_modules:
	$(call RUN_CMD_TIMED, chown root:root $(SRCDIR) && cd $(SRCDIR) && npm install,"  GEN     node_modules")

dev-run: $(SRCDIR)/node_modules
	cd $(SRCDIR) && npm run build && npm run start

dev-deploy: $(SRC_LKDIR)
	$(call RUN_CMD_TIMED, cd $(SRC_LKDIR) && npm run build,"  GEN     .next")
	$(call RUN_CMD_TIMED, cd $(SRC_LKDIR) && tar -cf - .next api config-server server.js | pigz -9 > lmi.tgz,"  GEN     lmi.tgz")
	$(call RUN_CMD_TIMED, cd $(SRC_LKDIR) && scp lmi.tgz root@$(HOST):/var/www/lmi,"  UPLOAD  lmi.tgz")
	$(Q)ssh root@$(HOST) rm -rf /var/www/lmi/.next /var/www/lmi/api
	$(Q)ssh root@$(HOST) tar -I pigz -xf /var/www/lmi/lmi.tgz -C /var/www/lmi
	$(Q)ssh root@$(HOST) chown -R www-data:www-data /var/www/lmi
	$(call RUN_CMD, ssh root@$(HOST) hex_config restart_lmi,"  DEPLOY  lmi")

dev-redeploy: $(SRC_LKDIR)
	$(call RUN_CMD_TIMED, cd $(SRC_LKDIR) && npm run build,"  GEN     .next")
	$(call RUN_CMD_TIMED, cd $(SRC_LKDIR) && tar -cf - .next api config-server server.js node_modules | pigz -9 > lmi_full.tgz,"  GEN     lmi_full.tgz")
	$(call RUN_CMD_TIMED, cd $(SRC_LKDIR) && scp lmi_full.tgz root@$(HOST):/var/www/lmi,"  UPLOAD  lmi_full.tgz")
	$(Q)ssh root@$(HOST) rm -rf /var/www/lmi/.next /var/www/lmi/api /var/www/lmi/config-server /var/www/lmi/server.js /var/www/lmi/node_modules
	$(Q)ssh root@$(HOST) tar -I pigz -xf /var/www/lmi/lmi_full.tgz -C /var/www/lmi
	$(Q)ssh root@$(HOST) chown -R www-data:www-data /var/www/lmi
	$(call RUN_CMD, ssh root@$(HOST) hex_config restart_lmi,"  REDEP   lmi")

dev-clean:
	$(Q)rm -rf $(SRCDIR)/node_modules $(SRCDIR)/.next $(SRCDIR)/lmi.tgz $(SRCDIR)/lmi_full.tgz

BUILD += $(SRC_LKDIR)
DISTCLEAN += $(SRC_LKDIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
