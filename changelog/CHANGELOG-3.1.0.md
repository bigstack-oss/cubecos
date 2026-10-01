## [3.1.0](https://github.com/bigstack-oss/cubecos/releases/tag/v3.1.0) - 2026-02-26

### <!-- 0 -->:rocket: New Features

#### Alert

- Allow arbitrary file names to be set as alert response exec shell names ([#256](https://github.com/bigstack-oss/cubecos/pull/256)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move alert event input for exec from stdin to env ([82c5ab9](https://github.com/bigstack-oss/cubecos/commit/82c5ab9efe9ac5b1d4f7dc299f41034b32db9cc7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use batch job to run alert event exec ([f0d61fe](https://github.com/bigstack-oss/cubecos/commit/f0d61fe194770c2b256dc346f1c5a105c14d4957)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Limit the resource usage of alert resp job run ([#289](https://github.com/bigstack-oss/cubecos/pull/289)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add ceph usage alert ([#307](https://github.com/bigstack-oss/cubecos/pull/307)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Remove ceph usage error event ([#423](https://github.com/bigstack-oss/cubecos/pull/423)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### App

- Add framework_check_prerequisites, framework_create, and framework_delete in the app cli ([61056d6](https://github.com/bigstack-oss/cubecos/commit/61056d61db8f01c488e2e5a802b2aa2fd078c0e2)) by [@jdjgya](https://github.com/jdjgya)
- Add framework_check_port_access in the app cli ([24078ee](https://github.com/bigstack-oss/cubecos/commit/24078eea9c3f4e62322629f653b5ae3cccac4ce8)) by [@jdjgya](https://github.com/jdjgya)
- Add framework_list in the app cli ([bb07762](https://github.com/bigstack-oss/cubecos/commit/bb077626fac867c5850616bad145da5e57d3e737)) by [@jdjgya](https://github.com/jdjgya)

#### Appctl

- Register appctl to the core modules ([ba05e62](https://github.com/bigstack-oss/cubecos/commit/ba05e62658f6a140fa9ab433c10bbc5fb6f2fef6)) by [@jdjgya](https://github.com/jdjgya)

#### Build

- Security artifacts of sbom, scan and cosign #494 ([#520](https://github.com/bigstack-oss/cubecos/pull/520)) by [@leechienpang](https://github.com/leechienpang)

#### Ceph

- Allow multipath fc and iscsi devices exist during ceph bootstrapping ([#540](https://github.com/bigstack-oss/cubecos/pull/540)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move multipathd bootstrapping from nova to ceph ([f77d272](https://github.com/bigstack-oss/cubecos/commit/f77d2720f1180e35e82801ffe6a2cf0e52fe3ada)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Activate lvm osds during bootstrapping ([e05a2ee](https://github.com/bigstack-oss/cubecos/commit/e05a2ee99f275d690f3e506a2a79e45634ee70b7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Backup lvm vg infos after adding mpath devices in case of upgrade ([#545](https://github.com/bigstack-oss/cubecos/pull/545)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > storage > set_force_use_mpath_devices to switch on or off using multipath devices for ceph if external storages exist ([a098de2](https://github.com/bigstack-oss/cubecos/commit/a098de24506c54087d84cfe6e5a0663eb1a4ee02)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Force to use the form /dev/mapper/[wwid] as mapped device name in case naming changes between reboots ([#562](https://github.com/bigstack-oss/cubecos/pull/562)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cinder

- Set hex_config and hex_translate for adding external storages as cinder backends ([69cbba3](https://github.com/bigstack-oss/cubecos/commit/69cbba3b8549d18275cc0d1f5af42ef5cb153434)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add hex_sdk cinder_put_model ([1ea416d](https://github.com/bigstack-oss/cubecos/commit/1ea416d26ae8314e80fdd8690eae535e5a57d3fb)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Apply multipathd config changes ([2ce43f3](https://github.com/bigstack-oss/cubecos/commit/2ce43f3a2f5a2294f6cd062c6145d59ac16c5dce)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add hex_sdk cinder_get_model ([cc74114](https://github.com/bigstack-oss/cubecos/commit/cc74114a86148eb180b3268420690d65c494c2bd)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add hex_sdk cinder_get_models ([f4bfe86](https://github.com/bigstack-oss/cubecos/commit/f4bfe863f8aaf2a2aa183d3a2aae0931a20fe271)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add hex_sdk cinder_put_models ([61d7b4b](https://github.com/bigstack-oss/cubecos/commit/61d7b4b54a86585c16b8cc35680b7e41b107c7b4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add hex_sdk cinder_delete_model ([4d73a58](https://github.com/bigstack-oss/cubecos/commit/4d73a585e641416e04d1a408f0508ddad2da077b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add hex_sdk cinder_put_storage ([99b90ff](https://github.com/bigstack-oss/cubecos/commit/99b90ff3d9b6ee9a839d530fd10dcf745363e77e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Apply configs and set volume type properties in cinder_put_storage ([2be2365](https://github.com/bigstack-oss/cubecos/commit/2be23655386e329d528427735c01f2b1c7755cc4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Catch volume type properties apply error ([e551700](https://github.com/bigstack-oss/cubecos/commit/e551700b91cadc9d4728be40a1ee430672d72430)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add hex_sdk cinder_test_storage ([e9275aa](https://github.com/bigstack-oss/cubecos/commit/e9275aa58fda1437270dfc2910711899856b4c09)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add hex_sdk cinder_get_storages ([29d07e7](https://github.com/bigstack-oss/cubecos/commit/29d07e76e45943e57cf1300ac8aaf5dc03382cec)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add hex_sdk cinder_get_storage ([1fd0a8b](https://github.com/bigstack-oss/cubecos/commit/1fd0a8b135318376146d234a03ca0c3c6ac9d4c9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add hex_sdk cinder_delete_storage ([7963cae](https://github.com/bigstack-oss/cubecos/commit/7963caedca9e9b6eb279e05ae65c5c0cee0ef9ed)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add hex_sdk cinder_get_default_storage ([ed57507](https://github.com/bigstack-oss/cubecos/commit/ed575071ef95de0c10db3e2711898fad1664c11c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add hex_sdk cinder_set_default_storage ([568c453](https://github.com/bigstack-oss/cubecos/commit/568c453dd9cf3b9758fb638e126011a6aa46790c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add hex_sdk cinder_get_active_multipath_setting ([0a279e5](https://github.com/bigstack-oss/cubecos/commit/0a279e5b4ad7a823d2dfe558581a48cacd275b94)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Migrate config files for external storages ([382e86c](https://github.com/bigstack-oss/cubecos/commit/382e86c361d0a72c84e5a5ed30aaceb910c01122)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add dell emc powerstore as a builtin model ([88c2c2c](https://github.com/bigstack-oss/cubecos/commit/88c2c2c9913578f02d64950bc80ae111841b6e5e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add generic nfs as a builtin model ([078506b](https://github.com/bigstack-oss/cubecos/commit/078506b10cc24ec46ec1da4ff162aff921804416)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Provide existing volume manage capabilities on NFS volume backends ([3c42d66](https://github.com/bigstack-oss/cubecos/commit/3c42d66d588f8d5435b86fb43da9d7e7d52f0485)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > iaas > volume > migrate_large_volume_from_nfs ([#495](https://github.com/bigstack-oss/cubecos/pull/495)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Filter out already managed volumes on nfs backends ([4d69c7f](https://github.com/bigstack-oss/cubecos/commit/4d69c7fcf20b491cf55d566a0e2f032ca6aba80e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add volume name input to cli > iaas > volume > migrate_large_volume_from_nfs ([c7dcc66](https://github.com/bigstack-oss/cubecos/commit/c7dcc66f31f03462f163b9f1015e9d7528b3d1cf)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add dest volume type input to cli migrate_large_volume_from_nfs ([9b89b97](https://github.com/bigstack-oss/cubecos/commit/9b89b97d11b1ddba964b5911004e6b7573f74088)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add virt-v2v volume conversion input to cli migrate_large_volume_from_nfs ([7490447](https://github.com/bigstack-oss/cubecos/commit/74904474620c5021438bdf5fd2185f33ab419a8f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > iaas > volume > move to move a volume to a backend ([f5e90a1](https://github.com/bigstack-oss/cubecos/commit/f5e90a130b90f68e4ee32e17a2f8c164ce39d49b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Take over the control of the existing volume ([37c1c43](https://github.com/bigstack-oss/cubecos/commit/37c1c43299022ae16adf840bec71613b73d77b0b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Check if the file is in the raw format ([fd81337](https://github.com/bigstack-oss/cubecos/commit/fd8133769d6b888f31e61a7afb4aed862953f20c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Check if the project quota is enough to manage the volume ([55fe568](https://github.com/bigstack-oss/cubecos/commit/55fe568d3e50df8d82e419287780483d0baba3e7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Perform volume conversions using virt-v2v ([31a0074](https://github.com/bigstack-oss/cubecos/commit/31a0074349ff3d5807a0df58ad8c97f7068696b0)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Update the target file path for cinder manage to the converted volume file path ([49bc3f0](https://github.com/bigstack-oss/cubecos/commit/49bc3f06a65cafcc4ddf94ee5d74f0d35be901ad)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Set volume image properties to the volume ([a9bf9c9](https://github.com/bigstack-oss/cubecos/commit/a9bf9c9e5c79c606b98cba5d077976a2170901b4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Parse volume metadata ([#503](https://github.com/bigstack-oss/cubecos/pull/503)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > iaas > volume_backend > list_models ([9026daf](https://github.com/bigstack-oss/cubecos/commit/9026daf5cf9623a44d1f7b6585f2b2e407dff4a8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > iaas > volume_backend > list_drivers ([49c2dea](https://github.com/bigstack-oss/cubecos/commit/49c2deabad9950b60429d05c968fd961ae950ba5)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > iaas > volume_backend > list_model ([964d7c2](https://github.com/bigstack-oss/cubecos/commit/964d7c213470f66e7b991e44592f5bcb23df5f4d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > iaas > volume_backend > set_model ([840ff21](https://github.com/bigstack-oss/cubecos/commit/840ff21bd11c504789ec418a974e2e522a143556)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > iaas > volume_backend > delete_model ([e52ac24](https://github.com/bigstack-oss/cubecos/commit/e52ac24833cc0a4972889dcc7abab2386090fbaa)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > iaas > volume_backend > get_active_multipath_setting ([50c7fdf](https://github.com/bigstack-oss/cubecos/commit/50c7fdfa20164a0abb0b519f3cf84ea28b00f90e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > iaas > volume_backend > get_storages ([2e82c35](https://github.com/bigstack-oss/cubecos/commit/2e82c3594cea73126913a8ffbc88c215b35c04f7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > iaas > volume_backend > get_storage ([5f0821b](https://github.com/bigstack-oss/cubecos/commit/5f0821b64cd91b1863708743d116f73b20f3918f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > iaas > volume_backend > test_storage ([c9a3974](https://github.com/bigstack-oss/cubecos/commit/c9a397461808232b878a13e11b30b87f7372d96a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > iaas > volume_backend > get_default_storage ([edaadf0](https://github.com/bigstack-oss/cubecos/commit/edaadf028d83d1c730e476fb5acdd17eafed053d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > iaas > volume_backend > set_default_storage ([9d22f81](https://github.com/bigstack-oss/cubecos/commit/9d22f81712aa819579fddb2b36bc83eef0174274)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > iaas > volume_backend > delete_storage ([7fc8f1a](https://github.com/bigstack-oss/cubecos/commit/7fc8f1abc1f7c7cdd9734c4ad8761d4cade82f7c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > iaas > volume_backend > set_storage ([#512](https://github.com/bigstack-oss/cubecos/pull/512)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Sync models on control nodes to pure compute nodes ([041b554](https://github.com/bigstack-oss/cubecos/commit/041b55425e7baa0ddbd71ff6f954d629b5b0e2c4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make virt-v2v to use tmp directories on nfs instead for cli > iaas > volume_backend > manage_existing_from_nfs ([73c3926](https://github.com/bigstack-oss/cubecos/commit/73c392621eba3e361c18074098dcb79ee4acb21b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Print preconditions for cli > iaas > volume > manage_existing_from_nfs ([#522](https://github.com/bigstack-oss/cubecos/pull/522)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add fujitsu eternus dx series fc and iscsi as builtin models ([#559](https://github.com/bigstack-oss/cubecos/pull/559)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Elk

- Build opensearch-dashboard by ourself to solve security issue ([#558](https://github.com/bigstack-oss/cubecos/pull/558)) by [@arasHi87](https://github.com/arasHi87)
- Security patch for opensearch-dashboard ([#561](https://github.com/bigstack-oss/cubecos/pull/561)) by [@arasHi87](https://github.com/arasHi87)

#### Glance

- Config glance for setting cinder volume-backed store ([eb4c7e9](https://github.com/bigstack-oss/cubecos/commit/eb4c7e9c62c4a9b2ded22ca8d30361fa3b899c9a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Gpu

- Upgrade nvidia vgpu manage driver to v580.105.06 to support rtx pro 6000 blackwell server edition ([4cd337f](https://github.com/bigstack-oss/cubecos/commit/4cd337f233c8c6b321fdf358652f4724826152c8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Install fabric manager ([0a24d78](https://github.com/bigstack-oss/cubecos/commit/0a24d78adf9ac2df443e87a47d00d7aba047e558)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Back port vfio variant driver framework support for nvidia gpu sr-iov vgpu from openstack epoxy ([bcd9449](https://github.com/bigstack-oss/cubecos/commit/bcd94495f6256d76b44d97a6976306c883f324ea)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add cli > gpu > nvlink_enable / nvlink_disable to manage nvlink devices ([#680](https://github.com/bigstack-oss/cubecos/pull/680)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_cli

- Add openstack exec ([3705029](https://github.com/bigstack-oss/cubecos/commit/3705029679a169663fbbf98b5589391f5ce5018f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add command iaas volume_backend list to list existing and configured backends ([7502109](https://github.com/bigstack-oss/cubecos/commit/75021096f1a5548476768a890c3cea97e84390ec)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use crontab to schedule jobs for ceph osd removals ([93c59ec](https://github.com/bigstack-oss/cubecos/commit/93c59ecc53a63c9551cfec702ccb8322627d6d78)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Avoid scheduling duplicated ceph_osd_safe_remove jobs ([8d8b57c](https://github.com/bigstack-oss/cubecos/commit/8d8b57c80433b1dc4496aabf6979e033670b5022)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use crontab to schedule jobs for ceph osd disk removals ([fe080c6](https://github.com/bigstack-oss/cubecos/commit/fe080c69568275b7e8a2ad16a895d19862e88722)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Support mpath devices in cli > storage > list_avail ([b14a4f9](https://github.com/bigstack-oss/cubecos/commit/b14a4f9df9736fdc3f12b5986a71cae05c0fb880)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Disable mpath device support for Ceph if external storage is enable, unless being forced ([75068b8](https://github.com/bigstack-oss/cubecos/commit/75068b83b5b6e366c4ffac6019fc21c44330f921)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Exclude mpath devices in cli > storage > add_disk & add_avail ([3b950f9](https://github.com/bigstack-oss/cubecos/commit/3b950f91cde03c8b825d41c919739dbb26afe097)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make ceph_osd_host_remove be compatible with the new ceph_osd_remove logics and prevent cron job from rerunning jobs after updating the cron file ([e6c5278](https://github.com/bigstack-oss/cubecos/commit/e6c527882ddc9d48d8f343048c40d2677728c417)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Remove checks for duplicated job schedules since underlying functions already perform the check ([acaa7bb](https://github.com/bigstack-oss/cubecos/commit/acaa7bb92d5ca11357c71c7e5e57b6ec40e44b7b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make cli > storage > add_disk be able to add mpath devices ([e6da13d](https://github.com/bigstack-oss/cubecos/commit/e6da13d41f946f54e5438025a6aebd4795513a0f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_config

- Load default configs of cinder and glance for the support team ([6ea9308](https://github.com/bigstack-oss/cubecos/commit/6ea9308d9ce0301b8147ffb8c8259f1fd9895fad)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Hide mongodb start up messages ([#433](https://github.com/bigstack-oss/cubecos/pull/433)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Migrate needed config files for upgrades ([06310fa](https://github.com/bigstack-oss/cubecos/commit/06310facac67ec2263ec42d708c63ed97a984868)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_sdk

- Get event list for attribute-based alert trigger ([#238](https://github.com/bigstack-oss/cubecos/pull/238)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Accept json input for alert setting put setting receiver exec shell ([6277d6f](https://github.com/bigstack-oss/cubecos/commit/6277d6f8668b21bee4f63ee67004be5622214ff1)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Allow customized triggers ([b1a4304](https://github.com/bigstack-oss/cubecos/commit/b1a4304aae73ef3dfeeaf85de66a9d51df2699e6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add alert_delete_trigger to delete a trigger ([4671232](https://github.com/bigstack-oss/cubecos/commit/4671232f044454bd721ea7d7850f0b031bd41470)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Provide exec call isolation ([17b062d](https://github.com/bigstack-oss/cubecos/commit/17b062ddf2adfe765ea072a7c3478bf48db1ad6f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add json helper functions ([96a5bf7](https://github.com/bigstack-oss/cubecos/commit/96a5bf7f805fdd5a49dcab0ed6c8bb94f27ce570)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add file system helper functions ([923eb0b](https://github.com/bigstack-oss/cubecos/commit/923eb0b0c2d2858ff18edf917d2f8cc495190ef4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Stats_partition #448 ([#471](https://github.com/bigstack-oss/cubecos/pull/471)) by [@leechienpang](https://github.com/leechienpang)
- Add logging functions ([d3cc37f](https://github.com/bigstack-oss/cubecos/commit/d3cc37fe63be14abab6c96aa524a98a5a5132a1d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Jail

- Mute emulate warning and fix nested build permission issue ([534dcdb](https://github.com/bigstack-oss/cubecos/commit/534dcdb175ba91433369a4dff20d113f936bb7a7)) by [@arasHi87](https://github.com/arasHi87)
- Enable podman daemon for dapper build process ([c244743](https://github.com/bigstack-oss/cubecos/commit/c24474347d5f7dedeed1224454e97c6f87fb4c82)) by [@arasHi87](https://github.com/arasHi87)

#### K3s

- Build k3s by ourself to solve security issue ([415e05c](https://github.com/bigstack-oss/cubecos/commit/415e05ca3f6d17733ca6cfdab9f6f968356efd4d)) by [@arasHi87](https://github.com/arasHi87)

#### Kapacitor

- Migrate registered trigger exec shells and bins ([c9a1495](https://github.com/bigstack-oss/cubecos/commit/c9a1495c50f2583245589ec9e7f5f8a42db4fa15)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Pour alerts in topic instance-events to topic events ([#242](https://github.com/bigstack-oss/cubecos/pull/242)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Kernel

- Move to kernel-ml (temporarily skip compiling nvidia) ([13ac3f7](https://github.com/bigstack-oss/cubecos/commit/13ac3f75fde842fcdeae3c271ebe09f3d18d95a9)) by [@leechienpang](https://github.com/leechienpang)
- Switch to kernel-6.12 to satisfy nvidia driver compilation ([#566](https://github.com/bigstack-oss/cubecos/pull/566)) by [@leechienpang](https://github.com/leechienpang)

#### Keycloak

- Set keycloak admin password ([5e93f7e](https://github.com/bigstack-oss/cubecos/commit/5e93f7e71c342d4e3ba25b9e41227998a8de29f0)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Save keycloak admin password as a k8s secret ([79f45b7](https://github.com/bigstack-oss/cubecos/commit/79f45b725bd3c513ead868a9b5968f9fdab95062)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add command get_keycloak_admin_password ([dc2e58f](https://github.com/bigstack-oss/cubecos/commit/dc2e58ff73b0c48dc17a037c6db71eb1e9affa09)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Update the admin password used in the terraform provider ([4a3f5ae](https://github.com/bigstack-oss/cubecos/commit/4a3f5aea1a52a830294cd2fed63e63b9c43b0cad)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add a setting health check for keycloak admin password not synced ([#452](https://github.com/bigstack-oss/cubecos/pull/452)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Hide db connection infos as k3s secrets ([c67bbb4](https://github.com/bigstack-oss/cubecos/commit/c67bbb49ee63815e2177445bc7e42fa46903e1f7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Log

- Send hex logs to separated files ([#437](https://github.com/bigstack-oss/cubecos/pull/437)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Make

- Generate sha256 checksum ([924968d](https://github.com/bigstack-oss/cubecos/commit/924968dbaa6204a492b9aee332013fb83b703cdc)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Push checksum computations of terminal artifacts to background and nohup them ([#265](https://github.com/bigstack-oss/cubecos/pull/265)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Include the gpu driver in builds ([#567](https://github.com/bigstack-oss/cubecos/pull/567)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Manila

- Config manila for setting cinder volume types of external storages ([23f75ae](https://github.com/bigstack-oss/cubecos/commit/23f75ae77b8880da5b19ed4ee78c0acf84a2f975)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Miscellaneous

- Rolling upgrade definition: no VMs go into error states #155 ([#186](https://github.com/bigstack-oss/cubecos/pull/186)) by [@leechienpang](https://github.com/leechienpang)
- Feat(k3s) remove unused k3s binary due to security issue ([7d13782](https://github.com/bigstack-oss/cubecos/commit/7d1378235b05fc56a315fb63d714db34f7bbb381)) by [@arasHi87](https://github.com/arasHi87)

#### Mongodb

- Hide commit outputs ([#587](https://github.com/bigstack-oss/cubecos/pull/587)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Neutron

- Enable qos plugin ([#524](https://github.com/bigstack-oss/cubecos/pull/524)) by [@arasHi87](https://github.com/arasHi87)
- Enable the subnet_dns_publish_fixed_ip for dns feature ([d30b180](https://github.com/bigstack-oss/cubecos/commit/d30b180b7bd3571900487fd4c08f9cbc4fe988bf)) by [@arasHi87](https://github.com/arasHi87)
- Publish dns record automatically when  setup dns-domain ([#535](https://github.com/bigstack-oss/cubecos/pull/535)) by [@arasHi87](https://github.com/arasHi87)

#### Nova

- Set vTPM config to nova ([#434](https://github.com/bigstack-oss/cubecos/pull/434)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Oci image

- Add a troubleshooting tool  by api add busybox-extras ([#350](https://github.com/bigstack-oss/cubecos/pull/350)) by [@jdjgya](https://github.com/jdjgya)

#### Prometheus

- Build  promtool by ourself to solve security issue ([6784fdb](https://github.com/bigstack-oss/cubecos/commit/6784fdb97b6f32cd4a84bfec2b8fc4fe72212e92)) by [@arasHi87](https://github.com/arasHi87)
- Build prometheus and promtool by ourself to solve security issue ([#557](https://github.com/bigstack-oss/cubecos/pull/557)) by [@arasHi87](https://github.com/arasHi87)

#### Rancher

- Upgrade rancher server and cli to v2.11.2 to support newer k8s versions ([#173](https://github.com/bigstack-oss/cubecos/pull/173)) by [@jdjgya](https://github.com/jdjgya)
- Deprecate cube node driver and remove related initial process ([#525](https://github.com/bigstack-oss/cubecos/pull/525)) by [@arasHi87](https://github.com/arasHi87)
- Build rancher by ourself to solve security issue ([dc6af23](https://github.com/bigstack-oss/cubecos/commit/dc6af23f43dde13648d827a6f04618d9db50c818)) by [@arasHi87](https://github.com/arasHi87)

#### Sbom

- Omit more directories during sbom generations ([8ce549c](https://github.com/bigstack-oss/cubecos/commit/8ce549c8bf29e376537b3a091ae066c7d3410ee4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Omit /etc in sbom generations ([d76547b](https://github.com/bigstack-oss/cubecos/commit/d76547b5d0a0e442690dcaf890036bb16b559bbb)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Security

- Drop icmp requests and replies ([#458](https://github.com/bigstack-oss/cubecos/pull/458)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Senlin

- Add cli > management > cleanup > cleanup_senlin to remove openstack senlin remnants ([#531](https://github.com/bigstack-oss/cubecos/pull/531)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Skyline

- Update to latest master to include the security fix ([#546](https://github.com/bigstack-oss/cubecos/pull/546)) by [@arasHi87](https://github.com/arasHi87)

#### Telegraf

- Update mod to solve the security issue ([6c7962d](https://github.com/bigstack-oss/cubecos/commit/6c7962d66a35ecd65f94f4a8d45d600c706977c0)) by [@arasHi87](https://github.com/arasHi87)

#### Terraform

- Build terraform by ourself to solve security issue ([03f52fe](https://github.com/bigstack-oss/cubecos/commit/03f52fe8a920bad8b6993cd751d5fdb49464a3fa)) by [@arasHi87](https://github.com/arasHi87)
- Build keycloak provider by ourself to solve security issue ([1d9dbb4](https://github.com/bigstack-oss/cubecos/commit/1d9dbb4256aa93cd651644a7764ecec8cdaaf4cf)) by [@arasHi87](https://github.com/arasHi87)
- Update go-getter and x-crypto to solve serurity issue ([f8e14f0](https://github.com/bigstack-oss/cubecos/commit/f8e14f0f782eaf65bce0066340d7001203d5db32)) by [@arasHi87](https://github.com/arasHi87)

#### Yq

- Build yq by ourself to solve security issue ([9cedc46](https://github.com/bigstack-oss/cubecos/commit/9cedc46aec8b271de0cd4b865ddc25082f811bd4)) by [@arasHi87](https://github.com/arasHi87)

### <!-- 1 -->:bug: Bug fixes

#### Alert

- Properly escape event inputs for alert response exec job ([#306](https://github.com/bigstack-oss/cubecos/pull/306)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### App frameworks

- Change the 'rancher-cluster-image.raw' to 'rancher-cluster-image-rke2-v1.32.4.raw' ([#527](https://github.com/bigstack-oss/cubecos/pull/527)) by [@jdjgya](https://github.com/jdjgya)
- Fix the image typo in the extpack's rancher md5 check ([#528](https://github.com/bigstack-oss/cubecos/pull/528)) by [@jdjgya](https://github.com/jdjgya)

#### Appctl

- Fix the incorrect file preparation path ([297d3f6](https://github.com/bigstack-oss/cubecos/commit/297d3f663ab536c50dc88aa4cfcf667a763211fa)) by [@jdjgya](https://github.com/jdjgya)
- Fix the git path conflict during building artifacts ([365f4d5](https://github.com/bigstack-oss/cubecos/commit/365f4d5622cdcf3b532bd4a3ee2a0b2ecd48a920)) by [@jdjgya](https://github.com/jdjgya)
- Fix the incorrect var usage in the appctl/copy-images.sh ([3547870](https://github.com/bigstack-oss/cubecos/commit/35478706010b55925d93f77014a298f408487347)) by [@jdjgya](https://github.com/jdjgya)
- Fix the incorrect var usage in the appctl/copy-images.sh ([fd555e4](https://github.com/bigstack-oss/cubecos/commit/fd555e41d272a55df3ad328b48b383eb461342ee)) by [@jdjgya](https://github.com/jdjgya)
- Fix the duplicated ./source dir during build time ([811b2d5](https://github.com/bigstack-oss/cubecos/commit/811b2d5aec70d55c1939f1dd526535da2e3fbf1c)) by [@jdjgya](https://github.com/jdjgya)
- Do APPCTL_GIT_DIR removal before creation ([d1dae49](https://github.com/bigstack-oss/cubecos/commit/d1dae498abc4ac65f48d3c14aa3e37eef4d5bef7)) by [@jdjgya](https://github.com/jdjgya)
- Use cp -rf to copy the plugin dir ([774cfa0](https://github.com/bigstack-oss/cubecos/commit/774cfa0bafd36762e9c9c10ec220e617fe94aff8)) by [@jdjgya](https://github.com/jdjgya)
- Fix the build process in the appctl's Makefile ([#473](https://github.com/bigstack-oss/cubecos/pull/473)) by [@jdjgya](https://github.com/jdjgya)
- Fix the offline image preparation issue ([#543](https://github.com/bigstack-oss/cubecos/pull/543)) by [@jdjgya](https://github.com/jdjgya)

#### Appfw

- Update docker-registry helm chart repo url ([9af13a2](https://github.com/bigstack-oss/cubecos/commit/9af13a266f20f70543617edd1e064dc8b54e9c64)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Build

- Ignore rpm --import Warning: Unsupported version of key: V6 ([#534](https://github.com/bigstack-oss/cubecos/pull/534)) by [@leechienpang](https://github.com/leechienpang)
- Unlock crun-1.20-2.el9 which is unavailable from upstreams ([#682](https://github.com/bigstack-oss/cubecos/pull/682)) by [@leechienpang](https://github.com/leechienpang)
- Increase timeout while reducing loop retries ([eb2a2e9](https://github.com/bigstack-oss/cubecos/commit/eb2a2e99ccacd369b47dd089191c905ef1ff7f0c)) by [@leechienpang](https://github.com/leechienpang)
- Bump up to kernel-6.12.69 ([#706](https://github.com/bigstack-oss/cubecos/pull/706)) by [@leechienpang](https://github.com/leechienpang)
- Java.lang.OutOfMemoryError: Java heap space hitting 1G cap ([#717](https://github.com/bigstack-oss/cubecos/pull/717)) by [@leechienpang](https://github.com/leechienpang)

#### Ceph

- Check if external storage is set on vip control node ([#549](https://github.com/bigstack-oss/cubecos/pull/549)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cinder

- Set up the service on fts, set the default volume type to the built-in if empty, and check if files exist before touching them ([#365](https://github.com/bigstack-oss/cubecos/pull/365)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Skip empty volume backend name ([045959b](https://github.com/bigstack-oss/cubecos/commit/045959bc88bbb788f1048c15faca76226b7307e8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Stop disabling qemu-guest-agent and iscsi-onboot services ([#375](https://github.com/bigstack-oss/cubecos/pull/375)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Fix type ([#386](https://github.com/bigstack-oss/cubecos/pull/386)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add the missing successful output of hex_sdk cinder_set_default_storage ([#401](https://github.com/bigstack-oss/cubecos/pull/401)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Set the correct file path ([060aa1b](https://github.com/bigstack-oss/cubecos/commit/060aa1b75b5170d72d43268d5b9ba957fae3bc3c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Restore the built-in model's multipath settings if it exists ([#418](https://github.com/bigstack-oss/cubecos/pull/418)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Escape the colon in volume type for cinder_get_volume_type_properties ([#451](https://github.com/bigstack-oss/cubecos/pull/451)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Failed to filter out duplicated storage names ([#453](https://github.com/bigstack-oss/cubecos/pull/453)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Fix typos in sdk interfaces ([d1042cd](https://github.com/bigstack-oss/cubecos/commit/d1042cd373c7285130e08a95eeb5d7bc559610e4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Support multiple backends using the same model ([fd82fc8](https://github.com/bigstack-oss/cubecos/commit/fd82fc811a58e0eadd68a64cc56f7246ae018c68)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Parse ini outputs without any sections ([fbe66f7](https://github.com/bigstack-oss/cubecos/commit/fbe66f71c4028bf2a7b380da4b19638dd54f9f01)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Allow one line command input for cli migrate_large_volume_from_nfs ([79c0f83](https://github.com/bigstack-oss/cubecos/commit/79c0f839da8381245147edeb5905fa3477d5f6ba)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Escape user input values in bash executions ([166ce85](https://github.com/bigstack-oss/cubecos/commit/166ce85674051ba86f9b7be71ce56891d761c0b3)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Always check the project quotas for managing a volume ([542a4c5](https://github.com/bigstack-oss/cubecos/commit/542a4c5b9db2b2eb1bcc9194c2a85aeb31f59177)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use absolute paths to call the binaries instead ([67d1944](https://github.com/bigstack-oss/cubecos/commit/67d1944a031a507e6ff0bd9b92f3785909ea30fb)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drain the pipe in ExecSync for the missing contents ([#506](https://github.com/bigstack-oss/cubecos/pull/506)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Check if storage backend config files are modified or not ([e91f7c1](https://github.com/bigstack-oss/cubecos/commit/e91f7c13c560ba7b6ce9f5a4af2609627fc54fb9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Get volume backend pools when backends have similar names ([3b7ab87](https://github.com/bigstack-oss/cubecos/commit/3b7ab87d561e23ff1127020793666eecf88600af)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Check volumes from all projects before deleting the external storage ([#687](https://github.com/bigstack-oss/cubecos/pull/687)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cubectl

- Fix cubectl's lib conflict issue ([#521](https://github.com/bigstack-oss/cubecos/pull/521)) by [@jdjgya](https://github.com/jdjgya)
- Upgrade the golang lib to 1.24.2 for resoving the net/http golib issue ([6a0f87f](https://github.com/bigstack-oss/cubecos/commit/6a0f87f4ca1553daedd98f95a247e784c70e5d84)) by [@jdjgya](https://github.com/jdjgya)

#### Etcd

- Upgrade the etcd to 3.5.23 for resoving the net/http golib issue ([6d4b8fd](https://github.com/bigstack-oss/cubecos/commit/6d4b8fdb7c158701958bdaf191e20ff3e9a981e7)) by [@jdjgya](https://github.com/jdjgya)

#### Fixpack_history

- Clear history after FW upgrade #695 ([7f12024](https://github.com/bigstack-oss/cubecos/commit/7f12024214d87e6c8b50f6d5ff350fa2dd134458)) by [@leechienpang](https://github.com/leechienpang)

#### Glance

- Set permissions before opening the file writing stream ([#372](https://github.com/bigstack-oss/cubecos/pull/372)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Skip empty store backend name ([f697b52](https://github.com/bigstack-oss/cubecos/commit/f697b520221e7e12950dc2a68e2bfbf88caf2828)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Reactivate logging for glance ([5bc97b2](https://github.com/bigstack-oss/cubecos/commit/5bc97b2a3f6bce76cbeb138897498ca197a9b0f9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Allow openstack user cinder with role service to set image locations ([#701](https://github.com/bigstack-oss/cubecos/pull/701)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Lift project service quota for volume-backed images ([#705](https://github.com/bigstack-oss/cubecos/pull/705)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Haproxy

- Separate cookie name token from different backends ([96162be](https://github.com/bigstack-oss/cubecos/commit/96162be38c789e905cda6373108b793b3c8ca92f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Remove the 'replace-header' of cookie for cube-cos-api and ceph-dashboard ([#294](https://github.com/bigstack-oss/cubecos/pull/294)) by [@jdjgya](https://github.com/jdjgya)

#### Hex_cli

- Cluster remove_mode does not remove its osds #101 ([7317adc](https://github.com/bigstack-oss/cubecos/commit/7317adc04f1da7a338f7709d94d2c3ec93055c0e)) by [@leechienpang](https://github.com/leechienpang)
- Remove the Quiet() for the ceph restful create-key and ceph restful list-keys ([#519](https://github.com/bigstack-oss/cubecos/pull/519)) by [@jdjgya](https://github.com/jdjgya)
- Check array index boundaries ([f0c155b](https://github.com/bigstack-oss/cubecos/commit/f0c155bcd58ade0093af306d7d207d1fc11defe9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use flock to avoid race conditions on read then write crontab ([6d34c52](https://github.com/bigstack-oss/cubecos/commit/6d34c524d70e0ebbd55474022b165769153c4663)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use safer checks to test if a disk is ready to be removed ([b5026d3](https://github.com/bigstack-oss/cubecos/commit/b5026d3ab4dffddc68eb90bcae6fc60498b97cbf)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Remove not needed /sys/class/scsi_host/*/scan outputs ([c07f850](https://github.com/bigstack-oss/cubecos/commit/c07f85013557e2d937da5000ee54ff189c61f2d4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_config

- Use the correct boot status cli command ([#436](https://github.com/bigstack-oss/cubecos/pull/436)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Resolve logrotate config conflict with rsyslog default configs ([db3459c](https://github.com/bigstack-oss/cubecos/commit/db3459c6be78ad383c4061226925d60e3f800d23)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Cirros image fails to import when glance is not fully ready ([c55e993](https://github.com/bigstack-oss/cubecos/commit/c55e99363728eedb41fc2468353eff5418d14bda)) by [@leechienpang](https://github.com/leechienpang)
- Limit file permissions of written files ([#457](https://github.com/bigstack-oss/cubecos/pull/457)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_fixpack_install

- Cmd not found #570 ([#571](https://github.com/bigstack-oss/cubecos/pull/571)) by [@leechienpang](https://github.com/leechienpang)

#### Hex_install

- Refactor FormatDataHDD and exclude non-writable and zero size devices ([2900ffe](https://github.com/bigstack-oss/cubecos/commit/2900ffe19884cd2cff0c0f7c04fd7c331662204f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_sdk

- Check file existence and adjust the wrong input parameter in alert_put_setting_receiver_exec_shell for alert_add_update_setting_receiver_exec_shell ([#251](https://github.com/bigstack-oss/cubecos/pull/251)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Fix typo ([#258](https://github.com/bigstack-oss/cubecos/pull/258)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Stop duplicating tuning outputs ([#432](https://github.com/bigstack-oss/cubecos/pull/432)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Block tcp port 8080 and accept local traffics ([#435](https://github.com/bigstack-oss/cubecos/pull/435)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Avoid having multiple Cirros img in Glance ([#438](https://github.com/bigstack-oss/cubecos/pull/438)) by [@leechienpang](https://github.com/leechienpang)
- CLI image import with progress bar would hang #128 ([#440](https://github.com/bigstack-oss/cubecos/pull/440)) by [@leechienpang](https://github.com/leechienpang)
- Image import to check volumes quota limit and space #445 ([#446](https://github.com/bigstack-oss/cubecos/pull/446)) by [@leechienpang](https://github.com/leechienpang)
- Image import quota check not cover correct proj_name #445 ([#462](https://github.com/bigstack-oss/cubecos/pull/462)) by [@leechienpang](https://github.com/leechienpang)
- Image import visibility shared should be public #463 ([#464](https://github.com/bigstack-oss/cubecos/pull/464)) by [@leechienpang](https://github.com/leechienpang)
- Image import to ext-storage backend via Glance #468 ([6032a2a](https://github.com/bigstack-oss/cubecos/commit/6032a2ad08ac4a52c8debfb67ae18f1d117df331)) by [@leechienpang](https://github.com/leechienpang)
- Image import to ext-storage backend not converted via virt-v2v #468 ([#474](https://github.com/bigstack-oss/cubecos/pull/474)) by [@leechienpang](https://github.com/leechienpang)
- Image_import to handle quota -1 value #563 ([#588](https://github.com/bigstack-oss/cubecos/pull/588)) by [@leechienpang](https://github.com/leechienpang)
- Ceph_osd_host_remove never finishes #679 ([#681](https://github.com/bigstack-oss/cubecos/pull/681)) by [@leechienpang](https://github.com/leechienpang)
- Trigger migrate_fixpack #695 ([#700](https://github.com/bigstack-oss/cubecos/pull/700)) by [@leechienpang](https://github.com/leechienpang)
- Create s3 log bucket during cluster_start #703 ([#712](https://github.com/bigstack-oss/cubecos/pull/712)) by [@leechienpang](https://github.com/leechienpang)

#### Httpd

- Only allow control management ips to access apache mod_status /server-status page ([b0fd95a](https://github.com/bigstack-oss/cubecos/commit/b0fd95aee30f67c34f16e55dbbad9b37a299dc9b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Install

- Exclude fc and iscsi hosts from the install process ([fba61cf](https://github.com/bigstack-oss/cubecos/commit/fba61cf6bba7dca4634f7242c3423b3752a4103d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Jail

- Upgrade the golang lib to 1.24.2 for resoving the net/http golib issue ([d1d36fd](https://github.com/bigstack-oss/cubecos/commit/d1d36fd1f3c9f66fb329eb3f0389f1ce29010287)) by [@jdjgya](https://github.com/jdjgya)
- Correct the typo in parameter pass ([2458402](https://github.com/bigstack-oss/cubecos/commit/2458402039881e21cdf9c9f3f378934c2248b66f)) by [@arasHi87](https://github.com/arasHi87)

#### K3s

- Adjust the process flow for generating the ceph rgw credential ([#478](https://github.com/bigstack-oss/cubecos/pull/478)) by [@jdjgya](https://github.com/jdjgya)
- Upgrade the k3s from 1.26.6 to 1.32.11 for resoving the net/http golib issue ([90d60e5](https://github.com/bigstack-oss/cubecos/commit/90d60e52cf2074bb6e9be974e8f436f776e19382)) by [@jdjgya](https://github.com/jdjgya)
- Correct the final build k3s binary to fix kubectl not found error ([2b2c7c6](https://github.com/bigstack-oss/cubecos/commit/2b2c7c6ef315c77926e1f5557f8fd679ba6f6ba0)) by [@arasHi87](https://github.com/arasHi87)
- Handle the dependency issue of klog after upgrade to 1.24 ([302ad98](https://github.com/bigstack-oss/cubecos/commit/302ad98499ad9001928e6f6bd4e2fa1c45297ab2)) by [@arasHi87](https://github.com/arasHi87)
- Wait for metrics-server pod and api service after k3s boostrapping ([67a3681](https://github.com/bigstack-oss/cubecos/commit/67a3681be0310d64e4ecd994f23d4dca3b70be43)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Correct bash syntax error while waiting for metrics-server api service ([#711](https://github.com/bigstack-oss/cubecos/pull/711)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Kapacitor

- Set the correct event messages for ceph usage alerts ([22294a9](https://github.com/bigstack-oss/cubecos/commit/22294a9b9d62f71c1434ebe246f7e3895d20db55)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Adjust the event list per ceph usage alert threshold change ([b91f0a0](https://github.com/bigstack-oss/cubecos/commit/b91f0a02fa8198bc4c4500679fff18ebbcb361d7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Filter out illegal characters in event handler names ([#459](https://github.com/bigstack-oss/cubecos/pull/459)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Kernel

- Bump kernel version from 6.1.136 to 6.1.149 ([#356](https://github.com/bigstack-oss/cubecos/pull/356)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Keycloak

- Avoid updating keycloak during rolling upgrade ([#456](https://github.com/bigstack-oss/cubecos/pull/456)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use the correct status flag ([59f68b4](https://github.com/bigstack-oss/cubecos/commit/59f68b4b54ebb1ffe2c7563cd4a7d9a3f952fb9c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Deploy at least one pod of keycloak ([fdb9fd0](https://github.com/bigstack-oss/cubecos/commit/fdb9fd080c6ecd6497bf00bf75c40da0ae09bd97)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Repair 0 replica in the helm release ([#465](https://github.com/bigstack-oss/cubecos/pull/465)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Fix the typo in the keycloak makefile ([#585](https://github.com/bigstack-oss/cubecos/pull/585)) by [@jdjgya](https://github.com/jdjgya)
- Ensure k3s is running before deploying keycloak ([a88de9d](https://github.com/bigstack-oss/cubecos/commit/a88de9d4fe18501c092a61b8a58f45b56348063e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Hide error messages from kubectl and helm cli ([#686](https://github.com/bigstack-oss/cubecos/pull/686)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Set required file permissions on keycloak idp xml file for keystone mellon to work ([#715](https://github.com/bigstack-oss/cubecos/pull/715)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Linux

- Fix linux user group database misconfigurations ([#330](https://github.com/bigstack-oss/cubecos/pull/330)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Make

- Add the missing chmod for sha256 of pkg parts ([a164315](https://github.com/bigstack-oss/cubecos/commit/a1643154ae6c80a7a6c84233b43f26c4e3be02ef)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Preserve PROJ_PPUISO proj.pkgiso builds ([8f11d86](https://github.com/bigstack-oss/cubecos/commit/8f11d860bfd815a15ad304539a9c37e18dc8045a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Remove the sha256 checksum files from the previous build ([4c887fd](https://github.com/bigstack-oss/cubecos/commit/4c887fdb089564ea756f608df86cdf451e6f550b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use find instead since extended globbing is not supported in Bourne shell ([#260](https://github.com/bigstack-oss/cubecos/pull/260)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Avoid using subshell after nohup ([eb045c8](https://github.com/bigstack-oss/cubecos/commit/eb045c813cd5d4327d2f68781a624abadf206281)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Disambiguate semicolon and ampersand ([#266](https://github.com/bigstack-oss/cubecos/pull/266)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump qemu-kvm version to 17:9.1.0-26.el9 ([a7b9c7f](https://github.com/bigstack-oss/cubecos/commit/a7b9c7fb4419d8abe55c0fbeb9bf6799f4547a0d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump qemu-kvm version to 17:9.1.0-27.el9 ([#472](https://github.com/bigstack-oss/cubecos/pull/472)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Downgrade qemu-kvm version to 17:9.1.0-24.el9 ([151c173](https://github.com/bigstack-oss/cubecos/commit/151c173f91551ce18c4cce96cba832ab0293e635)) by [@leechienpang](https://github.com/leechienpang)
- Place yq to the correct location ([6cf33ce](https://github.com/bigstack-oss/cubecos/commit/6cf33ce5d49a2ddd713a77af467fce1e7cc2404c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Miscellaneous

- Filter out intermediated grep results that pollutes stdout #155 ([#201](https://github.com/bigstack-oss/cubecos/pull/201)) by [@leechienpang](https://github.com/leechienpang)
- SDK mgmt_ip doesn't handle bonding + vlan #205 ([#207](https://github.com/bigstack-oss/cubecos/pull/207)) by [@leechienpang](https://github.com/leechienpang)
- SDK GetParentIfname bad inputs, causing malfunction of password_init #155 ([#215](https://github.com/bigstack-oss/cubecos/pull/215)) by [@leechienpang](https://github.com/leechienpang)
- SDK ceph_osd_list outputs messed up by concurrent instances #225 ([#232](https://github.com/bigstack-oss/cubecos/pull/232)) by [@leechienpang](https://github.com/leechienpang)
- Control-converged pacemaker_remote_add leads to vip loss #155 ([#233](https://github.com/bigstack-oss/cubecos/pull/233)) by [@leechienpang](https://github.com/leechienpang)
- Bootstrap can fail because of temporary master node VIP #155 ([#254](https://github.com/bigstack-oss/cubecos/pull/254)) by [@leechienpang](https://github.com/leechienpang)
- Compute node fails to init octavia-hm0 #155 ([#257](https://github.com/bigstack-oss/cubecos/pull/257)) by [@leechienpang](https://github.com/leechienpang)
- Rolling-upgrade master control unresponsive ceph mon #155 ([b306ee2](https://github.com/bigstack-oss/cubecos/commit/b306ee2c9d776bf4f2933b0521e692295596c743)) by [@leechienpang](https://github.com/leechienpang)
- Rolling-upgrade ensure only master control has vip #155 ([#267](https://github.com/bigstack-oss/cubecos/pull/267)) by [@leechienpang](https://github.com/leechienpang)
- Proj_functions to use standardized timeout variables ([#280](https://github.com/bigstack-oss/cubecos/pull/280)) by [@leechienpang](https://github.com/leechienpang)
- Rolling-upgrade VM evacuation continues irrespective of failures ([#290](https://github.com/bigstack-oss/cubecos/pull/290)) by [@leechienpang](https://github.com/leechienpang)
- Bootstrap logic mistakes #155 ([#305](https://github.com/bigstack-oss/cubecos/pull/305)) by [@leechienpang](https://github.com/leechienpang)
- Non-master control should not lose vip ([#311](https://github.com/bigstack-oss/cubecos/pull/311)) by [@leechienpang](https://github.com/leechienpang)
- Rolling upgrade cluster level SDK pacemaker status #155 ([#329](https://github.com/bigstack-oss/cubecos/pull/329)) by [@leechienpang](https://github.com/leechienpang)
- FTS roll is undef so health_vip_check doesn't work #155 ([#338](https://github.com/bigstack-oss/cubecos/pull/338)) by [@leechienpang](https://github.com/leechienpang)
- Stopping pacemaker with systemd can take 20 min #155 ([#361](https://github.com/bigstack-oss/cubecos/pull/361)) by [@leechienpang](https://github.com/leechienpang)
- Infinite loop of hex_sdk #155 ([#374](https://github.com/bigstack-oss/cubecos/pull/374)) by [@leechienpang](https://github.com/leechienpang)
- SDK ceh_mds check output and detail not consistent #380 ([#381](https://github.com/bigstack-oss/cubecos/pull/381)) by [@leechienpang](https://github.com/leechienpang)
- SDK is_checking bug #155 ([#385](https://github.com/bigstack-oss/cubecos/pull/385)) by [@leechienpang](https://github.com/leechienpang)
- Fixpack hide unwanted command outputs #86 ([#408](https://github.com/bigstack-oss/cubecos/pull/408)) by [@leechienpang](https://github.com/leechienpang)
- Rolling-upgrade do not run check_repair which brings up pcs on non-control nodes #155 ([#422](https://github.com/bigstack-oss/cubecos/pull/422)) by [@leechienpang](https://github.com/leechienpang)
- Rolling-upgrade unsuccessful live-migration #155 ([#427](https://github.com/bigstack-oss/cubecos/pull/427)) by [@leechienpang](https://github.com/leechienpang)
- Image import misses progress bar in some cases #426 ([#430](https://github.com/bigstack-oss/cubecos/pull/430)) by [@leechienpang](https://github.com/leechienpang)

#### Mongodb

- Upgrade mongodb from 7.0.25 to 7.0.28 to fix the CVE-2025-14847 ([#573](https://github.com/bigstack-oss/cubecos/pull/573)) by [@jdjgya](https://github.com/jdjgya)

#### Non-rolling

- Pcs has no vip resource #155 ([#466](https://github.com/bigstack-oss/cubecos/pull/466)) by [@leechienpang](https://github.com/leechienpang)

#### Nova

- Allow volume-backed instance snapshots to be used to create vms ([#454](https://github.com/bigstack-oss/cubecos/pull/454)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Pcs

- Conflicting constraints ([#582](https://github.com/bigstack-oss/cubecos/pull/582)) by [@leechienpang](https://github.com/leechienpang)

#### Rancher

- Fix the unexpected rancher pod pending during version upgrade in 1cc and 1ec ([#177](https://github.com/bigstack-oss/cubecos/pull/177)) by [@jdjgya](https://github.com/jdjgya)
- Upgrade the terraform rancher module to 7.0.0 to support the rancher server(v2.11.2) operation ([#179](https://github.com/bigstack-oss/cubecos/pull/179)) by [@jdjgya](https://github.com/jdjgya)

#### Rc.nicdetect.sh

- Handle network multiplexer for physical and VM #517 ([#526](https://github.com/bigstack-oss/cubecos/pull/526)) by [@leechienpang](https://github.com/leechienpang)

#### Rolling

- Stale mariadbd hinders service to start #155 ([#443](https://github.com/bigstack-oss/cubecos/pull/443)) by [@leechienpang](https://github.com/leechienpang)
- Mariadbd failed to be repaired #155 ([#455](https://github.com/bigstack-oss/cubecos/pull/455)) by [@leechienpang](https://github.com/leechienpang)

#### Rolling-upgrade

- Keep vip on old firmware to minimize VM down time #155 ([#483](https://github.com/bigstack-oss/cubecos/pull/483)) by [@leechienpang](https://github.com/leechienpang)
- Temporarily remove vaw for backward compatibilities #155 ([#493](https://github.com/bigstack-oss/cubecos/pull/493)) by [@leechienpang](https://github.com/leechienpang)

#### S3

- Empty files in s3://log bucket ([#716](https://github.com/bigstack-oss/cubecos/pull/716)) by [@leechienpang](https://github.com/leechienpang)

#### Security

- Monasca log4j and misc pip pkgs ([#551](https://github.com/bigstack-oss/cubecos/pull/551)) by [@leechienpang](https://github.com/leechienpang)
- Bump up ELK stack versions ([#556](https://github.com/bigstack-oss/cubecos/pull/556)) by [@leechienpang](https://github.com/leechienpang)

#### Terraform

- Upgrade the terraform from 0.14.3 to 1.12.0 for resoving the net/http golib issue ([2d282cf](https://github.com/bigstack-oss/cubecos/commit/2d282cfc60d4040e5b9fa611dfb57fda6083791f)) by [@jdjgya](https://github.com/jdjgya)
- Skip sum check for self build rancher provider ([#538](https://github.com/bigstack-oss/cubecos/pull/538)) by [@arasHi87](https://github.com/arasHi87)

#### Watcher

- Patch watcher's workload balancing strategy ([32d12a6](https://github.com/bigstack-oss/cubecos/commit/32d12a602c8fcae03d7b1424403593055bdc6abb)) by [@jdjgya](https://github.com/jdjgya)
- Add CONFIG_OBSERVES keystone in the watcher ([5dc24c0](https://github.com/bigstack-oss/cubecos/commit/5dc24c0058fb6c7bc9ec548ce9b2580297c29f21)) by [@jdjgya](https://github.com/jdjgya)
- Remove the unnecessary vm_workload_consolidation files ([#515](https://github.com/bigstack-oss/cubecos/pull/515)) by [@jdjgya](https://github.com/jdjgya)
- Fix the incorrect statistic unit for instance_ram_usage from GiB to MiB ([#548](https://github.com/bigstack-oss/cubecos/pull/548)) by [@jdjgya](https://github.com/jdjgya)

### <!-- 3 -->:boom: Refactor

#### App

- Change the implementation of hex's app cli ([0566ad7](https://github.com/bigstack-oss/cubecos/commit/0566ad77de3d294800c39f74b0df66f9a2677320)) by [@jdjgya](https://github.com/jdjgya)

#### Ceph

- Use the absolute path to call mpathconf ([77cc028](https://github.com/bigstack-oss/cubecos/commit/77cc0281471e559a63967b2c0143928286729742)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cinder

- Remove the unused variable model_found ([d8de0e7](https://github.com/bigstack-oss/cubecos/commit/d8de0e787ca89a937a32a28bc0221c5e7f7e9f23)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move error messages to stderr and change the input format of cinder_get_model to json ([4a6ec77](https://github.com/bigstack-oss/cubecos/commit/4a6ec776162d7fdae4d5cf015689293cfe757cb8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Name the built-in model file as the naming convention from the driver name ([#391](https://github.com/bigstack-oss/cubecos/pull/391)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Align ERROR_JSON_NOT_ARRAY error message formats ([3a0f179](https://github.com/bigstack-oss/cubecos/commit/3a0f179e25d6286d2ffe64ccd96276f0c0b67536)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move error messages to stderr in hex_sdk cinder_test_storage ([#394](https://github.com/bigstack-oss/cubecos/pull/394)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Rename the ambiguous field model to type in resource model ([3918777](https://github.com/bigstack-oss/cubecos/commit/3918777cf0e11ce08e33f62e7c4c29e8719a321f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Rename command migrate_large_volume_from_nfs to manage_existing_from_nfs ([10bb300](https://github.com/bigstack-oss/cubecos/commit/10bb3000bd896e925d2fbab2e7afb2b03cd338a1)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move function GetVolumeTypeById to openstack.cpp ([0546f09](https://github.com/bigstack-oss/cubecos/commit/0546f091ef73b6e433f57789b18b1622e438ebe6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move yaml file to json string function to yaml.cpp ([c8acb7e](https://github.com/bigstack-oss/cubecos/commit/c8acb7ee4ccc59a1d428fc9b12f91ec9a1cfc16d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move json string to yaml string function to yaml.cpp ([64ba987](https://github.com/bigstack-oss/cubecos/commit/64ba987777bcf58023331fd6e10d55a64bc591d1)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Handle file system errors in isStorageBackendModified ([f9a2964](https://github.com/bigstack-oss/cubecos/commit/f9a29646fb5b6d2aab4dc93f1f464afee041d77e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cube_sdk_library

- Simplify OpenstackExec parameters ([ef3866d](https://github.com/bigstack-oss/cubecos/commit/ef3866dc6d8699f9aa8e157655ee2af0838ee122)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Docker

- Use cephfs to store the docker registry data ([#400](https://github.com/bigstack-oss/cubecos/pull/400)) by [@jdjgya](https://github.com/jdjgya)

#### Git

- Centralize git lfs records ([00bcf16](https://github.com/bigstack-oss/cubecos/commit/00bcf16414932b77fa6872a3a3cda613728a7bd3)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Glance

- Increase glance's image size cap from 1 TiB to 2 TiB ([28e536a](https://github.com/bigstack-oss/cubecos/commit/28e536a4ca6326e75138d46250a95103a2698965)) by [@jdjgya](https://github.com/jdjgya)
- Add a new conf - 'node_staging_uri' for placing the tmp transition file ([#487](https://github.com/bigstack-oss/cubecos/pull/487)) by [@jdjgya](https://github.com/jdjgya)
- Separate import logics based on business logics ([#597](https://github.com/bigstack-oss/cubecos/pull/597)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_cli

- Collect iaas functions under command iaas ([9e75dcf](https://github.com/bigstack-oss/cubecos/commit/9e75dcfb3c46d7f8b72ad2c6ead4da5adb93ef14)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move GetFilesUnderDirectory to filesystem.cpp ([7b7c121](https://github.com/bigstack-oss/cubecos/commit/7b7c121ecc2f60e3a4bf040e97e40c1dc3dd1ed2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Avoid type conversions ([#542](https://github.com/bigstack-oss/cubecos/pull/542)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_config

- Move openstack cli binary path to constant.hpp ([e44cb02](https://github.com/bigstack-oss/cubecos/commit/e44cb027deb4c9acf5352755e6ee791bc6c8c213)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_sdk

- Use absolute path for logger in logging functions ([e251234](https://github.com/bigstack-oss/cubecos/commit/e2512349c2e5ec869c68824147b6ec33a63c8e3a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Kapacitor

- Move event.yaml to kapacitor folder under cubecos static data ([c6fda27](https://github.com/bigstack-oss/cubecos/commit/c6fda27ed6a7b0b2a44535abf10a4926fbc2841f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Keycloak

- Move keycloak status command from cubectl to hex_config ([295b0fc](https://github.com/bigstack-oss/cubecos/commit/295b0fc07493fb37f170f0b49d42e221f43c8eff)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move keycloak check command from cubectl to hex_config ([705234f](https://github.com/bigstack-oss/cubecos/commit/705234f567bb663c9d58717de09c72dfb9504936)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move keycloak repair command from cubectl to hex_config ([09fd5b8](https://github.com/bigstack-oss/cubecos/commit/09fd5b899e5921b8fd512cfd6a45923f80fc2088)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move keycloak reset command from cubectl to hex_config ([1f8e137](https://github.com/bigstack-oss/cubecos/commit/1f8e1370c6399e97bee519b1cb7b8113284469e8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move keycloak commit command from cubectl to hex_config ([a215a1d](https://github.com/bigstack-oss/cubecos/commit/a215a1d991c8c4ac6eaa474342bee32beff2c02c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Remove old code ([088133f](https://github.com/bigstack-oss/cubecos/commit/088133fd46f68035c26e7db04f79a6d5c8d10981)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Make

- Let upstreams maintain their NodeJS version through .nvmrc ([50b7508](https://github.com/bigstack-oss/cubecos/commit/50b7508112ddb5d9dd1e7a911967896e9e72d6be)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Set relative paths for rpm targets ([#175](https://github.com/bigstack-oss/cubecos/pull/175)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Create config directories in the build jail ([#206](https://github.com/bigstack-oss/cubecos/pull/206)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Adjust makefiles ([42af753](https://github.com/bigstack-oss/cubecos/commit/42af753136fc0abf60eb0338016f73578bca6def)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### <!-- 4 -->:memo: Documentation

#### Changelog

- Adjust the base tag ref for v3.0.0-rc4 ([#489](https://github.com/bigstack-oss/cubecos/pull/489)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cinder

- Input as parameters instead of stdin ([#387](https://github.com/bigstack-oss/cubecos/pull/387)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Remove stderr section in cinder_get_models ([fa2329a](https://github.com/bigstack-oss/cubecos/commit/fa2329ad8a58dc97b3b3971f795efe56f2404251)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add interface details of hex_sdk cinder_delete_model ([bcad31d](https://github.com/bigstack-oss/cubecos/commit/bcad31dc8991fd336ee87ab9756e5854efef5a27)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add docs for cli > iaas > volume_backend > set_model ([#504](https://github.com/bigstack-oss/cubecos/pull/504)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_sdk

- Add exec shell and bin related outputs into comments ([f1b53b3](https://github.com/bigstack-oss/cubecos/commit/f1b53b3cfbd2ee13a37605bf6b564d6099731bc9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Keycloak

- Add hex_config command update_keycloak_admin_password usage ([#450](https://github.com/bigstack-oss/cubecos/pull/450)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Miscellaneous

- Update README ([#226](https://github.com/bigstack-oss/cubecos/pull/226)) by [@bigstack-brian-su](https://github.com/bigstack-brian-su)
- Update CONTRIBUTING and MAINTAINERS ([#341](https://github.com/bigstack-oss/cubecos/pull/341)) by [@bigstack-brian-su](https://github.com/bigstack-brian-su)
- :memo: create initial changelog version ([10ea43a](https://github.com/bigstack-oss/cubecos/commit/10ea43a1bc8a87ee64888d710cfe8dbd326c9087)) by [@bigstack-brian-su](https://github.com/bigstack-brian-su)
- Update 3.1.0 changelog and prepare conventional commit template ([#718](https://github.com/bigstack-oss/cubecos/pull/718)) by [@bigstack-brian-su](https://github.com/bigstack-brian-su)

#### Readme

- Update readme ([92d7b1b](https://github.com/bigstack-oss/cubecos/commit/92d7b1bf8b607356e0a08c3576e3722b95b0f1e8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add community channels ([3ea59ee](https://github.com/bigstack-oss/cubecos/commit/3ea59eeae74336012b28db0e48dda900a6f4521b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add supported dev os ([caee595](https://github.com/bigstack-oss/cubecos/commit/caee5956d0c12e982d25f2e1e52dbc2bee982d6a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Update disk space size for dev ([#166](https://github.com/bigstack-oss/cubecos/pull/166)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### Miscellaneous Tasks

#### Bump

- Bump version to v3.1.0 ([9a2fd5a](https://github.com/bigstack-oss/cubecos/commit/9a2fd5ad6a56a3424477a6424283276381635b15)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump keycloak image tag to 17.2.0 ([b7b694c](https://github.com/bigstack-oss/cubecos/commit/b7b694c87ce000c128b1442f2521c1a23543a42e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Ceph

- Format config_ceph.cpp ([4a0fab6](https://github.com/bigstack-oss/cubecos/commit/4a0fab6700bc1d946c32e10c2995f105bf7a5aba)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Ci

- Apply hardened runner configuration ([8fed148](https://github.com/bigstack-oss/cubecos/commit/8fed1483ddb667a55b313e81da6024d7517297bc)) by [@bigstack-brian-su](https://github.com/bigstack-brian-su)

#### Cinder

- Remove testing code ([#514](https://github.com/bigstack-oss/cubecos/pull/514)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cube_sdk_library

- Fix the typo in filesystem.cpp ([#502](https://github.com/bigstack-oss/cubecos/pull/502)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cubectl

- Upgrade the golang.org/x/crypto from 0.25.0 to 0.31.0 ([611e9ed](https://github.com/bigstack-oss/cubecos/commit/611e9eda48f437c4491b3b1cad8fcb7aa879ef61)) by [@jdjgya](https://github.com/jdjgya)
- Upgrade the golang.org/x/crypto from 25.0.5 to 25.0.6 by upgrade the helm.sh/helm/v3 from 3.15.3 to 3.16.0 ([2c66c8f](https://github.com/bigstack-oss/cubecos/commit/2c66c8f5cb12f96ef690f84fa5196e9b7d3dc4bf)) by [@jdjgya](https://github.com/jdjgya)
- Upgrade the golang.org/x/crypto from 0.31.0 to 0.40.0 ([cd3d2b4](https://github.com/bigstack-oss/cubecos/commit/cd3d2b4b723444249e062f38b8e6bc965b70d581)) by [@jdjgya](https://github.com/jdjgya)
- Upgrade the helm.sh/helm/v3 from v3.16.0 to 3.18.4 ([7ff7b6d](https://github.com/bigstack-oss/cubecos/commit/7ff7b6d1cb611ea6da83c84e34f89ff5b5e323a9)) by [@jdjgya](https://github.com/jdjgya)
- Upgrade the helm.sh/helm/v3 from v3.18.4 to 3.19.0 ([bfd8e57](https://github.com/bigstack-oss/cubecos/commit/bfd8e57ea1c8b1da8b5d9635e507646cfbf19f92)) by [@jdjgya](https://github.com/jdjgya)
- Upgrade the golang.org/x/crypto from v0.43.0 to 0.45.0 ([#518](https://github.com/bigstack-oss/cubecos/pull/518)) by [@jdjgya](https://github.com/jdjgya)

#### Deps

- Bump github/codeql-action from 3.30.1 to 3.30.3 ([#376](https://github.com/bigstack-oss/cubecos/pull/376)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump github/codeql-action from 3.30.3 to 3.30.5 ([8e7601d](https://github.com/bigstack-oss/cubecos/commit/8e7601dc186565bb847b98bedc9c64135e559f62)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Etcd

- Upgrade etcd from 3.5.5 to 3.5.18 to patch the security update of golang.org/x/crypto ([36409bf](https://github.com/bigstack-oss/cubecos/commit/36409bff7d3aa8d9bcec6031c066c4b8fd560f30)) by [@jdjgya](https://github.com/jdjgya)

#### Gpu

- Drop the old vgpu grid driver container image ([9cfb6b1](https://github.com/bigstack-oss/cubecos/commit/9cfb6b1ddbf2143ecea72b95b1b9b28af06e16ff)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Format cli_gpu.cpp ([484163a](https://github.com/bigstack-oss/cubecos/commit/484163ad0437b4ff688e77b2cbd3979084b22d5b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Grafana

- Bump grafana to 10.3.12 ([c1741e2](https://github.com/bigstack-oss/cubecos/commit/c1741e2da4a5ec42d5c875554af2c96a624aeeff)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_cli

- Format cli_alert_resp cpp code using WebKit coding style ([3c4fecd](https://github.com/bigstack-oss/cubecos/commit/3c4fecd38a57825f1b2583ea173558128e184999)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Format policy_notify cpp code using WebKit coding style ([8dbe922](https://github.com/bigstack-oss/cubecos/commit/8dbe922b12ae1b1ad1663cbefd7f2da9c97a47c5)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Organize cli_iaas_volume.cpp ([#488](https://github.com/bigstack-oss/cubecos/pull/488)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Remove cli > storage > toggle_diskcheck ([594d4d9](https://github.com/bigstack-oss/cubecos/commit/594d4d99ef59442b8618bad2bfe56e4dafa44d67)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Format cli_ceph.cpp ([5e7d618](https://github.com/bigstack-oss/cubecos/commit/5e7d618394cd23775aaac857ddd5f22d5a3c04c0)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_config

- Format config_api cpp code using WebKit coding style ([1536354](https://github.com/bigstack-oss/cubecos/commit/15363548e183b975fa45d0e7974e8551d8a0391e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Format config_nginx cpp code using WebKit coding style ([8f18cf2](https://github.com/bigstack-oss/cubecos/commit/8f18cf26b3a89ddbe610f0208a72512ad2b5107b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Format config_skyline cpp code using WebKit coding style ([77c0578](https://github.com/bigstack-oss/cubecos/commit/77c0578a84c05f1aabf8174f193c12364a7bee00)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Format role_cubesys.h cpp code using WebKit coding style ([f48a7c5](https://github.com/bigstack-oss/cubecos/commit/f48a7c593eb02ae67f8a2231048130d3e3d3a633)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Format cluster.h cpp code using WebKit coding style ([89bd10e](https://github.com/bigstack-oss/cubecos/commit/89bd10ea0db99f747829449664f4f66bb7cc4d13)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Format config_cinder cpp code using WebKit coding style ([#348](https://github.com/bigstack-oss/cubecos/pull/348)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_install

- Fix the typo in the comment ([eb5eabf](https://github.com/bigstack-oss/cubecos/commit/eb5eabff8c41ced1312e7fb3fb404ca2dfe3e2f1)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_sdk

- Remove the unused local variable vol_name ([12e420e](https://github.com/bigstack-oss/cubecos/commit/12e420e68db8372a9b5512c464de4cb6a62cafab)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_translate

- Format translate_alert_resp cpp code using WebKit coding style ([2d0bf12](https://github.com/bigstack-oss/cubecos/commit/2d0bf120dbb684e362463d79787cb0f782643c08)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Format translate_alert_setting cpp code using WebKit coding style ([ad89c15](https://github.com/bigstack-oss/cubecos/commit/ad89c15e405f53287a7d7d0ef352ffcb3e59fac7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### K3s

- Allow more memory usage for k3s ([#182](https://github.com/bigstack-oss/cubecos/pull/182)) by [@jdjgya](https://github.com/jdjgya)
- Format config_k3s.cpp ([7fd3c93](https://github.com/bigstack-oss/cubecos/commit/7fd3c93606da89cbf9d9ab379496b763cbaa71d3)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### K3s cephcsi

- Upgrade cephcsi from 3.11.0 to 3.13.1 for crypto lib upgrade ([c6da72f](https://github.com/bigstack-oss/cubecos/commit/c6da72fcd9cdc6dbbcbffd4467949bd0f51963d3)) by [@jdjgya](https://github.com/jdjgya)

#### License

- Update license type option prime to enterprise ([985d168](https://github.com/bigstack-oss/cubecos/commit/985d168a2b7f790e02ad9d1535c14cf0de3efaa1)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Mongodb

- Bump mongodb to 7.0.25-1 ([4ca67fc](https://github.com/bigstack-oss/cubecos/commit/4ca67fcbe280b095ba761112eda2314e04e5a1c8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Pr

- Set code owners to the backend team ([#168](https://github.com/bigstack-oss/cubecos/pull/168)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Senlin

- Remove the senlin service from cos ([#477](https://github.com/bigstack-oss/cubecos/pull/477)) by [@jdjgya](https://github.com/jdjgya)

#### Terraform

- Polish the debug info ([2236d62](https://github.com/bigstack-oss/cubecos/commit/2236d62c334e3718ab450591a2292c2475771530)) by [@arasHi87](https://github.com/arasHi87)

#### Typo

- Fix typo ([e8b5ac9](https://github.com/bigstack-oss/cubecos/commit/e8b5ac973c0f17b7df60aa45d4c1edb9825bb80b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### Security

#### Build

- Make sbom ([#544](https://github.com/bigstack-oss/cubecos/pull/544)) by [@leechienpang](https://github.com/leechienpang)

#### Miscellaneous

- Support cephfs file size up to 4TiB #412 ([#413](https://github.com/bigstack-oss/cubecos/pull/413)) by [@leechienpang](https://github.com/leechienpang)

### Build

#### K3s

- Add the custom build script for k3s binary build ([76d45a7](https://github.com/bigstack-oss/cubecos/commit/76d45a769066d2d66c3649c8a2e97bc28648480d)) by [@arasHi87](https://github.com/arasHi87)

#### Provider

- Update the package to pass the security scan ([#530](https://github.com/bigstack-oss/cubecos/pull/530)) by [@arasHi87](https://github.com/arasHi87)

#### Rc

- Release v3.1.0-rc1 ([#584](https://github.com/bigstack-oss/cubecos/pull/584)) by [@jdjgya](https://github.com/jdjgya)
- Release v3.1.0-rc3 ([#704](https://github.com/bigstack-oss/cubecos/pull/704)) by [@jdjgya](https://github.com/jdjgya)
- Release v3.1.0-rc3 (round 2) ([#707](https://github.com/bigstack-oss/cubecos/pull/707)) by [@jdjgya](https://github.com/jdjgya)

### New

#### Bootstrap

- Allow auto_repair to kick in first ([#693](https://github.com/bigstack-oss/cubecos/pull/693)) by [@leechienpang](https://github.com/leechienpang)

### Revert

#### Cinder

- Revert back to running cinder services on control nodes only ([d3ba8dc](https://github.com/bigstack-oss/cubecos/commit/d3ba8dcb64287a0b03327b37fec6201e757f2710)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Docker

- Use cephfs to store the docker registry data ([#406](https://github.com/bigstack-oss/cubecos/pull/406)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### Sec

#### Cve-2026-21721

- Grafana Cross-dashboard privilege escalation #699 ([838f359](https://github.com/bigstack-oss/cubecos/commit/838f3597cfe7ac2b768adae1023762e7b2d522b3)) by [@leechienpang](https://github.com/leechienpang)

### Test


