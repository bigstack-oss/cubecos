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

# The path unit that notices the console origins the Advisor reports, and the
# oneshot it triggers. Shipped disabled like the agent's own unit: hex_config's
# advisor module enables the watch once a node is enrolled, and an un-enrolled
# node has no report to watch for.
ADVISOR_SSO_UNITS := cube-advisor-sso.path cube-advisor-sso.service

rootfs_install::
	$(Q)cp -f $(COREDIR)/advisor/$(ADVISOR_AGENT_SERVICE) $(ROOTDIR)/usr/lib/systemd/system/
	$(Q)for u in $(ADVISOR_SSO_UNITS) ; do \
		cp -f $(COREDIR)/advisor/$$u $(ROOTDIR)/usr/lib/systemd/system/ ; \
	done

# for RC builds
heavyfs_install::
	$(Q)cp -f $(COREDIR)/advisor/$(ADVISOR_AGENT_SERVICE) $(ROOTDIR)/usr/lib/systemd/system/
	$(Q)for u in $(ADVISOR_SSO_UNITS) ; do \
		cp -f $(COREDIR)/advisor/$$u $(ROOTDIR)/usr/lib/systemd/system/ ; \
	done
