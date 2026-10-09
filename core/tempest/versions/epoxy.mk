# Tempest + plugins for OpenStack 2025.1 (epoxy)
TEMPEST_VER := 43.0.0
TEMPEST_PIP := tempest==$(TEMPEST_VER) \
	neutron-tempest-plugin==2.11.0 cinder-tempest-plugin==1.17.0 octavia-tempest-plugin==3.0.0 \
	designate-tempest-plugin==0.25.0 heat-tempest-plugin==2.5.0 manila-tempest-plugin==2.7.0 \
	barbican-tempest-plugin==4.3.0 watcher-tempest-plugin==3.4.0 cyborg-tempest-plugin==2.5.0 \
	ironic-tempest-plugin==2.13.0
