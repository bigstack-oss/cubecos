# Cube SDK
# Cube AI Advisor agent unit installation into the node OS image.
#
# The agent binary itself is not shipped here: it arrives at enrolment as a
# signed release, verified against the key compiled into hex_config (ADR 0003).
# Only its unit ships with the image, and it is deliberately NOT enabled at
# build time -- an un-enrolled node has no identity and the unit would
# crash-loop from first boot. hex_sdk's advisor_enroll enables it once a node
# has actually enrolled.

ADVISOR_AGENT_SERVICE := cube-advisor-agent.service

rootfs_install::
	$(Q)cp -f $(COREDIR)/advisor/$(ADVISOR_AGENT_SERVICE) $(ROOTDIR)/usr/lib/systemd/system/

# for RC builds
heavyfs_install::
	$(Q)cp -f $(COREDIR)/advisor/$(ADVISOR_AGENT_SERVICE) $(ROOTDIR)/usr/lib/systemd/system/
