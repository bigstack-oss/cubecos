# CUBE SDK

include ../../build.mk

dev-deploy:
	$(call RUN_CMD_TIMED, cd $(SRCDIR)/logstash && tar -cf - pipelines.yml patterns.txt eventdb conf.d | pigz -9 > logstash.tgz,"  GEN     logstash.tgz")
	$(call RUN_CMD_TIMED, cd $(SRCDIR)/logstash && scp logstash.tgz root@$(HOST):/etc/logstash,"  UPLOAD  logstash.tgz")
	$(Q)ssh root@$(HOST) rm -rf /etc/logstash/eventdb /etc/logstash/conf.d
	$(Q)ssh root@$(HOST) tar -I pigz -xf /etc/logstash/logstash.tgz -C /etc/logstash
	$(call RUN_CMD, ssh root@$(HOST) hex_config bootstrap logstash,"  RECFG   logstash")

BUILDCLEAN += $(SRCDIR)/logstash/logstash.tgz

include $(HEX_MAKEDIR)/hex_sdk.mk
