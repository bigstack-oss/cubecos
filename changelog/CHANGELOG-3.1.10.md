## [3.1.10](https://github.com/bigstack-oss/cubecos/releases/tag/v3.1.10) - 2026-09-03

### <!-- 0 -->:rocket: New Features

#### Appfw

- Move ospurge into the antelope venv ([0a117a9](https://github.com/bigstack-oss/cubecos/commit/0a117a90ec603421482ab7789c5053ee8788a7d7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Barbican

- Upgrade barbican to openstack antelope ([45f122f](https://github.com/bigstack-oss/cubecos/commit/45f122f39a7227bca6632ba94ae67b022522357e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Boot

- Parallel etcd quorum join, local-zk kafka, ceph-ordered services ([#1071](https://github.com/bigstack-oss/cubecos/pull/1071)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Ceph

- Accept the member role for rgw keystone auth ([54b49a6](https://github.com/bigstack-oss/cubecos/commit/54b49a68b68c5a79f81ed57defe9dacc611412be)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cinder

- Upgrade cinder to openstack antelope ([d06dea7](https://github.com/bigstack-oss/cubecos/commit/d06dea78894691845fffc3512ee4900fffec1c21)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Migrate the patch ([9cf995d](https://github.com/bigstack-oss/cubecos/commit/9cf995d45b6af429a8793dd6ee5817b08ce91579)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make cinder aware of galera cluster to prevent read after write inconsistencies ([6131c85](https://github.com/bigstack-oss/cubecos/commit/6131c852988fc5dc36610597bda6750dbe1d718f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Link cinder binaries under /usr/bin ([6d707c2](https://github.com/bigstack-oss/cubecos/commit/6d707c2968b70236e5d6ac8380ec8535d7b2c3b8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Apply the config change in antelope to prevent volume operation race conditions between cinder and glance ([0666f1b](https://github.com/bigstack-oss/cubecos/commit/0666f1bf27a4ae08b6eb76de5b5cf4f936c130d7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Adjust the ceph volume backend config for cinder moving toward ceph rbd trash system ([a16a9c8](https://github.com/bigstack-oss/cubecos/commit/a16a9c891d62b8721036b70a6c519bceef8b3398)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Set up the service user section to allow volume detaching to continue to work against nova ([b54377c](https://github.com/bigstack-oss/cubecos/commit/b54377c1f0e5c0465208debc48896c93f8a732ff)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cli

- Add iaas identity migrate_legacy_member_role ([8329825](https://github.com/bigstack-oss/cubecos/commit/8329825dac408a504af9080541041bd30d5542b1)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cluster

- Workload-preserving rolling restart -- boot-relay drain/reboot/restore ([9b20aa6](https://github.com/bigstack-oss/cubecos/commit/9b20aa69b8104dd38b0a15831f0bcc804d2b7cb2), [refs #1035](https://github.com/bigstack-oss/cubecos/issues/1035)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Rolling-restart CLI -- always dry-run + confirm, fail-fast guard ([3c3072d](https://github.com/bigstack-oss/cubecos/commit/3c3072d48e35c17f0b881f47ebc8ad3f9d401943), [refs #1035](https://github.com/bigstack-oss/cubecos/issues/1035)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Cluster bootup status -- per-node power-up phase timing ([933123a](https://github.com/bigstack-oss/cubecos/commit/933123a0ea8f96c8a824323c47f6938f5d1e5e08)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Record running VMs at cluster stop and restore them after power-up ([05c33d2](https://github.com/bigstack-oss/cubecos/commit/05c33d2611832debe55aacc421d22565d4fb7a56)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Core

- Build + ship the zero-touch driver (agent + pxeserver server) ([#1178](https://github.com/bigstack-oss/cubecos/pull/1178)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Cyborg

- Upgrade cyborg to openstack antelope ([d70f432](https://github.com/bigstack-oss/cubecos/commit/d70f432185907167947a22f9d3acb62f4956cc6a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Update the default config for cyborg ([d87a6ea](https://github.com/bigstack-oss/cubecos/commit/d87a6ea581b09d4eb732b2100b4b89c7b1bc751b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Update the binary path in service unit files ([5e0af71](https://github.com/bigstack-oss/cubecos/commit/5e0af71bf975d47525d68486c5fd54a6ef15c459)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Migrate the patch ([c6056bf](https://github.com/bigstack-oss/cubecos/commit/c6056bf226e85539849b676f74b63dddbca971f4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make cyborg aware of galera cluster to prevent read after write inconsistencies ([47fb620](https://github.com/bigstack-oss/cubecos/commit/47fb620695e915e1d29fab7e587327130d5c54fd)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop the system python copy of the accelerator osc plugin ([0f4e036](https://github.com/bigstack-oss/cubecos/commit/0f4e0364bf638e0660628b7708f0e2301dbb16e6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Designate

- Upgrade designate to openstack antelope ([5f47e4c](https://github.com/bigstack-oss/cubecos/commit/5f47e4ccddc28ef39b2834a3d6153c86be82f792)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Update binaries path in service unit files ([17be721](https://github.com/bigstack-oss/cubecos/commit/17be721501c8e0a62e25d56c760abd026c2e6b12)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Update the sample config ([dc6a895](https://github.com/bigstack-oss/cubecos/commit/dc6a8957432621b160793dd64e188d3b8ffef38b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Install designate-dashboard into the system python for horizon ([0c011dd](https://github.com/bigstack-oss/cubecos/commit/0c011dde66da9840bd0c373f0ccb1956a68213e0)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make designate aware of galera cluster to prevent read after write inconsistencies ([ac0b0e2](https://github.com/bigstack-oss/cubecos/commit/ac0b0e2441324f8c1145e15b263b19cb1fa3a76e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Name python3-designateclient for the system openstack CLI ([0fc1c28](https://github.com/bigstack-oss/cubecos/commit/0fc1c28630087d0422fdc3e2cf6e4619248170b9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move the dns osc plugin into the antelope venv ([479f40f](https://github.com/bigstack-oss/cubecos/commit/479f40f27d726075dc2dc93756e7fedffd2f4846)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Fts

- Hidden opt-out for cluster repair + health auto_repair ([#1226](https://github.com/bigstack-oss/cubecos/pull/1226)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Airgap_sim_apply/clear — CUBE_AIRGAP egress block for air-gapped install validation ([#1246](https://github.com/bigstack-oss/cubecos/pull/1246)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Git

- Opt-out flag so a node keeps its uncommitted rootfs changes ([54ac712](https://github.com/bigstack-oss/cubecos/commit/54ac712291bc4dff42f22fa6c2944a50755abaec), [closes #1306](https://github.com/bigstack-oss/cubecos/issues/1306)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Glance

- Upgrade glance to openstack antelope ([1cbf3be](https://github.com/bigstack-oss/cubecos/commit/1cbf3be586f661a2086ea00a7a5181936a7b0266)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Adjust systemd service unit files for the venv execution context ([a8b323d](https://github.com/bigstack-oss/cubecos/commit/a8b323db3ac97cbfacbd49ea93471698c4f6ee56)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make glance aware of galera cluster to prevent read after write inconsistencies ([10c407d](https://github.com/bigstack-oss/cubecos/commit/10c407da63dca7ce7769e00a6c8bbbdcc12bfaa2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Set glance-manage to the binary under venv ([aadc418](https://github.com/bigstack-oss/cubecos/commit/aadc418c8591fc11d26b2dd0704fc3bc6908a730)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Link more glance binaries under /usr/bin ([5fac935](https://github.com/bigstack-oss/cubecos/commit/5fac935d9517b27871ef42b4b26d16bb658dd5db)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Gpu

- Support nvidia rtx a2000 ([1b30fda](https://github.com/bigstack-oss/cubecos/commit/1b30fda33de02f73d28539f52cb949825e6b7622)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add GPU Utilization and VRAM history panels to Device dashboard ([#1019](https://github.com/bigstack-oss/cubecos/pull/1019), [refs #824](https://github.com/bigstack-oss/cubecos/issues/824)) by [@SekiXu](https://github.com/SekiXu)
- Validate vGPU profiles in gpu_resource_set (#904) ([db232ff](https://github.com/bigstack-oss/cubecos/commit/db232ff10aa2df5ca24f4dd1494e6ae2ec9ed37c)) by [@SekiXu](https://github.com/SekiXu)
- Add SR-IOV vGPU apply helper with fail-fast teardown (#904) ([366fb4e](https://github.com/bigstack-oss/cubecos/commit/366fb4e1d0dd168d5846b00fabee3e83c9c98e41)) by [@SekiXu](https://github.com/SekiXu)
- Resolve full vGPU type names and derive Nova PCI aliases (#904) ([d12ca7c](https://github.com/bigstack-oss/cubecos/commit/d12ca7c146801468e0779c41883d596361dde565)) by [@SekiXu](https://github.com/SekiXu)
- Regenerate the Nova PCI drop-in from the GPU truth file (#904) ([871fe9c](https://github.com/bigstack-oss/cubecos/commit/871fe9cd1260544752f7ed34b7e5d093fad72eb3)) by [@SekiXu](https://github.com/SekiXu)
- Wire the sriovVgpu branch of gpu_resource_set (#904) ([81c5b66](https://github.com/bigstack-oss/cubecos/commit/81c5b6634708f395ad3c7530c0071e5c34ddcbc4)) by [@SekiXu](https://github.com/SekiXu)
- Re-apply sriovVgpu partitioning on boot via Commit() (#904) ([a590693](https://github.com/bigstack-oss/cubecos/commit/a5906936e359c5331ef18071793294223d875e95)) by [@SekiXu](https://github.com/SekiXu)
- Implement migBackedVgpu resource-set support (#905) ([#1223](https://github.com/bigstack-oss/cubecos/pull/1223)) by [@SekiXu](https://github.com/SekiXu)

#### Grafana

- Provision the lachesis dashboards from the component clone ([0b4eb7e](https://github.com/bigstack-oss/cubecos/commit/0b4eb7eb3c682e6d019a221888e78633579d52c5)) by [@arasHi87](https://github.com/arasHi87)
- Let a device GPU history link narrow to one card ([#1287](https://github.com/bigstack-oss/cubecos/pull/1287)) by [@SekiXu](https://github.com/SekiXu)

#### Health

- Add fc_link Fibre Channel storage link health check ([#1057](https://github.com/bigstack-oss/cubecos/pull/1057)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Register lachesis with cluster check and auto-repair ([#1186](https://github.com/bigstack-oss/cubecos/pull/1186)) by [@arasHi87](https://github.com/arasHi87)

#### Heat

- Let hex_config manage logrotate and wsrep sync for heat ([55942d3](https://github.com/bigstack-oss/cubecos/commit/55942d3b0a12208e392261ad296dd68d1aa631e1)) by [@SekiXu](https://github.com/SekiXu)
- Resolve heat-manage from the venv symlink ([bb80d02](https://github.com/bigstack-oss/cubecos/commit/bb80d021b17753d67326bfabc3559df7e8f5545e)) by [@SekiXu](https://github.com/SekiXu)
- Add antelope config sample and systemd units ([a9b2669](https://github.com/bigstack-oss/cubecos/commit/a9b266927bc12914a6f6d39ef84060a5a57f22bf)) by [@SekiXu](https://github.com/SekiXu)
- Install heat from pip into the antelope venv ([7d91ff0](https://github.com/bigstack-oss/cubecos/commit/7d91ff010605b59001e081a34fa8a9cfc49cbbe5)) by [@SekiXu](https://github.com/SekiXu)
- Restore the orchestration panels with heat-dashboard 9.0.0 ([2d98ba1](https://github.com/bigstack-oss/cubecos/commit/2d98ba196b64cb9bf595958d7d451291654df1e2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move the orchestration osc plugin into the antelope venv ([e7a0902](https://github.com/bigstack-oss/cubecos/commit/e7a0902a60bc50158de6c983e29cb85037eed02f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Link the heat client cli out of the antelope venv ([93bc94d](https://github.com/bigstack-oss/cubecos/commit/93bc94d0dff48731b35864d8ae1e4c31171258fd)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Heavyfs

- Point the openstack dnf repo at antelope ([6305ff2](https://github.com/bigstack-oss/cubecos/commit/6305ff2c4b0bacfc240d29b1ca7d1637b8c1ad4c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_config

- Start lachesis on compute nodes and render its config ([0dd6e68](https://github.com/bigstack-oss/cubecos/commit/0dd6e68ab0dafbfdd5b8f8c4f1cd5cdd098ffe79)) by [@arasHi87](https://github.com/arasHi87)

#### Horizon

- Serve the dashboard from gunicorn behind an httpd proxy ([79ea9bd](https://github.com/bigstack-oss/cubecos/commit/79ea9bde0f14414b8509dc096eca0c6fbbb65258)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move horizon into the openstack antelope venv ([4c0bcfb](https://github.com/bigstack-oss/cubecos/commit/4c0bcfb47b95896f45c25e7844da2b89d8196b8a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Start the dashboard unit and migrate under the venv python ([cfbd967](https://github.com/bigstack-oss/cubecos/commit/cfbd967f9acd02e412164e7c6613fa89b96d343e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Register the load balancer panel and its policy defaults ([8368183](https://github.com/bigstack-oss/cubecos/commit/8368183d0138bbb61858e750c03c24cc27eaa866)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Hand new project users the member role ([f96c15d](https://github.com/bigstack-oss/cubecos/commit/f96c15d5f65a3215a6fe2f5620f001259c2b21d9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Ironic

- Upgrade ironic to openstack antelope ([d8d9987](https://github.com/bigstack-oss/cubecos/commit/d8d9987c28ee35fba063683f2eea2965b3261c77), [refs #610](https://github.com/bigstack-oss/cubecos/issues/610)) by [@SekiXu](https://github.com/SekiXu)
- Restore the bare metal panel with ironic-ui 6.1.0 ([81151a9](https://github.com/bigstack-oss/cubecos/commit/81151a9b2affe0eea254dec51a2fa8fbc9841977)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Jail

- Bump pinned kernel 6.12.95 -> 6.12.96 ([#1210](https://github.com/bigstack-oss/cubecos/pull/1210)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Keycloak

- Move the login deployment onto the quarkus keycloakx chart ([ae7debb](https://github.com/bigstack-oss/cubecos/commit/ae7debb2b2ddae3d12bae94d240b871293250119)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Configure keycloak 18 through the keycloakx chart values ([7b9ce92](https://github.com/bigstack-oss/cubecos/commit/7b9ce92a5e4ddcdebf15ade48a8d86377c7af0b5)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Keystone

- Upgrade keystone to openstack antelope ([a10fd7d](https://github.com/bigstack-oss/cubecos/commit/a10fd7dcd3af5325378c1a711bbe2c13e6bbce95)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Adjust system setups for keystone coming from pip instead of centos openstack sig rpm ([5721d7c](https://github.com/bigstack-oss/cubecos/commit/5721d7c0bed72dea17e89c54a6c77905eb7e2208)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make keystone aware of galera cluster to prevent read after write inconsistencies ([ec7d7f7](https://github.com/bigstack-oss/cubecos/commit/ec7d7f7ff9b94c79a5ce8cc7145869eb44c8f90b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Set keystone-manage to the binary under venv ([7f71688](https://github.com/bigstack-oss/cubecos/commit/7f716886022785faab48eabf41dc8f4854855b46)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Change request flow from httpd wsgi -> keystone to httpd proxy -> gunicorn -> keystone ([bf8fb28](https://github.com/bigstack-oss/cubecos/commit/bf8fb2886dfda2ab7197a67e754c6b013058de0d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Keep the member role and bridge _member_ onto it ([dcb9c03](https://github.com/bigstack-oss/cubecos/commit/dcb9c036808fb9e2c5ecdfda908a4ed3c2eae05a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bind the member role to cube_users alongside _member_ ([a03221d](https://github.com/bigstack-oss/cubecos/commit/a03221de82e24940fec744895542268f9398bd45)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Manila

- Add tuning for additional share-backend Cinder volume types ([02bb173](https://github.com/bigstack-oss/cubecos/commit/02bb173f700beed35fac97a831b8ab1bac7a2f56)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Render one generic backend section per configured Cinder volume type ([80b867b](https://github.com/bigstack-oss/cubecos/commit/80b867b7f5260bf23a526c64f07b7ce844034334)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Create/prune a share type per configured backend on commit ([5e9aba1](https://github.com/bigstack-oss/cubecos/commit/5e9aba162179375e391aa9faf334cacde6317429)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Move manila into the openstack antelope venv ([d9e7fcf](https://github.com/bigstack-oss/cubecos/commit/d9e7fcf720a7f1442efd37968ed4f591ab3a684d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Let hex_config manage logrotate and wsrep sync for manila ([79cf98b](https://github.com/bigstack-oss/cubecos/commit/79cf98b64368da83b193ce4b0b26dfc1929494c1)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Keep max_pool_size and pin the privsep helper after dropping manila-dist.conf ([aaefc8f](https://github.com/bigstack-oss/cubecos/commit/aaefc8f05ae7b6a84dea694806a61b2dcf8a7e06)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Build the service image and source it from the antelope build ([1056c3d](https://github.com/bigstack-oss/cubecos/commit/1056c3dcb0c2f7d1cf62879d044be9cceb74951d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move manila-ui into the openstack antelope venv ([97b0836](https://github.com/bigstack-oss/cubecos/commit/97b08365e003a7e00a211df2f0fe4fffa79e08f9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move the share osc plugin into the antelope venv ([c79caa5](https://github.com/bigstack-oss/cubecos/commit/c79caa5c8eea028a4ed3a5e622fbcd843fd7ad4e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Mariadb

- Size galera gcache to 4G for IST-safe rolling upgrades ([7a4a595](https://github.com/bigstack-oss/cubecos/commit/7a4a59573defc10bbf1e5ea96531922e35e10297)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Bump mariadb from 10.5.x to 10.6.x for openstack antelope ([fb6f8aa](https://github.com/bigstack-oss/cubecos/commit/fb6f8aa7224b81ef2c658b2de98d2dd98fc8fb1c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Masakari

- Upgrade masakari to openstack antelope ([ae6ca95](https://github.com/bigstack-oss/cubecos/commit/ae6ca956472e3f137e1041e1be545392d4a7d2d7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Migrate the source patches to antelope ([9b1e3e2](https://github.com/bigstack-oss/cubecos/commit/9b1e3e2afdaa84ed71881b92643e0fd5b8c59ac8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make masakari aware of galera cluster to prevent read after write inconsistencies ([4f87f02](https://github.com/bigstack-oss/cubecos/commit/4f87f02e3210f23a215a910a2cd20ce2fca66fcd)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Patch masakaridashboard in the venv and drop its python 3.9 copies ([6b1e92e](https://github.com/bigstack-oss/cubecos/commit/6b1e92ed3d2000ca9c000d00029253be772db70d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop the system python copy of the ha osc plugin ([f88b00b](https://github.com/bigstack-oss/cubecos/commit/f88b00b8d0c1013266eddba9a5b6b702f75c9e29)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Miscellaneous

- Add gpu_device_list function to sdk_gpu ([2d85758](https://github.com/bigstack-oss/cubecos/commit/2d85758c42616f1d7e474215cab7fa2b39b078e2)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Add gpu_vgpu_profile_list function to sdk_gpu ([#894](https://github.com/bigstack-oss/cubecos/pull/894)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Add `gpu_pgpu_attached_instance_get <pciAddress>` to `sdk_gpu` ([#900](https://github.com/bigstack-oss/cubecos/pull/900)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Add `supportedTypes` and `profileCountLimit` to gpu_device_list function ([c80da04](https://github.com/bigstack-oss/cubecos/commit/c80da04dd2ae7c91c5cfdbf55d0d3f9136691ac6)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Fix incorrect implementation of gpu_device_list ([#903](https://github.com/bigstack-oss/cubecos/pull/903)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Vgpu_profile_list always return all profiles ([#934](https://github.com/bigstack-oss/cubecos/pull/934)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Add  to  for pGPU ([b34cced](https://github.com/bigstack-oss/cubecos/commit/b34cced1eb824ac7dd8c8a6ec84907cb1c31cdc2)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Add config_gpu that creates and migrates GPU config files ([453acd4](https://github.com/bigstack-oss/cubecos/commit/453acd44230f6d2ee4f855bb1b08eb7088b1f0e0)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- 763 pcie need to expand to maximum ([#1008](https://github.com/bigstack-oss/cubecos/pull/1008)) by [@raven-pan](https://github.com/raven-pan)
- Hex_config gpu_resource_set functionality for passthrough mode ([139c811](https://github.com/bigstack-oss/cubecos/commit/139c8115d19eecc4336fdc302795ed2ea524d9fb)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Hex_config gpu_resource_set functionality for passthrough mode ([#1015](https://github.com/bigstack-oss/cubecos/pull/1015)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)

#### Monasca

- IPMI sensor + RDT L3 agent plugins for Watcher goals ([59d3271](https://github.com/bigstack-oss/cubecos/commit/59d32715fa4bc79efdcbdb64e111b637e6e0a2b0)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Move monasca into the openstack antelope venv ([851815b](https://github.com/bigstack-oss/cubecos/commit/851815b2ea1a797ad276c33a9db8f253add62655)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Health-check monasca-api as its own service ([bfc2930](https://github.com/bigstack-oss/cubecos/commit/bfc2930e446fb52918b428ce369da0cfb2995a9b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Mongodb

- Upgrade mongodb from 7.0.28 to 8.0.29 ([3cb151b](https://github.com/bigstack-oss/cubecos/commit/3cb151b4a1c231f62bf5833c0ec50a11d69dbdbb)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Raise the featureCompatibilityVersion once the last control node rolls ([9caceb4](https://github.com/bigstack-oss/cubecos/commit/9caceb454dac9875522fdca6a6caacd293e1a2e6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Report and repair a featureCompatibilityVersion left behind ([cdf4edc](https://github.com/bigstack-oss/cubecos/commit/cdf4edc9f72074c52e02cbab9fbf9314284e160f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Mysql

- Ship MariaDB-devel and zlib-devel for the mysqlclient build ([653709c](https://github.com/bigstack-oss/cubecos/commit/653709c2f90a7d4e5b62a2afa870ced530e64858)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Neutron

- Upgrade neutron to openstack antelope ([abe95f5](https://github.com/bigstack-oss/cubecos/commit/abe95f525ae5a022819362042328afd26dbb6334)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Migrate the patch ([8dad8c2](https://github.com/bigstack-oss/cubecos/commit/8dad8c29ff5bda2b042e78b169f788e361f0d7ca)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop the deprecated config option DEFAULT/allow_overlapping_ips ([293cb04](https://github.com/bigstack-oss/cubecos/commit/293cb04a6d60ca6c1b095c9450f329aa06fb0a80)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make neutron aware of galera cluster to prevent read after write inconsistencies ([689b8e1](https://github.com/bigstack-oss/cubecos/commit/689b8e16e244b744cc3dd2a4ea8aebc83a9f2755)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Register the vpnaas dashboard panel ([61194c8](https://github.com/bigstack-oss/cubecos/commit/61194c89961add88fadfcbc94e839187cc34805c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Nova

- Cap concurrent live-migrations at 3 for rolling restart ([#1054](https://github.com/bigstack-oss/cubecos/pull/1054), [refs #1031](https://github.com/bigstack-oss/cubecos/issues/1031)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Upgrade nova to openstack antelope ([7552e57](https://github.com/bigstack-oss/cubecos/commit/7552e57626286e46467ca1951137e251e1b31dc0)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make nova aware of galera cluster to prevent read after write inconsistencies ([c71104d](https://github.com/bigstack-oss/cubecos/commit/c71104dc3699bafb16d7bfff24762edc440355a4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop the deprecated config option glance/api_servers ([1622f3e](https://github.com/bigstack-oss/cubecos/commit/1622f3ec10c2032997efd0e5fd1dbac5667ca684)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Migrate the patch ([a5a9f1a](https://github.com/bigstack-oss/cubecos/commit/a5a9f1ac996bf9a6d72fbf7c32074f07812a64d8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Run placement-api using uwsgi and proxy requests from httpd to uwsgi ([eeab5d7](https://github.com/bigstack-oss/cubecos/commit/eeab5d78d2e267205f704b5e4bdab63157430883)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Octavia

- Add antelope config sample, policy and dist conf ([ae99c31](https://github.com/bigstack-oss/cubecos/commit/ae99c31bb09ed05785a4d148217e45717035db55)) by [@SekiXu](https://github.com/SekiXu)
- Align the api and housekeeping units with the venv layout ([6d4582a](https://github.com/bigstack-oss/cubecos/commit/6d4582ae61687d9410ce7abf48b62bce7bc66301)) by [@SekiXu](https://github.com/SekiXu)
- Install octavia from pip into the antelope venv ([050136e](https://github.com/bigstack-oss/cubecos/commit/050136e7c750347b117988b9b558de32ea725e00)) by [@SekiXu](https://github.com/SekiXu)
- Resolve octavia-db-manage from the venv symlink ([f2533fd](https://github.com/bigstack-oss/cubecos/commit/f2533fd803d9b9ad26f2a2a8e1e565846ba7b04f)) by [@SekiXu](https://github.com/SekiXu)
- Set mysql_wsrep_sync_wait on the octavia database ([4985c7a](https://github.com/bigstack-oss/cubecos/commit/4985c7aeb775c8c18fc8c8323078e67f67d364d2)) by [@SekiXu](https://github.com/SekiXu)
- Source the amphora image from the antelope build ([b4030fc](https://github.com/bigstack-oss/cubecos/commit/b4030fc82fda5ecf0857deb6c812ceaf455f5535)) by [@SekiXu](https://github.com/SekiXu)
- Move octavia-dashboard into the openstack antelope venv ([7012c2e](https://github.com/bigstack-oss/cubecos/commit/7012c2e105aa865a7bcd41e0cbbaaac4935e252d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move the loadbalancer osc plugin into the antelope venv ([d202805](https://github.com/bigstack-oss/cubecos/commit/d202805b7ddeef6f9d8ee66cb53e67d56a130f46)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Back the amphorav2 taskflow with a jobboard ([e635f4d](https://github.com/bigstack-oss/cubecos/commit/e635f4d0b466e52e16a7aa4cd9b25adf192c523a), [refs #616](https://github.com/bigstack-oss/cubecos/issues/616)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Openstack

- Prepare the venv environment for the next openstack version, antelope ([2a40914](https://github.com/bigstack-oss/cubecos/commit/2a409140e459f71ad39c9e310f4bba75b8b5f20c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Install the pip constraint file for openstack antelope ([277b49f](https://github.com/bigstack-oss/cubecos/commit/277b49f933352625f2f5b621f1f644469f36b24e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Update path to include venv for openstack antelope ([7e0831b](https://github.com/bigstack-oss/cubecos/commit/7e0831bc8d8ac597cddb70754dcaba2a044c85ec)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add the caracal release tier and its pip constraint file ([349f4e4](https://github.com/bigstack-oss/cubecos/commit/349f4e4507d54667b4cdb30ecc1728fff5e6c1b7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Set up the execution context for openstack caracal ([8c39c61](https://github.com/bigstack-oss/cubecos/commit/8c39c611d7a7d6469989fb6d09f02c4dd8caec65)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move the openstack cli into the antelope venv ([6462be4](https://github.com/bigstack-oss/cubecos/commit/6462be4ce639a8ef12b285666405cf1836451452)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Power

- Instrument rolling restart/upgrade/bootup for root-cause telemetry ([97787f5](https://github.com/bigstack-oss/cubecos/commit/97787f593a2234fbc199fd8de6c529cfde6d35f0)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Prometheus

- Scrape the lachesis agent fleet via a file_sd target list ([aa0bbc1](https://github.com/bigstack-oss/cubecos/commit/aa0bbc1f29effe08dffcfdd6713166d566625ffd)) by [@arasHi87](https://github.com/arasHi87)
- Regenerate the lachesis scrape targets on membership change via a cron.d job ([c3a522b](https://github.com/bigstack-oss/cubecos/commit/c3a522b4f0b1e7dfad85663b0d752742d1d83609)) by [@arasHi87](https://github.com/arasHi87)

#### Python

- Install python 3.10 ([9b83d1c](https://github.com/bigstack-oss/cubecos/commit/9b83d1c1c0b6fe8ba95312d209c6e5dde609b9cd)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Install python 3.11 ([f619307](https://github.com/bigstack-oss/cubecos/commit/f619307187094042bb29c74541b6fcf0d52adb92)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Rabbitmq

- Upgrade rabbitmq from 3.9 to 3.10 ([f13118d](https://github.com/bigstack-oss/cubecos/commit/f13118d72bb9b1b79a29aebe2c54ad25d5b52146)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Rolling

- Hand off the OVN SB master before a node reboots ([bc278ae](https://github.com/bigstack-oss/cubecos/commit/bc278ae7a737c83ecaffda7623e77ac74e381561)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Stall watchdog pauses a wedged roll from the VIP holder ([d528535](https://github.com/bigstack-oss/cubecos/commit/d5285350f5efe682a71648a7c14cd88bfcaa5e9c)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Security

- Restrict AMQP 5672 to cluster nodes via SERVICE-INT (cubecos-private#73) ([ef893dd](https://github.com/bigstack-oss/cubecos/commit/ef893ddbd2f26081a9d24f259007be36cc5c3340)) by [@SekiXu](https://github.com/SekiXu)
- Drop RabbitMQ 15672/25672 from non-cluster sources (cubecos-private#73) ([#1051](https://github.com/bigstack-oss/cubecos/pull/1051)) by [@SekiXu](https://github.com/SekiXu)
- Enable hybrid PQC TLS group and complete nginx TLS profile ([9b2b3c3](https://github.com/bigstack-oss/cubecos/commit/9b2b3c361654e7f183d50bef78b547ba5bd922e6)) by [@SekiXu](https://github.com/SekiXu)

#### Skyline

- Move skyline into the openstack caracal venv ([69f584a](https://github.com/bigstack-oss/cubecos/commit/69f584a6637b4863989b40f4fd90277c3fb5fdc1), [closes #601](https://github.com/bigstack-oss/cubecos/issues/601)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Swift

- Upgrade the swift client to openstack antelope ([2735008](https://github.com/bigstack-oss/cubecos/commit/2735008f7dbef5e1a67f97ef943e8969305f9369)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Telegraf

- Upgrade from 1.17.2 to 1.24.4 ([26e6f1f](https://github.com/bigstack-oss/cubecos/commit/26e6f1fde3793065d7ec0e884a495756ad8359f3)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Give sflow a read-only openstack db account ([06666ec](https://github.com/bigstack-oss/cubecos/commit/06666ec8a44a9e72de95588cdfa91b1502079eff)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Terraform

- Bump the keycloak provider to 4.2.0 for the quarkus admin api ([41c7164](https://github.com/bigstack-oss/cubecos/commit/41c7164b0b8f81c99d3661596117d72c57fb3c72)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Upgrade

- Gate both rolling relays on a functional live-migration path ([d6d10b5](https://github.com/bigstack-oss/cubecos/commit/d6d10b5f1f17fe34114f49acedcef5fb03aca6ab)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Version-uniformity + masakari-maintenance gates for mixed-version rolls ([1cd87be](https://github.com/bigstack-oss/cubecos/commit/1cd87be3d35ddde716c88a1916f7d1c68e6265c7)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Split RabbitMQ feature-flag enable into FTS vs upgrade paths ([e3d79a9](https://github.com/bigstack-oss/cubecos/commit/e3d79a977224c503123b15919c6d90002f384160)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Watcher

- Wire Monasca metrics for the optimization goals (config) ([5f5352e](https://github.com/bigstack-oss/cubecos/commit/5f5352ee088bab6587b55be914d55dbf2cff9200)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Add allocation_balance strategy for idle-instance spreading ([#1128](https://github.com/bigstack-oss/cubecos/pull/1128)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Add the antelope config sample and systemd units ([c85570e](https://github.com/bigstack-oss/cubecos/commit/c85570e07533d469b448a5e619fbbeee7b989c80)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move watcher into the openstack antelope venv ([75bff75](https://github.com/bigstack-oss/cubecos/commit/75bff75d29a89bf0b00192eac30590f27ac3104b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Set the galera sync wait for watcher ([3eda789](https://github.com/bigstack-oss/cubecos/commit/3eda789258f28f181087da81a41600cd6e318963)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop the system python copy of the optimize osc plugin ([241c9a0](https://github.com/bigstack-oss/cubecos/commit/241c9a0a3ab63fe3a33b3ecd5ab999b8b49afbd2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### <!-- 1 -->:bug: Bug fixes

#### ClusterReady

- Hide check_repair outputs in FTS #726 ([#729](https://github.com/bigstack-oss/cubecos/pull/729)) by [@leechienpang](https://github.com/leechienpang)

#### Airgap

- Seed rancher v2.11.2 image set in the offline registry ([#1232](https://github.com/bigstack-oss/cubecos/pull/1232)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Bundle rancher/machine into the offline registry ([#1253](https://github.com/bigstack-oss/cubecos/pull/1253)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Keep CUBE_AIRGAP counters across periodic re-applies ([bd59e6e](https://github.com/bigstack-oss/cubecos/commit/bd59e6e28630a4c5cc9acea05187c15be7ed88de)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Apache

- Bind 8080 to loopback and deny the empty docroot ([3a82984](https://github.com/bigstack-oss/cubecos/commit/3a829848a431e454d446b633ede22ea62dcbc618)) by [@raven-pan](https://github.com/raven-pan)
- Stop shipping the default welcome page ([#1113](https://github.com/bigstack-oss/cubecos/pull/1113)) by [@raven-pan](https://github.com/raven-pan)

#### Api

- Write the logrotate config for api ([4531dab](https://github.com/bigstack-oss/cubecos/commit/4531dabcc7f12f7fa33bddce7749fc2c06f71eef)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### App

- Fix an arg reading issue for app_register ([#853](https://github.com/bigstack-oss/cubecos/pull/853)) by [@jdjgya](https://github.com/jdjgya)
- Surface import.sh failures in app_import ([5c89a45](https://github.com/bigstack-oss/cubecos/commit/5c89a4503e323e00cd8c58c7bf4c93adbc666d2c)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Barbican

- Bring up the antelope services and correct barbican.conf ([9edee7b](https://github.com/bigstack-oss/cubecos/commit/9edee7b921c95bc7d554919d1f836457da75582b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add the missing pymysql and kafka driver dependencies ([4cb2c58](https://github.com/bigstack-oss/cubecos/commit/4cb2c58cd89edbbb82eea68594b19ad5acbd9ee4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Boot

- Stop a down/flapping external SAN from stalling reboot + recovery ([7fec85a](https://github.com/bigstack-oss/cubecos/commit/7fec85ac4adfcfe3bb4808d7a188966be3744a72), [closes #1036](https://github.com/bigstack-oss/cubecos/issues/1036)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Abort a node's bring-up when bootstrap fails instead of marching on ([c4e754d](https://github.com/bigstack-oss/cubecos/commit/c4e754dec2fa0c5101ee9a84fd7987bf81fed6d2)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Start pacemaker on a configured master reboot so the VIP returns ([beba2a0](https://github.com/bigstack-oss/cubecos/commit/beba2a0d4b551aa7cf101270dbc24206af905535)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Tolerate cold-boot timing -- keystone endpoint wait + bootup status math ([135d51a](https://github.com/bigstack-oss/cubecos/commit/135d51a315b90c26a0459bc8fd2038fe93fd96f6)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Bootstrap

- Bound every console write so a dead console can't stall the roll ([8328048](https://github.com/bigstack-oss/cubecos/commit/83280482d630d6a39038ea688e329ec6b47477c3), [closes #1303](https://github.com/bigstack-oss/cubecos/issues/1303)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Bound the two remaining console pipelines ([8749ee3](https://github.com/bigstack-oss/cubecos/commit/8749ee303757da54c203f453b2d9ca299d3819a4)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Build

- Upgrade trivy version to 0.69.3 ([#721](https://github.com/bigstack-oss/cubecos/pull/721)) by [@leechienpang](https://github.com/leechienpang)
- Sudo: PAM account management error: Authentication ([#1083](https://github.com/bigstack-oss/cubecos/pull/1083)) by [@leechienpang](https://github.com/leechienpang)
- Fetch kafka from archive.apache.org and drop partial downloads ([dde43d3](https://github.com/bigstack-oss/cubecos/commit/dde43d36639817af3cc2c1993e3838f41fe2e3dd)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Fetch the pinned mariadb rpms from the official Rocky CDN ([#1136](https://github.com/bigstack-oss/cubecos/pull/1136)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Make full errors in core/fixpacks ([#1159](https://github.com/bigstack-oss/cubecos/pull/1159)) by [@leechienpang](https://github.com/leechienpang)
- Keep the appctl lfs payload out of the clone timeout ([0fe58a9](https://github.com/bigstack-oss/cubecos/commit/0fe58a901a63843a6c12ccb46ca7c57ea54300ef)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Ceph

- Defer lifting data-movement flags until OSDs rejoin on boot ([#1069](https://github.com/bigstack-oss/cubecos/pull/1069)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Render mon host from the live monmap on every node's boot ([#1100](https://github.com/bigstack-oss/cubecos/pull/1100)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Harden perf-tuned defaults for converged nodes ([cba9f08](https://github.com/bigstack-oss/cubecos/commit/cba9f0813cc296edd88ee1612ad978a443031e65), [closes #1120](https://github.com/bigstack-oss/cubecos/issues/1120)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Carry admin.key across PPU upgrade so cephfs mounts ([aab49da](https://github.com/bigstack-oss/cubecos/commit/aab49daffdd4cbe7af72485f627bc315d798b539)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Ganesha active/active HA -- rados_cluster + per-node nodeid + grace DB ([#1233](https://github.com/bigstack-oss/cubecos/pull/1233)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Install the rados/rbd bindings with pip ([cbd4987](https://github.com/bigstack-oss/cubecos/commit/cbd498706242bcc71c3983952acd635b30633117)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bound the ganesha grace-DB calls so FTS cannot wedge ([3c9a10d](https://github.com/bigstack-oss/cubecos/commit/3c9a10dda70e5e24a2de06ddadc6aa0432f93e79)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Enforce the CLI timeout and move MDS placement off the boot path ([d04c273](https://github.com/bigstack-oss/cubecos/commit/d04c273dc482054bd9f5616f7c0446fd30c28e70)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Keep the ganesha grace-DB membership the roll depends on ([8b5923c](https://github.com/bigstack-oss/cubecos/commit/8b5923c7f4de385fb6f8f5c016f80b88b0d9aba9), [closes #1311](https://github.com/bigstack-oss/cubecos/issues/1311)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Lift the poweroff I/O pause before the boot needs storage ([e07ec05](https://github.com/bigstack-oss/cubecos/commit/e07ec05a395c7af2ece36ca5a932c4b28811ddf0)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Bound the per-OSD compact so it cannot wedge a node's bootstrap ([c35a346](https://github.com/bigstack-oss/cubecos/commit/c35a3469c78f1f05b9887edd1b12183b79f11257), [closes #1329](https://github.com/bigstack-oss/cubecos/issues/1329)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Cinder

- Make type checking work ([#765](https://github.com/bigstack-oss/cubecos/pull/765)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Nvmetcli is provided as noarch instead of x86_64 ([1c71e25](https://github.com/bigstack-oss/cubecos/commit/1c71e255074fc98fdb0d643265f9a6f1b658f91e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Provide the default config to launch services ([af239d6](https://github.com/bigstack-oss/cubecos/commit/af239d6d6555a9b62d10a90e9ab718da6d1b9432)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Prepend the venv bin to rootwrap exec_dirs ([aca5dd3](https://github.com/bigstack-oss/cubecos/commit/aca5dd399ee8caa095797ee8e34f0df8936e6b12)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Call the cinder cli at its venv path ([8479433](https://github.com/bigstack-oss/cubecos/commit/8479433cf4db5ec3cea201ee13966352ea9457a7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cli

- Add_disk is partially successful when osd id >= 10 #725 ([1b08dfe](https://github.com/bigstack-oss/cubecos/commit/1b08dfe3958f33cac68a3be7b9ec84c2c4b3cc57)) by [@leechienpang](https://github.com/leechienpang)
- Repair os_light_osc off, which never restored the real client ([9493423](https://github.com/bigstack-oss/cubecos/commit/9493423f22500329b07679bb9a2ea61e5c573c98)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Point $NOVA at the nova client that exists ([4a5489d](https://github.com/bigstack-oss/cubecos/commit/4a5489de612214c5ff52b4d225849441ea1a05bd)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cluster

- Stop `cluster poweroff` deadlocking on cephfs umount ([#1060](https://github.com/bigstack-oss/cubecos/pull/1060)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Make rolling-restart status resilient to failover, wedge, and phase loss ([26310cf](https://github.com/bigstack-oss/cubecos/commit/26310cf0f8b15901bde1f164f407765e7a2813d1)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Mark bootup 'done' + roll-advance from the boot script per node ([#1090](https://github.com/bigstack-oss/cubecos/pull/1090)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Record the rolling-restart 'bootstrapping' phase timestamp ([#1092](https://github.com/bigstack-oss/cubecos/pull/1092)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Import builtin glance images at set_ready, not at boot ([#1140](https://github.com/bigstack-oss/cubecos/pull/1140)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Restore recorded VMs even when health repair is opted out ([a8aa168](https://github.com/bigstack-oss/cubecos/commit/a8aa1684f852e08d25a13eff3b9911006e724c54)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Gate the health monitors during a planned cluster stop ([23e89d9](https://github.com/bigstack-oss/cubecos/commit/23e89d98e7c402c0937a1fa167d3187d073ca466)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Complete a planned stop instead of abandoning it ([70f935a](https://github.com/bigstack-oss/cubecos/commit/70f935ade2e863712cabefbdbb9d8cac6312cd96), [closes #1330](https://github.com/bigstack-oss/cubecos/issues/1330)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Cmd

- Bound remote ssh + command so a wedged node can't hang cmd() ([#1065](https://github.com/bigstack-oss/cubecos/pull/1065)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Cube_scan

- Declare it as the provider of the config globals ([baf8b21](https://github.com/bigstack-oss/cubecos/commit/baf8b21356adfe9d223653dabdf52f6536febb6a)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Cubectl

- Don't panic while reporting an error ([#1126](https://github.com/bigstack-oss/cubecos/pull/1126)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Cubesys

- Keep the operator opt-out markers across an upgrade ([df27cf4](https://github.com/bigstack-oss/cubecos/commit/df27cf4e9b54309310ee17a29353fd8d4db8d944)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Cyborg

- Pin the venv privsep-helper so the agent can discover devices ([fc62e3b](https://github.com/bigstack-oss/cubecos/commit/fc62e3b717c4480bb89c6efc7dd042c648e57478)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop dead config and stop overriding [nova]/[placement] auth ([0d7c80d](https://github.com/bigstack-oss/cubecos/commit/0d7c80d0ead169cd58b01a2e773fae6144fe0510)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Install the osc plugin into the system python as well ([faeb928](https://github.com/bigstack-oss/cubecos/commit/faeb928ec21b9b11820435754bb167c0c6d4d59e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Register the oslo.policy options in cyborg-status ([d995c4a](https://github.com/bigstack-oss/cubecos/commit/d995c4ac9fcccc3af145b28734eb3a08d459c8ca)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Backport the microversion header parsing fix from zed ([e714cb8](https://github.com/bigstack-oss/cubecos/commit/e714cb8dab65159352484758c13cf179d9091211)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop the trailing space from the api host_ip key ([7df2ad6](https://github.com/bigstack-oss/cubecos/commit/7df2ad6d54045e366422e53c6c7c53293da9ec08)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Hold the read scope so pooled connections are not abandoned ([382d8e6](https://github.com/bigstack-oss/cubecos/commit/382d8e66ee9eab139ae623fdd1a1fe75a5a51665)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Designate

- Indent the binary link recipe lines with tabs ([68e1e12](https://github.com/bigstack-oss/cubecos/commit/68e1e12944e4f64b1503479f81c5b6ce363ab70f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Run the patched binaries with the venv interpreter ([9dcc0fc](https://github.com/bigstack-oss/cubecos/commit/9dcc0fcec3897dc4b5d49eda42985d749b88a004)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Install designate.conf.def as a file, not a directory ([83d70b3](https://github.com/bigstack-oss/cubecos/commit/83d70b30ae88af85caf0991273327a522323f56b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop config options removed upstream and move quotas/reports to the admin API ([ca2a0c1](https://github.com/bigstack-oss/cubecos/commit/ca2a0c12964ab4eb2dffa169ffe5da9102e6b030)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Events

- Drop the dup category tag that 400s hex_log_event points; quiet influx flux notices ([d1634d3](https://github.com/bigstack-oss/cubecos/commit/d1634d3ef8600f200a8f62cb01d2f94c5c5bf1e7)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Fixpack

- Missing pre/post install/rollback actions ([#1122](https://github.com/bigstack-oss/cubecos/pull/1122)) by [@leechienpang](https://github.com/leechienpang)
- Re-make triggers target re-build ([#1137](https://github.com/bigstack-oss/cubecos/pull/1137)) by [@leechienpang](https://github.com/leechienpang)

#### Fts

- Retry peer ceph mon-IP resolution during parallel apply ([d9714cc](https://github.com/bigstack-oss/cubecos/commit/d9714cc619cdb28ce87b4680fb4e64d46ff2be7b)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Fan out octavia peer port creation from the master ([8515a97](https://github.com/bigstack-oss/cubecos/commit/8515a97e8594a31b059a7a920d92c9c2a9e49110)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Decouple keycloak SAML-metadata gate and retry helm upgrade ([c51ec5c](https://github.com/bigstack-oss/cubecos/commit/c51ec5c1126b999cf56b2908e662c493bed12db8)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Restart cinder-volume only on the master during apply ([#1197](https://github.com/bigstack-oss/cubecos/pull/1197)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Init config-history git per-node once ready, over local cephfs (#1195) ([f458742](https://github.com/bigstack-oss/cubecos/commit/f458742c11eb64f7854ff0e0dea33acfd194f882)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Create manila service network once, before manila-share starts (#1195) ([3095250](https://github.com/bigstack-oss/cubecos/commit/309525008053c22ef8c5e8fd83247faf9bec7106)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- DB/OVN connection resilience across set_ready reconfig (#1195) ([#1213](https://github.com/bigstack-oss/cubecos/pull/1213)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Set_ready_reconcile trigger to heal ovn-controller ([36c7d37](https://github.com/bigstack-oss/cubecos/commit/36c7d37df09b74b24bafb8879896953512798c6d)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Gate manila service-network ensure on OVN NB readiness ([#1267](https://github.com/bigstack-oss/cubecos/pull/1267)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Git

- Preserve setuid/setgid modes across rootfs git checkouts ([#1212](https://github.com/bigstack-oss/cubecos/pull/1212)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Converge /.git init in the background, drop its health check ([bdcb0f3](https://github.com/bigstack-oss/cubecos/commit/bdcb0f30c5aca1134fdabff026a96465b711301c)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Glance

- Perform the glob expansion inside the rootfs ([7de1f48](https://github.com/bigstack-oss/cubecos/commit/7de1f48271008686059db5ac3687ecfd55d7997d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Install rootwrap filters for glance_store and os-brick ([9d07cda](https://github.com/bigstack-oss/cubecos/commit/9d07cdac07587fd68bb5b1b481d3c241c6b478f6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Perform the glob expansion inside the rootfs for chown ([8127158](https://github.com/bigstack-oss/cubecos/commit/812715849a6cd6a781b66e768e5e60e8aa476107)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add more missing dependencies for glance ([b3acbb5](https://github.com/bigstack-oss/cubecos/commit/b3acbb518635ca763e2cad8a7b42b67388c15016)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Build ceph bindings for glance to be run under python 3.10 ([e8cadd2](https://github.com/bigstack-oss/cubecos/commit/e8cadd2f384f325596308ec25f552d7435562b84)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Provide dns resolution capabilities for downloading the ceph source tarball ([3ecf18e](https://github.com/bigstack-oss/cubecos/commit/3ecf18eb2a90bb69e1d6922c52e3b924199b2886)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Prepend the venv bin to rootwrap exec_dirs ([422e603](https://github.com/bigstack-oss/cubecos/commit/422e60347958ad4e790df799aaf3c02f577c2816)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Gpu

- Match uppercase GPU when parsing util_gpu in gpu stats ([#1017](https://github.com/bigstack-oss/cubecos/pull/1017)) by [@SekiXu](https://github.com/SekiXu)
- Drop stale Nova drop-in entries when a card leaves sriovVgpu (#904) ([232118b](https://github.com/bigstack-oss/cubecos/commit/232118b821317c2d76cc809ea0805972dc08aa6f)) by [@SekiXu](https://github.com/SekiXu)
- Clear per-VF vgpu type before zeroing sriov_numvfs on unset ([5d1efa9](https://github.com/bigstack-oss/cubecos/commit/5d1efa93a6c231e38a130e41fd40465b96342fc9)) by [@SekiXu](https://github.com/SekiXu)
- Use sriov-manage -d instead of raw sysfs write to unset sriovVgpu ([a35aa48](https://github.com/bigstack-oss/cubecos/commit/a35aa483febfbb52ecc976d84f69332ff2d6e0f5)) by [@SekiXu](https://github.com/SekiXu)
- Retry sriov-manage on transient unbindLock contention ([522fef6](https://github.com/bigstack-oss/cubecos/commit/522fef6bd2543e051402888282142689319575f7)) by [@SekiXu](https://github.com/SekiXu)
- Use a more unique exit-code delimiter in RunSriovManageWithRetry ([44011f4](https://github.com/bigstack-oss/cubecos/commit/44011f4ffef2bc88bf94b3314ecde4c4c2a1eaab)) by [@SekiXu](https://github.com/SekiXu)
- Fail closed when sriov_totalvfs can't be read ([#1141](https://github.com/bigstack-oss/cubecos/pull/1141)) by [@SekiXu](https://github.com/SekiXu)
- Fix jq scope bug in gpu_device_list that breaks gpuCards API ([#1142](https://github.com/bigstack-oss/cubecos/pull/1142)) by [@SekiXu](https://github.com/SekiXu)
- Don't fail Commit() for a single sriovVgpu card's apply hiccup ([#1160](https://github.com/bigstack-oss/cubecos/pull/1160)) by [@SekiXu](https://github.com/SekiXu)
- Quote exit-code delimiter in RunSriovManageWithRetry ([d432254](https://github.com/bigstack-oss/cubecos/commit/d4322543b3600587fafddbd5e8d0bc9fc7fb12ea)) by [@SekiXu](https://github.com/SekiXu)
- Bind pgpu passthrough atomically and let a card leave pgpu ([4eb0e52](https://github.com/bigstack-oss/cubecos/commit/4eb0e52e8b6b2c361d066dfcaa1504a180244083)) by [@SekiXu](https://github.com/SekiXu)
- Stop gpu_device_list silently reporting an empty device list ([#1175](https://github.com/bigstack-oss/cubecos/pull/1175)) by [@SekiXu](https://github.com/SekiXu)
- Release a MIG-backed card's VFs before disabling MIG mode (#905) ([c4becf2](https://github.com/bigstack-oss/cubecos/commit/c4becf23accca9bf06706f4f4ed28d7567fa2273)) by [@SekiXu](https://github.com/SekiXu)
- Anchor nvidia-smi parsing so one card cannot blank a node ([87c681d](https://github.com/bigstack-oss/cubecos/commit/87c681dcee3d529dcbf1997c2aa0d4fd553e97bc), [refs #824](https://github.com/bigstack-oss/cubecos/issues/824), [refs #825](https://github.com/bigstack-oss/cubecos/issues/825)) by [@SekiXu](https://github.com/SekiXu)
- Accept both spellings of the utilization GPU leaf ([#1228](https://github.com/bigstack-oss/cubecos/pull/1228), [refs #824](https://github.com/bigstack-oss/cubecos/issues/824), [refs #825](https://github.com/bigstack-oss/cubecos/issues/825), [refs #826](https://github.com/bigstack-oss/cubecos/issues/826)) by [@SekiXu](https://github.com/SekiXu)
- Report vGPU capability for cards bound to vfio-pci ([#1282](https://github.com/bigstack-oss/cubecos/pull/1282), [closes #1263](https://github.com/bigstack-oss/cubecos/issues/1263)) by [@SekiXu](https://github.com/SekiXu)
- Stop creating example flavors that can never boot ([#1283](https://github.com/bigstack-oss/cubecos/pull/1283), [closes #1264](https://github.com/bigstack-oss/cubecos/issues/1264)) by [@SekiXu](https://github.com/SekiXu)

#### Grafana

- Keep a VM's vGPU history in one series across host reboots ([#1286](https://github.com/bigstack-oss/cubecos/pull/1286)) by [@SekiXu](https://github.com/SekiXu)

#### Ha

- Survive VIP failover -- deadline API sessions, sweep stale flows ([#1102](https://github.com/bigstack-oss/cubecos/pull/1102)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Vaw always follows vip + escalate etcd repair to a quorum-guarded member reseed ([267a8f1](https://github.com/bigstack-oss/cubecos/commit/267a8f114f7b6dfd9ef43c2214cf5c3ecd774bf1)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Hacluster

- Strengthen remote compute repair logics ([#1115](https://github.com/bigstack-oss/cubecos/pull/1115)) by [@leechienpang](https://github.com/leechienpang)

#### Haproxy

- Set timeout server on galera listen so idle DB connections survive ([e78d9e1](https://github.com/bigstack-oss/cubecos/commit/e78d9e1a6f9302193377ff023b4cb83abc0648d1)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Inject security headers on cyborg api vip listener ([a00b42b](https://github.com/bigstack-oss/cubecos/commit/a00b42bd13600e0d86168621388ee383011c3e81)) by [@SekiXu](https://github.com/SekiXu)
- Inject security headers on opensearch vip listener ([#1081](https://github.com/bigstack-oss/cubecos/pull/1081)) by [@SekiXu](https://github.com/SekiXu)

#### Health

- Don't spend the auto-repair maxerr budget while cluster is not ready ([#1063](https://github.com/bigstack-oss/cubecos/pull/1063), [closes #1062](https://github.com/bigstack-oss/cubecos/issues/1062)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Make boot-time auto-repair robust on multi-node power-up ([#1058](https://github.com/bigstack-oss/cubecos/pull/1058)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Storage services auto-recover after a maintenance cycle ([59569da](https://github.com/bigstack-oss/cubecos/commit/59569dadf75cc16dc35e9684bbd147776695d5d5)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Back off past maxerr instead of giving up auto-repair forever ([819e9d4](https://github.com/bigstack-oss/cubecos/commit/819e9d4d0c07fa0b61638f1173d928229362f91c)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Check node clock time differences in parallel ([f759e38](https://github.com/bigstack-oss/cubecos/commit/f759e3823549cb8db9c511f1a202749317737453)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Repair OVN metadata by nb_cfg progress, not the Alive flag ([dfda2f5](https://github.com/bigstack-oss/cubecos/commit/dfda2f5c309901f6b44ca00cdc3696f6c6ca807b)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Report instance-HA off, an unbound hm0 port and load balancers in ERROR ([765ba73](https://github.com/bigstack-oss/cubecos/commit/765ba731785edb46c703d4686ab4a6e280fe5065)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Stop manila reporting share down on every multi-backend cluster ([b2c864e](https://github.com/bigstack-oss/cubecos/commit/b2c864e53b9e7e9fe86c6e0dd89606163e1ad85b), [closes #1317](https://github.com/bigstack-oss/cubecos/issues/1317)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Heat

- Keep python3-heatclient for the system openstack client ([454805c](https://github.com/bigstack-oss/cubecos/commit/454805c4cfe2c166dbbed2e173b20a36fac84725)) by [@SekiXu](https://github.com/SekiXu)
- Restore the heat_revision that heat-dist.conf carried ([25a3196](https://github.com/bigstack-oss/cubecos/commit/25a319603e960e6eeeac415fdd62ede74f43c170)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Heavyfs

- Set the updated source rpm repo url after centos stream 9 sig url restructuring ([07827d5](https://github.com/bigstack-oss/cubecos/commit/07827d526801703cadde8d9f633bab4592407a74)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Escape the dollar sign in the makefile ([fa25e36](https://github.com/bigstack-oss/cubecos/commit/fa25e36545e02257726797f98ff3131a7b1f579c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Enable dns when downloading packages in component.mk ([807147d](https://github.com/bigstack-oss/cubecos/commit/807147d49d9d4dbebf0e87be26250ab129fe7dce)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move dns resolv conf copy step into keystone.mk ([425df7f](https://github.com/bigstack-oss/cubecos/commit/425df7f742568326ac88517316c07a9d456b38c8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use the installed constraint file inside the chroot environment while installing package wheel instead of the source code ([4bc5a16](https://github.com/bigstack-oss/cubecos/commit/4bc5a164af5ed44f10c86ec3bc2fff5e188c2650)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Stop installing scciclient into the system python ([1ebb943](https://github.com/bigstack-oss/cubecos/commit/1ebb94336440609932d2e1facdb1cc97b4e6b984)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Apply the venv setuptools pin at creation ([235f96e](https://github.com/bigstack-oss/cubecos/commit/235f96eb024b536a31bb46185520ebc69ea74800)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex

- Hex_config parallel cluster_start + rootfs helpers (hex_log_event, air-gapped dnf-makecache) ([#1053](https://github.com/bigstack-oss/cubecos/pull/1053)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_config

- Derive cube_scan's role from the tuning, not the observer static ([ab92e95](https://github.com/bigstack-oss/cubecos/commit/ab92e9550c3d69479508f993f892970c1a4a52c1), [refs #610](https://github.com/bigstack-oss/cubecos/issues/610)) by [@SekiXu](https://github.com/SekiXu)

#### Hex_sdk

- Health_clock_check has no effect #723 ([#724](https://github.com/bigstack-oss/cubecos/pull/724)) by [@leechienpang](https://github.com/leechienpang)
- Avoid word splitting while parsing the node list ([#766](https://github.com/bigstack-oss/cubecos/pull/766)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Probe the barbican units behind the httpd 9311 proxy ([666fa59](https://github.com/bigstack-oss/cubecos/commit/666fa592aab7cf11aab63859a1491cb8b348cfc8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Horizon

- Escape the timezone without assuming two components ([#1173](https://github.com/bigstack-oss/cubecos/pull/1173)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Install horizon after the source-installed dashboard plugins ([7e68de3](https://github.com/bigstack-oss/cubecos/commit/7e68de35938df519361565aa0310ff28f241cc2d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Correct the affected-plugin list in the ordering comment ([156020b](https://github.com/bigstack-oss/cubecos/commit/156020bf4b9f6adb67fa36f880711d4b13702937)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Build horizon's XStatic sdists against the venv's pinned setuptools ([f61e7c5](https://github.com/bigstack-oss/cubecos/commit/f61e7c5e9848c761dc36a0cbd2ed03654312b4ef)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Rotate /var/log/horizon through hex ([655e263](https://github.com/bigstack-oss/cubecos/commit/655e263be3a2cafe0d52f2e9dbd31a0a08fc1985)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Run cube_edge_cfg's dashboard steps in the venv ([1583980](https://github.com/bigstack-oss/cubecos/commit/1583980895171c0ae550f2c9531f4abd497a9af4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Fail the build when a policy dump fails ([a51da4a](https://github.com/bigstack-oss/cubecos/commit/a51da4a3f640333f9a679f02cee1d1a5503c9cf2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Collect static without --clear ([4ab294d](https://github.com/bigstack-oss/cubecos/commit/4ab294d29fa94dd610961a36dbf8d981157e6a30)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Give manage.py the shebang its mode implies ([be454e2](https://github.com/bigstack-oss/cubecos/commit/be454e2929d3cf9db43ba9f2ffadf4204de5bb0f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Influxdb

- Require ceph before enabling the influx mgr plugin ([#1133](https://github.com/bigstack-oss/cubecos/pull/1133)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Ironic

- Keep the existing config when cluster addresses are unresolved ([75bcc41](https://github.com/bigstack-oss/cubecos/commit/75bcc41125216aebb896f2c94df7aa4710c3bb0d), [refs #610](https://github.com/bigstack-oss/cubecos/issues/610)) by [@SekiXu](https://github.com/SekiXu)
- Install ironic-lib's rootwrap filter set ([449b37b](https://github.com/bigstack-oss/cubecos/commit/449b37b9988597fdabcd9a2a23357cfe7ad89602), [refs #610](https://github.com/bigstack-oss/cubecos/issues/610)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Jail

- Remove trivy from jail since old versions are missing and it is not used ([86947c3](https://github.com/bigstack-oss/cubecos/commit/86947c3defa5d35c41f9b8962c1932e5a2573661)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Re-org CI make targets ([#1261](https://github.com/bigstack-oss/cubecos/pull/1261)) by [@leechienpang](https://github.com/leechienpang)
- Give the jail a valid machine-id ([#1415](https://github.com/bigstack-oss/cubecos/pull/1415)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### K3s

- Update the image tags of ceph csi for offline environments ([#874](https://github.com/bigstack-oss/cubecos/pull/874)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Parse every ceph monitor, and stop re-importing present CSI images ([fdd9c33](https://github.com/bigstack-oss/cubecos/commit/fdd9c3321cbe7907ab4b8a90b36116bfb7cb9171)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Bind the engine socket at /run, which crun can resolve ([cb0242e](https://github.com/bigstack-oss/cubecos/commit/cb0242e297eb951955f2248c14ec1badde9d99ab)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Kafka

- Use a more permanent download link for kafka tarball ([#1117](https://github.com/bigstack-oss/cubecos/pull/1117)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Whitelist the envi four-letter word for the octavia jobboard ([9c7ef79](https://github.com/bigstack-oss/cubecos/commit/9c7ef79d85865d0febe1790f9b39aff8ebd4bbf5)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Keycloak

- Gate the commit on the SAML metadata download ([ac84ed6](https://github.com/bigstack-oss/cubecos/commit/ac84ed6f47f706114156a974b4a82c517d7858a3)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Keep wildfly 17 and quarkus 18 off one schema during a rolling upgrade ([8868ad8](https://github.com/bigstack-oss/cubecos/commit/8868ad888a40e675713da84915dfa7a49ecd21dd)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Scope the cos-ui theme to the master realm login page ([f91a3b5](https://github.com/bigstack-oss/cubecos/commit/f91a3b57873a97cf8870ed7590806f2cffa6fd31), [closes #187](https://github.com/bigstack-oss/cubecos/issues/187)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Keystone

- Declare keystone_idp's dependency on keystone ([#1169](https://github.com/bigstack-oss/cubecos/pull/1169)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Handle module pkg_resources not found ([3983f62](https://github.com/bigstack-oss/cubecos/commit/3983f62890b4822b7e4ef32f668e054b22f00aa3)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Handle module pymysql not found ([e51a44e](https://github.com/bigstack-oss/cubecos/commit/e51a44ee9c1e390b620c9ce4344b7be31a9b4217)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add more missing dependencies for keystone ([477456d](https://github.com/bigstack-oss/cubecos/commit/477456dd0b22223bcece81c19ebf946f7128e5c9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Install the c library for python-ldap ([245ffbf](https://github.com/bigstack-oss/cubecos/commit/245ffbf7732a7c830405f3cb935b50cd24c75dae)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Handle module confluent_kafka not found ([05d12b8](https://github.com/bigstack-oss/cubecos/commit/05d12b8707e1e9d9fd9a2153ee0d459b9693bc38)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Write the logrotate config for keystone ([10fd842](https://github.com/bigstack-oss/cubecos/commit/10fd84274c36f5856d66e04654769d7f98771377)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Create the soft links in the right rootfs ([5b91028](https://github.com/bigstack-oss/cubecos/commit/5b910289e08457f69d42e382834220ad89e3d0e9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Restore mellon's assertion across the gunicorn proxy ([d8a59d7](https://github.com/bigstack-oss/cubecos/commit/d8a59d751db50cb023e1a488816cb1e51d7a9e02)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Keystone,glance

- Make the published debug tunings actually work ([24bfa98](https://github.com/bigstack-oss/cubecos/commit/24bfa9801d37535a619bea668d5584d96411dd26)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Logstash

- Start after influxdb/kapacitor to stop boot-time error flood ([16f884a](https://github.com/bigstack-oss/cubecos/commit/16f884a8cca4af2fc47318f04191a98092e510a3)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Collect mariadb's error log now that it no longer reaches journald ([12c6ef7](https://github.com/bigstack-oss/cubecos/commit/12c6ef78ccb1425715f84fc32488f0a2e3ba9ebf)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Manila

- Rebase the nfs export helper patch onto the antelope wheel ([7fff303](https://github.com/bigstack-oss/cubecos/commit/7fff303aa0210c52ecdefde9fb0c3f17a9cbd620)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Mariadb

- Resolve dependency conflicts on mariadb-connector-c with rpms from mariadb official repo ([bbf8957](https://github.com/bigstack-oss/cubecos/commit/bbf895711e45d58881baa893556315b0d7d0bc0c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- No need to handle a default config file after switching the rpm repo ([14b7047](https://github.com/bigstack-oss/cubecos/commit/14b704787ad2bec93085b7eec198a5b818278b52)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Masakari

- Only run hostmonitor under HA ([13bc0c7](https://github.com/bigstack-oss/cubecos/commit/13bc0c7bffc632ade09dc63191c9377512ccc91f)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Gate processmonitor too + robust HA read (complete hostmonitor flood fix) ([36ba6f5](https://github.com/bigstack-oss/cubecos/commit/36ba6f5f91233e6b6b49efa7536b9394a45542ba)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Probe corosync via corosync-cfgtool, not a tcpdump packet sniff ([#1030](https://github.com/bigstack-oss/cubecos/pull/1030)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Survive concurrent VM crashes and cover all instances by default ([#1098](https://github.com/bigstack-oss/cubecos/pull/1098)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Run masakari-manage from the venv symlink ([6001089](https://github.com/bigstack-oss/cubecos/commit/60010897e628031aeea5490090f1c7aa58d667c6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Keep masakari in python 3.9 for horizon's policy namespace ([9dbfe2c](https://github.com/bigstack-oss/cubecos/commit/9dbfe2c8d603995307d00f68f0d12a5d37c967a3)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Pin oslo.privsep's helper to the venv ([5133467](https://github.com/bigstack-oss/cubecos/commit/513346717cf97ba60b44a96fb21968da76fe56f7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Set hostname instead of the deprecated host option ([31305c7](https://github.com/bigstack-oss/cubecos/commit/31305c70740aef5c9c8b35e2ef61f6e8ac6d8f97)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Match the monitors at their venv paths in process_list ([6dc1f70](https://github.com/bigstack-oss/cubecos/commit/6dc1f7057c9f1524451675e6832be593f10d7e86)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Gate host-failure recovery on nova's own preconditions ([1fcfec9](https://github.com/bigstack-oss/cubecos/commit/1fcfec9ab74bd7867289eed26ec5a146e93ab48b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Miscellaneous

- Upgrade ruby version ([62d978a](https://github.com/bigstack-oss/cubecos/commit/62d978ab1a18d1d32fb269f4c5a5a0a71b45a729)) by [@raven-pan](https://github.com/raven-pan)
- Cut steady-state log flooding and pe-error disk churn ([1645e30](https://github.com/bigstack-oss/cubecos/commit/1645e30f233c5f6b1e90f790e187b6ff7cdb1048), [refs #1029](https://github.com/bigstack-oss/cubecos/issues/1029)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Cut steady-state log flooding on healthy clusters, phase 2 ([#1104](https://github.com/bigstack-oss/cubecos/pull/1104)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Don't disruptively repair pacemaker while cluster is mid-transition ([741f409](https://github.com/bigstack-oss/cubecos/commit/741f4093cab7dec81b4a18a05998f8d027a53049)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- One module's commit failure must not skip the rest of bootstrap ([b2fb63b](https://github.com/bigstack-oss/cubecos/commit/b2fb63b40320bcbf9febace4b4252adb2a50029d)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Monasca

- Ib_network check skips devices without a counters dir ([927af3b](https://github.com/bigstack-oss/cubecos/commit/927af3b50413a37b98c34d502e97915b6b88c0d3)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Rdt_l3 parses multi-vCPU pqos rows (CORE column "err") ([936a68b](https://github.com/bigstack-oss/cubecos/commit/936a68b11a2b7791466993bbab7663aee7a6a916)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Sudo-grant ipmitool/pqos so the agent plugins can read hardware ([#1034](https://github.com/bigstack-oss/cubecos/pull/1034)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Pin the apache server-status check to 127.0.0.1 ([48b2614](https://github.com/bigstack-oss/cubecos/commit/48b26148b5009cd9c8ac8f95e25cde82fc376375)) by [@raven-pan](https://github.com/raven-pan)
- Rebase the agent and persister patches onto the shipped wheels ([d40eca7](https://github.com/bigstack-oss/cubecos/commit/d40eca77c0cdc332e49544b69ddf7f60d604ca14)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop the system python copy of the monasca client ([0f342d4](https://github.com/bigstack-oss/cubecos/commit/0f342d474f67e4a04b6416261d3c6c3baf3ff7d3)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Mongodb

- Set the correct file ownership for mongodb replica set key file ([#722](https://github.com/bigstack-oss/cubecos/pull/722)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Multipath

- Wait for multipathd, and never fail the commit on a map refresh ([#1127](https://github.com/bigstack-oss/cubecos/pull/1127)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Mysql

- Rotate the error log mariadb actually writes, and create its directory ([2107478](https://github.com/bigstack-oss/cubecos/commit/21074787bf3e4a87944411aeb7b9d06fa173ffc9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Point wsrep_provider at the galera-4 library path ([22c2922](https://github.com/bigstack-oss/cubecos/commit/22c2922e00043df479db0a16c06a57f3714571d6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bound mariadb's stop and let systemd enforce it ([cbd6b62](https://github.com/bigstack-oss/cubecos/commit/cbd6b62841dc9465530e5e382addb768272eec92)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Do not bootstrap galera over a live primary ([d01ba79](https://github.com/bigstack-oss/cubecos/commit/d01ba792d17798fee5def7b62d56d48edc68d9ea)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Neutron

- Provide the dns capability while downloading packages for neutron-vpnaas ([b1f0663](https://github.com/bigstack-oss/cubecos/commit/b1f06639e3ac3c280fc3234d2abe734888335020)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop the line for copying not needed sysctl conf ([88d20c4](https://github.com/bigstack-oss/cubecos/commit/88d20c43ddd64b800e6c074f890e65b850409481)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Leave the panel installation into horizon for neutron-vpnaas-dashboard till horizon upgrade ([49babd0](https://github.com/bigstack-oss/cubecos/commit/49babd0ff9884373ecb24615453b8c3ff36754ed)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Copy files to the right directory ([ba5790b](https://github.com/bigstack-oss/cubecos/commit/ba5790b922982f7050a5531b8785af5013a849bd)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make ln steps idempotent while installing neutron ([2f22f18](https://github.com/bigstack-oss/cubecos/commit/2f22f1897e3d0f0ae92326cc2567a472c610515b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Install neutron-dist.conf under the chroot environment ([d6d1a73](https://github.com/bigstack-oss/cubecos/commit/d6d1a73a305e4d7e0490fa07cd6ca8c35cb64164)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Link neutron-vpnaas binaries ([6bf9522](https://github.com/bigstack-oss/cubecos/commit/6bf952257662182baa73b8c02cf0d5cf9bb301d3)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop conflicting networking-ovn pip package, add networking-baremetal ([b830b38](https://github.com/bigstack-oss/cubecos/commit/b830b38b4706e2cd670ef9718f0bfd1ddeea07c4), [closes #615](https://github.com/bigstack-oss/cubecos/issues/615)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Modernize designate auth to keystoneauth password plugin ([3f6df34](https://github.com/bigstack-oss/cubecos/commit/3f6df341ff689313cc44c916e13f90217d16db3f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Pin networking-baremetal to the 2023.1 series ([6111c77](https://github.com/bigstack-oss/cubecos/commit/6111c77ecd4daf392cb683b24a916e787100f4d1)) by [@SekiXu](https://github.com/SekiXu)
- Stop loading two dns extension drivers at once ([1f0af8b](https://github.com/bigstack-oss/cubecos/commit/1f0af8bf9c3ce961c6f955fcad578deb080e2981)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Repoint the vpn wrapper rootwrap filter at /usr/bin ([2d402bc](https://github.com/bigstack-oss/cubecos/commit/2d402bc9d88bc83de2710cb1a3b6d2f331b77c18)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Keep the port API alive across a mixed-version roll ([01b019f](https://github.com/bigstack-oss/cubecos/commit/01b019f8d03a5739d4a7a94ae8fb6063dbac321a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Detect and repair port status stuck DOWN against OVN ([a8d31b5](https://github.com/bigstack-oss/cubecos/commit/a8d31b598e07f1f6afb9b8f53a8da628f4aa83ca)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Nginx

- SPA cache contract for the cube-cos-ui vhost ([#1138](https://github.com/bigstack-oss/cubecos/pull/1138)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Nova

- Route live migration over overlay + durable convergence config ([#1032](https://github.com/bigstack-oss/cubecos/pull/1032)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Enable volume_use_multipath only when an FC/iSCSI backend exists ([5025598](https://github.com/bigstack-oss/cubecos/commit/50255985657903823716104190a2e15b78dca742)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Add the missing dependency novnc for openstack-nova-novncproxy ([1aba654](https://github.com/bigstack-oss/cubecos/commit/1aba654d57ac37d46553db4130329edde414e8ed)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Temporarily separate privsep-helper from both yoga (python 3.9) and antelope (python 3.10) to allow root disk based vm creation work ([19e0a4e](https://github.com/bigstack-oss/cubecos/commit/19e0a4e1f44131150b261dbb359bcedd5fa564a8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add back the dropped file descriptor limit lifting line for nova compute and nova conductor ([9f6838a](https://github.com/bigstack-oss/cubecos/commit/9f6838a25138ce98ac3485ef8f1516c8496ad641)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Lock the whole libvirt tree so the -14 pin actually holds ([5f85b77](https://github.com/bigstack-oss/cubecos/commit/5f85b7794a68096055114caab0fd787c0386097c)) by [@SekiXu](https://github.com/SekiXu)
- Link the venv privsep-helper into /usr/bin ([f5157b0](https://github.com/bigstack-oss/cubecos/commit/f5157b0eaa17ce67b4a26f6e10e45c54cb14602c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Stop recording a failed online_data_migrations as complete ([299a4b5](https://github.com/bigstack-oss/cubecos/commit/299a4b58135cd2c8fd4095c4b39f6f07ccfc9878)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Define the ceph libvirt secret on every compute node ([6fadd29](https://github.com/bigstack-oss/cubecos/commit/6fadd29b611f5fa4f2a060add90d6fb3302f2984)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Restore placement log ownership after an upgrade ([2881a74](https://github.com/bigstack-oss/cubecos/commit/2881a74684c07aaef234602b99a5449ae7666564)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Tolerate a back-levelled BDM during a mixed-version roll ([7f0cc33](https://github.com/bigstack-oss/cubecos/commit/7f0cc339ff2ab2b3941fe219d1288408b5f75c43)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Carry compute_id across the root-slot switch on upgrade ([441257d](https://github.com/bigstack-oss/cubecos/commit/441257dbfb1852f456d2cfb83f2dd2270142bc5b)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Octavia

- Recover octavia-hm0 on non-master nodes via health repair ([#1055](https://github.com/bigstack-oss/cubecos/pull/1055)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Derive the health manager address from the mgmt cidr ([51305c9](https://github.com/bigstack-oss/cubecos/commit/51305c9707fe673614cf7f24ccb09690ab00efbd), [refs #616](https://github.com/bigstack-oss/cubecos/issues/616)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Register the oslo_policy opts octavia-status reads ([6c40c1f](https://github.com/bigstack-oss/cubecos/commit/6c40c1fd2a3140b61af966a4ad4fdd36be37ff4a), [refs #616](https://github.com/bigstack-oss/cubecos/issues/616)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Point amphora heartbeats at every controller, not just one ([938db39](https://github.com/bigstack-oss/cubecos/commit/938db3965275b8d0cec00d29837620a9dfbc8134)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Keep masakari from evacuating amphorae ([19bdfcc](https://github.com/bigstack-oss/cubecos/commit/19bdfcc214401f9b2a0cc6f6b57f883ed1c1398c)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Land the CA on peers where octavia.conf expects it ([793d5f0](https://github.com/bigstack-oss/cubecos/commit/793d5f0e47271b1502165584bc64ab2f79261d70)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Stop non-master commits wiping the lb-mgmt ids ([6e34e3b](https://github.com/bigstack-oss/cubecos/commit/6e34e3b65e3fb4d33108a0458eb1d89b0f29b2d8)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Opensearch

- Skip opensearch rpm repo metadata gpg key checks since upstream key signing did not match ([#1061](https://github.com/bigstack-oss/cubecos/pull/1061)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Power

- Retry rejected drain migrations; record running VMs up front for poweroff restore ([43505f7](https://github.com/bigstack-oss/cubecos/commit/43505f7b7dd678232d9af92b5f48e58f47a1df51)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Powercycle

- CLI cluster powercycle sequence #719 ([#720](https://github.com/bigstack-oss/cubecos/pull/720)) by [@leechienpang](https://github.com/leechienpang)

#### Rabbitmq

- Restore the erlang and rabbitmq-server version locks ([c9e45bd](https://github.com/bigstack-oss/cubecos/commit/c9e45bd076e4b08d93a1d10c15f66661906488e3)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Cap the broker start timeout so a wedged start can't stall bootstrap ([#1403](https://github.com/bigstack-oss/cubecos/pull/1403)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Roll

- Print the CLI verb, not the internal roll kind ([#1302](https://github.com/bigstack-oss/cubecos/pull/1302), [closes #1334](https://github.com/bigstack-oss/cubecos/issues/1334)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Rolling

- Stand down auto-repair during a roll, and survive a failed boot ([53b8b2b](https://github.com/bigstack-oss/cubecos/commit/53b8b2b678c363fc9c8d6f66f566fafaf1e88945)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Hardening from the first consolidated rolls on the sky lab ([c71ba12](https://github.com/bigstack-oss/cubecos/commit/c71ba121e8dac9ea36dd58a8c58c93242ea113ea)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Drive the roll from the VIP holder and drop cephfs from live migration ([#1125](https://github.com/bigstack-oss/cubecos/pull/1125)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Sanitize the pause reason before logging the event ([2302b71](https://github.com/bigstack-oss/cubecos/commit/2302b7151d1cf52c234baa2571f2faa3353e789c)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Survive a wedged cephfs client at staging time ([069e1c1](https://github.com/bigstack-oss/cubecos/commit/069e1c1da8be2ea82d13e7ea028aa47d10f3301f)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Continue must not re-pause on a stale deadline or re-roll a done node ([#1157](https://github.com/bigstack-oss/cubecos/pull/1157)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Init config-history git repo per-node, once per slot ([#1164](https://github.com/bigstack-oss/cubecos/pull/1164)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Restore libvirt secrets on compute nodes during upgrade ([f880eb6](https://github.com/bigstack-oss/cubecos/commit/f880eb645f62d05d2802f8a824fc42bee05c3a6b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Unbreak power_roll_status_json jq quoting ([b8bb35b](https://github.com/bigstack-oss/cubecos/commit/b8bb35b954ee9cd6b7adee71702ce670f45cf476)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Hand off ceph-mgr and verify dashboard before rebooting its node ([c7ecb02](https://github.com/bigstack-oss/cubecos/commit/c7ecb0206c65b7bd28838f8424ac1a473f261323)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Gate each drain on the rejoined node's APIs actually serving ([b2eca68](https://github.com/bigstack-oss/cubecos/commit/b2eca68fdc6fce58ea4ede90081b3714d625d296)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Scope the API-ready gate to control nodes ([#1392](https://github.com/bigstack-oss/cubecos/pull/1392), [closes #1391](https://github.com/bigstack-oss/cubecos/issues/1391)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Rolling-upgrade

- Gate on storage-ready targets, never hard-reboot a VM, evacuate the active MDS first ([8ec5419](https://github.com/bigstack-oss/cubecos/commit/8ec5419aa9628fe7f44e7d2b9206397902526a85)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Drain correctness -- host-scoped list, drain-host gate, loud successor probe, no false success ([5b0c05f](https://github.com/bigstack-oss/cubecos/commit/5b0c05fe0eaaf4cc842cc62fd94f76a3a624d8ef)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Rootfs

- Ensure pkg sizes are under 4 gib ([0f48545](https://github.com/bigstack-oss/cubecos/commit/0f485459f1f19bcb47a34adee314f04ca25a57e9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Sdk

- Is_rolling_upgrade to handle same FW on different partitions ([#850](https://github.com/bigstack-oss/cubecos/pull/850)) by [@leechienpang](https://github.com/leechienpang)

#### Sec

- Default security to norollback ([#1180](https://github.com/bigstack-oss/cubecos/pull/1180)) by [@leechienpang](https://github.com/leechienpang)

#### Security

- Hardcode AMQP 5672 DROP, drop the opt-in tuning (cubecos-private#73) ([1272c81](https://github.com/bigstack-oss/cubecos/commit/1272c8180ba7fa14fc377d3a1c90d1a89da9c3b9)) by [@SekiXu](https://github.com/SekiXu)

#### Set_ready

- Drop redundant neutron/octavia/kafka work + align csi image tags ([#1028](https://github.com/bigstack-oss/cubecos/pull/1028), [closes #1027](https://github.com/bigstack-oss/cubecos/issues/1027)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Skyline

- Drop the system_reader_roles override for _member_ ([6ff04bc](https://github.com/bigstack-oss/cubecos/commit/6ff04bc13c9a67db5462365ae87b3c2d4fa02cc9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Telegraf

- Survive kafka-not-ready at boot instead of tripping the start-limit ([477c9fc](https://github.com/bigstack-oss/cubecos/commit/477c9fc681b7782e8250f643ba4cedefcab3044b)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Create the sflow db account only once ([556fa23](https://github.com/bigstack-oss/cubecos/commit/556fa2387f24762155fe7bd3c640b6480a36bf2a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Install the unit the 1.24 rpm no longer drops in ([53b4239](https://github.com/bigstack-oss/cubecos/commit/53b4239a24cf278a7e8b5bd9c252465973bea8a4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Pin Type=simple now that the packaged unit sets notify ([901b73d](https://github.com/bigstack-oss/cubecos/commit/901b73da8992ce0d29a305a1f9ada9e1a5b4506a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Terraform

- Use filesystem mirror to avoid checksum mismatches of patched terraform provider binaries ([#888](https://github.com/bigstack-oss/cubecos/pull/888)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Keep provider install + telemetry air-gapped ([b3efa0d](https://github.com/bigstack-oss/cubecos/commit/b3efa0d1cd3bb6a7c8ef8ac7f2479c41206eecfd)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Ui

- Hardcoded logo image paths in login template ([#979](https://github.com/bigstack-oss/cubecos/pull/979)) by [@tomaioo](https://github.com/tomaioo)
- Source Device dashboard Host variable from existing host tag ([#1018](https://github.com/bigstack-oss/cubecos/pull/1018)) by [@SekiXu](https://github.com/SekiXu)
- Write the logrotate config for ui ([10a6b02](https://github.com/bigstack-oss/cubecos/commit/10a6b0235513c891616298b0450e92c1874a62d8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Upgrade

- Keep OSDs in during a rolling upgrade; drop the end-of-roll kafka repair ([8d76ae6](https://github.com/bigstack-oss/cubecos/commit/8d76ae694e24d25971f5e5533891908c3bd302c5)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Watcher

- Keep instance_cpu_usage on the metric that actually flows ([02614a7](https://github.com/bigstack-oss/cubecos/commit/02614a7417cf993bdd1ed424d0e6975375f7f860)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Implement the stubbed Monasca datasource getters ([7eba522](https://github.com/bigstack-oss/cubecos/commit/7eba522356abc2138c2c750baed8efe103e66f0c)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Rebase the monasca and workload-balance patches onto the antelope wheel ([f1bcec9](https://github.com/bigstack-oss/cubecos/commit/f1bcec984dc51162c8857da21830f5fe1129cf97)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### <!-- 3 -->:boom: Refactor

#### Bootstrap

- Emit boot events via hex_log_event, not raw influx ([2f627e8](https://github.com/bigstack-oss/cubecos/commit/2f627e81efb4e84fb8e623b648eb4a2d685d8ba1)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Resolve kernel consoles once, one status-line helper ([2a7eff3](https://github.com/bigstack-oss/cubecos/commit/2a7eff36a2f283dd5f776a35961472c80ef25d85)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Ceph

- Stop naming the dashboard patch after the openstack release ([91f3c11](https://github.com/bigstack-oss/cubecos/commit/91f3c11d27aa2327fde0d2cbbeba477709a88cbc)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cinder

- Let hex_config manage logrotate configs for cinder ([6a9e041](https://github.com/bigstack-oss/cubecos/commit/6a9e0416a24e15219f014baab898509b4111487b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Designate

- Drop the python 3.9 designate-dashboard install ([3f3a0aa](https://github.com/bigstack-oss/cubecos/commit/3f3a0aab79ad6696733eda9f6cbfbb961477689c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Glance

- Link glance-manage under /usr/bin ([e199ade](https://github.com/bigstack-oss/cubecos/commit/e199ade56acd0347638fc00984bdfc1d5d16b0e2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use simple copying for sample configs ([9fae390](https://github.com/bigstack-oss/cubecos/commit/9fae390ffa8eeac6526aae72d11a9d00a5a9bc87)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Let hex_config manage the logrotate config of glance ([be38ef5](https://github.com/bigstack-oss/cubecos/commit/be38ef5c6d8a9ef87a339e86d22d3333fa5c5876)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use /usr/bin locations to call glance binaries ([5e1f1d8](https://github.com/bigstack-oss/cubecos/commit/5e1f1d81a562c62e5df63f9e585cb01e2da522d6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Health

- Also wrap is_sshable inside the background job to provide non-blocking parallel executions for time sensitive commands ([#1087](https://github.com/bigstack-oss/cubecos/pull/1087)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Heavyfs

- Drop the yoga python 3.9 patch tree ([dbf2017](https://github.com/bigstack-oss/cubecos/commit/dbf20177fefbad6d36da2eb81df18ab00ddbdce3)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Horizon

- Move the HORIZON_* layout variables into horizon.mk ([2fc228f](https://github.com/bigstack-oss/cubecos/commit/2fc228f97142f2752d28744f844935e20fc30059)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Keystone

- Move sample config generations from build time to simple static file copying ([3e697dc](https://github.com/bigstack-oss/cubecos/commit/3e697dc24a947d3d5574437a682346857ff93f3b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop not needed rdo keystone default port registration config ([a253e1d](https://github.com/bigstack-oss/cubecos/commit/a253e1d7966df813172f8c7fc24bf3f195b618de)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Link keystone binaries in python venv to /usr/bin/ to make it visible via path variable ([b00245c](https://github.com/bigstack-oss/cubecos/commit/b00245cde4603b44bbc98a7b80ed38c7d07ec738)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Let hex_config manage keystone log rotate ([b010673](https://github.com/bigstack-oss/cubecos/commit/b010673da314286a811ee7ea877a126939bc3f7b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop /opt/openstack-antelope/bin from the path variable ([5bb1252](https://github.com/bigstack-oss/cubecos/commit/5bb1252d2d232b062e29012e601e36dc726cae62)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop python3-mod_wsgi now that nothing hosts wsgi in httpd ([23c32ab](https://github.com/bigstack-oss/cubecos/commit/23c32ab9f47f7e81db0916e7dabbafd28aac86a8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Manila

- Mirror Cinder's storage-backend array instead of a new tuning ([#1162](https://github.com/bigstack-oss/cubecos/pull/1162)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Resolve manila-manage from the venv symlink ([64476e4](https://github.com/bigstack-oss/cubecos/commit/64476e44f276fcd00b51cdb7dbf7e94b9b33edc7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Miscellaneous

- Set gpu to passthrough mode ([#898](https://github.com/bigstack-oss/cubecos/pull/898)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Refine sdk gpu device list response ([#1038](https://github.com/bigstack-oss/cubecos/pull/1038)) by [@raven-pan](https://github.com/raven-pan)

#### Mongodb

- Derive the FCV target from the replica set instead of naming it ([d0b7f9c](https://github.com/bigstack-oss/cubecos/commit/d0b7f9ce0571ef48926fd584042390031fb0e8ee)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Settle the FCV from cluster_start instead of the health check ([fb88bf2](https://github.com/bigstack-oss/cubecos/commit/fb88bf223315f2882bf7230a724d86a611e571a3)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Neutron

- Move vpnaas make commands away from ovn ([925ee8a](https://github.com/bigstack-oss/cubecos/commit/925ee8a545381a65dbf9711e4577cff4ab277ac8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Nova

- Read cinder's backend tuning directly now that specs are lazy ([04669fa](https://github.com/bigstack-oss/cubecos/commit/04669fa133fc515320cac8472dcad82f16624a8c)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Openstack

- Promote antelope from NEXT_* to the current release ([4880566](https://github.com/bigstack-oss/cubecos/commit/4880566736a285612169f2ee255555fd57542856)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Privsep

- Point the pinned helper paths at /usr/bin ([57f5a0c](https://github.com/bigstack-oss/cubecos/commit/57f5a0c82644501d82da19dd95472eb1bff2b3a8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Rolling

- Unify rolling restart and rolling upgrade into one kind-aware roll ([5621ce5](https://github.com/bigstack-oss/cubecos/commit/5621ce55d49ab15a6e6c87a28b6d635e21f60cfb)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Is_node_rolling_upgrade asks the roll job, and becomes is_cluster_rolling ([66dd83c](https://github.com/bigstack-oss/cubecos/commit/66dd83c9143f44f9fd6df86a60554457435754ef)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Rootwrap

- Drop the temporary venv exec_dirs override ([40cbda8](https://github.com/bigstack-oss/cubecos/commit/40cbda8e92c2c020bc1e178819988c40b741e933)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Storage

- Consolidate multipath into a dedicated config_multipath module ([#1052](https://github.com/bigstack-oss/cubecos/pull/1052), [closes #1037](https://github.com/bigstack-oss/cubecos/issues/1037)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Upgrade

- Merge _os_pre_failure_host_evacuation into live_migration_gate repair mode ([b9f2c6f](https://github.com/bigstack-oss/cubecos/commit/b9f2c6f6444c08a354c948a417571bbf1bf90a70)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Watcher

- Drop the python 3.9 watcher-dashboard install ([a0823c7](https://github.com/bigstack-oss/cubecos/commit/a0823c7147bd6df51eeeb857bebcfc0611eb45bb)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### <!-- 4 -->:memo: Documentation

#### Github

- Require a QA Verification section in the issue templates ([033116d](https://github.com/bigstack-oss/cubecos/commit/033116dbd5f54b308d62a96994759a2d14191a38)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Horizon

- Record why the proxy must not set X-Forwarded-Proto ([ea1be56](https://github.com/bigstack-oss/cubecos/commit/ea1be562f06bf55c129f94cbaf9bc9bfe02f6fb2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Ironic

- Record why pykickstart is not installed ([8cc224a](https://github.com/bigstack-oss/cubecos/commit/8cc224a04d9425c45f40c2c3848ed1c356dd0018), [refs #610](https://github.com/bigstack-oss/cubecos/issues/610)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Issue-templates

- Require cubecos handbook knowledge update as an output artifact ([#982](https://github.com/bigstack-oss/cubecos/pull/982)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Miscellaneous

- Shorten nfs-ganesha/telegraf drop-in comments (detail lives in the kb notes) ([#1085](https://github.com/bigstack-oss/cubecos/pull/1085)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Mention the scenario sidecar in the handbook DoD checkbox ([#1291](https://github.com/bigstack-oss/cubecos/pull/1291)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Mysql

- Record where the build strips the devel packages ([f1f8dbd](https://github.com/bigstack-oss/cubecos/commit/f1f8dbd557b6b040baf54be4873a30a4b32aa2f1)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Python

- Building cpython requires /dev/null ([30c017b](https://github.com/bigstack-oss/cubecos/commit/30c017b55e128df784952b9ccf0dc6e3945f00f6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Swift

- Record that the pip-installed yoga swiftclient copy is gone ([a9db2f8](https://github.com/bigstack-oss/cubecos/commit/a9db2f8d2a94432f9f5b75c3152ea5ffd6c6ad96)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Correct the two stale claims about the yoga client ([af7379a](https://github.com/bigstack-oss/cubecos/commit/af7379a6a03122c15e0c6ffe00f9974672f0d109)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### Miscellaneous Tasks

#### Actions

- Refresh pinned action versions ([a561c6a](https://github.com/bigstack-oss/cubecos/commit/a561c6a4185c510d31950b375172c66b0c7681b5)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Appfw

- Drop unused legacy terraform tree ([cf92517](https://github.com/bigstack-oss/cubecos/commit/cf925176e813a4e103d534084b606b75e8490fe8)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Ceph

- Remove the used hdsentinel zip file during heavyfs build time ([8e9970c](https://github.com/bigstack-oss/cubecos/commit/8e9970c3e4955f1e30aa4088788f6df55512706b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cluster

- Comment out set_ready/start explicit neutron repair to verify redundancy ([#1094](https://github.com/bigstack-oss/cubecos/pull/1094)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)

#### Dependabot

- Watch GitHub Actions versions ([3bff1a8](https://github.com/bigstack-oss/cubecos/commit/3bff1a82823ebb88592056312d2807566aeeb079)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Glance

- Update the comment ([f642777](https://github.com/bigstack-oss/cubecos/commit/f642777d0cee8a4cf25a1da55b8daabb5b044f73)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Grub

- Bump grub2 build number from 118 to 129 ([#1039](https://github.com/bigstack-oss/cubecos/pull/1039)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Heavyfs

- Drop the orphaned yoga patch notes ([#1266](https://github.com/bigstack-oss/cubecos/pull/1266)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex

- Bump hex reference ([66f97ae](https://github.com/bigstack-oss/cubecos/commit/66f97ae65a4be7f35a3d90d74f0e2845a3285dd2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump hex link ([0c7e489](https://github.com/bigstack-oss/cubecos/commit/0c7e489f6e63b0e80777dd6d693568e78dce29d6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump hex ([81a3296](https://github.com/bigstack-oss/cubecos/commit/81a3296cf12b53f22c2ab6ca25473822cc8a10b8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump hex ([#1106](https://github.com/bigstack-oss/cubecos/pull/1106)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump submodule to 44b2acb — zero-touch installer + console fixes ([#1207](https://github.com/bigstack-oss/cubecos/pull/1207)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Bump submodule to 466f003 — QA Verification + CI fixes ([#1218](https://github.com/bigstack-oss/cubecos/pull/1218)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Issue template

- Add new template for epic, user story, feature, task, spike, and bug ([#738](https://github.com/bigstack-oss/cubecos/pull/738)) by [@jdjgya](https://github.com/jdjgya)

#### Kafka

- Bump kafka to 3.9.2 since 3.8.0 was purged ([3613e46](https://github.com/bigstack-oss/cubecos/commit/3613e46584e2797cfabd511a77b28ccf9f20da78)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Kernel

- Bump kernel to 6.12.74 since 6.12.69 was purged ([e30e1e1](https://github.com/bigstack-oss/cubecos/commit/e30e1e1047c1d7fe69798f264d2eec834917e525)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump kernel from 6.12.74 to 6.12.82 ([#852](https://github.com/bigstack-oss/cubecos/pull/852)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump kernel from 6.12.82 to 6.12.87 ([#875](https://github.com/bigstack-oss/cubecos/pull/875)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump kernel from 6.12.87 to 6.12.93 ([#956](https://github.com/bigstack-oss/cubecos/pull/956)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump kernel from 6.12.96 to 6.12.100 ([45f4a70](https://github.com/bigstack-oss/cubecos/commit/45f4a70653a7bf7827f3514e70d630c40b843915)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump kernel from 6.12.100 to 6.12.103 ([9027eb8](https://github.com/bigstack-oss/cubecos/commit/9027eb80a0172b65e094f371036fcbf84578039a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump kernel from 6.12.103 to 6.12.105 ([77ea049](https://github.com/bigstack-oss/cubecos/commit/77ea049c07751fcc4d4b9c7b0965f06220e29535)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump kernel from 6.12.105 to 6.12.107 ([10c0185](https://github.com/bigstack-oss/cubecos/commit/10c01857ccf8280b780f376735d8a35f8d2acd5c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Mariadb

- Bump mariadb from 10.6.26 to 10.6.27 ([86c56e9](https://github.com/bigstack-oss/cubecos/commit/86c56e9d00c0694381d5b7e7b61c869ab5f5ed78)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Avoid using mirror sites for mariadb packages since mirror sites were not reachable from the squid proxy ([19da57a](https://github.com/bigstack-oss/cubecos/commit/19da57a6922fa374d66efd094be50b429aba9123)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Masakari

- Clean up the build directory ([e54cbca](https://github.com/bigstack-oss/cubecos/commit/e54cbca2794295e6b365c0935dd802f83688e59a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Miscellaneous

- Issue templates type update ([#816](https://github.com/bigstack-oss/cubecos/pull/816)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Update hex submodule ([#864](https://github.com/bigstack-oss/cubecos/pull/864)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Update mariadb version for mysql.mk based on commit `07ca9a` ([ed5d7ff](https://github.com/bigstack-oss/cubecos/commit/ed5d7ff364f5c543a14ed1d097dd10da2d23066e)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Update hex submodule version ([#901](https://github.com/bigstack-oss/cubecos/pull/901)) by [@steven-chiu-bigstack](https://github.com/steven-chiu-bigstack)
- Bump hex to feat/config-provides-globals ([e70ba60](https://github.com/bigstack-oss/cubecos/commit/e70ba6095d1cd26cb6aa0e360043d090ab0dd9f6)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Add heat to conventional commit scopes ([0d499b3](https://github.com/bigstack-oss/cubecos/commit/0d499b39c3d0c1230494c783c90c356b7944260d)) by [@SekiXu](https://github.com/SekiXu)
- Add ironic to conventional commit scopes ([8ec3e57](https://github.com/bigstack-oss/cubecos/commit/8ec3e576115392945f5f18f16a2a715afe5a2a4d)) by [@SekiXu](https://github.com/SekiXu)
- Complete and tidy the conventional commit scope list ([d153cee](https://github.com/bigstack-oss/cubecos/commit/d153ceeec724d0617372b89eacff6a718e0cdb73)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Octavia

- Comment out openstack-octavia-ui until octavia moves to antelope ([1cdc1aa](https://github.com/bigstack-oss/cubecos/commit/1cdc1aa71b5e57b3fa9a4d41580e358def764f46)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Pr

- Allow merging toward non default branches ([#892](https://github.com/bigstack-oss/cubecos/pull/892)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Version

- Bump cubecos version to v3.1.10 ([#845](https://github.com/bigstack-oss/cubecos/pull/845)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### Security

#### Deps

- Bump step-security/harden-runner from 2.20.0 to 2.20.1 ([#1227](https://github.com/bigstack-oss/cubecos/pull/1227)) by [@dependabot[bot]](https://github.com/dependabot[bot])

### Build

#### Hex

- Bump hex for the tuning-spec registration fix ([1cc5a25](https://github.com/bigstack-oss/cubecos/commit/1cc5a25e9bbdae57588d6605b110f32170a01117)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Jail

- Add the eBPF toolchain and bump Go to 1.25.12 ([db49dee](https://github.com/bigstack-oss/cubecos/commit/db49dee784f8a94a567105316e17ced2ef7eb0c8)) by [@arasHi87](https://github.com/arasHi87)

#### Keycloak

- Assert login image tag matches the chart pin ([e35f03d](https://github.com/bigstack-oss/cubecos/commit/e35f03d8167686d611e0e411ae234839b848394b)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Pull the login source from the XA fix branch ([a500ac0](https://github.com/bigstack-oss/cubecos/commit/a500ac08c918b93ad23fa6ed30255123d7d522f2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Make

- Stop redundant rebuilds and clean up build output ([1fec992](https://github.com/bigstack-oss/cubecos/commit/1fec9921030660957e4408dfe3f53edd35ff2995), [refs #1005](https://github.com/bigstack-oss/cubecos/issues/1005)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Stop redundant hex_crashd rebuild and source-tree pollution ([#1006](https://github.com/bigstack-oss/cubecos/pull/1006)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Rpm components rebuild incrementally; bump hex submodule ([#1007](https://github.com/bigstack-oss/cubecos/pull/1007), [refs #1005](https://github.com/bigstack-oss/cubecos/issues/1005)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Register lachesis as a core component built from source ([bfe0e00](https://github.com/bigstack-oss/cubecos/commit/bfe0e007038d904dd5847d377d2806c552e674b7)) by [@arasHi87](https://github.com/arasHi87)
- Include defectdojo.mk alongside jenkins.mk ([#1199](https://github.com/bigstack-oss/cubecos/pull/1199)) by [@jimchen77](https://github.com/jimchen77)

#### Qemu

- Pin qemu-kvm to 17:10.1.0-22.el9 from the kojihub archive ([#1158](https://github.com/bigstack-oss/cubecos/pull/1158), [refs #1150](https://github.com/bigstack-oss/cubecos/issues/1150)) by [@traviswu-bigstack](https://github.com/traviswu-bigstack)
- Drop the epoch from the version lock ([702d260](https://github.com/bigstack-oss/cubecos/commit/702d260bbff01cdc7dfbb196bd4f43b3dcdeaed7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Release

- Pin the 3.1.10 component branches and rc artifacts ([#1274](https://github.com/bigstack-oss/cubecos/pull/1274)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### New

#### Build

- Bump jail java-sdk to version 21 ([#873](https://github.com/bigstack-oss/cubecos/pull/873)) by [@leechienpang](https://github.com/leechienpang)

#### Hex

- Pick up latest hex ([#1082](https://github.com/bigstack-oss/cubecos/pull/1082)) by [@leechienpang](https://github.com/leechienpang)

#### Sec

- Generate security fixpack with latest kernel ([#1066](https://github.com/bigstack-oss/cubecos/pull/1066)) by [@leechienpang](https://github.com/leechienpang)
- Rsync kernel/firmware/boot partitions after security fixpack install ([#1112](https://github.com/bigstack-oss/cubecos/pull/1112)) by [@leechienpang](https://github.com/leechienpang)

### Phone-home-agent

### Revert

#### Telegraf

- Drop the sflow openstack db account ([becedf6](https://github.com/bigstack-oss/cubecos/commit/becedf69271ed54d9ed497c9ee3dc52f9ac574c2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### Style

#### Mysql

- List the log directory owner where the other services list theirs ([25ffaff](https://github.com/bigstack-oss/cubecos/commit/25ffaff59af5aaee59aa9b7dd9c1cef2d86b5cd7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)


