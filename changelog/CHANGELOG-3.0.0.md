## [3.0.0](https://github.com/bigstack-oss/cubecos/releases/tag/v3.0.0) - 2025-06-08

### <!-- 0 -->:rocket: New Features

#### Alert

- Cli & policy for alert setting ([0e87140](https://github.com/bigstack-oss/cubecos/commit/0e87140a7fcf62b84700c219a8aa07cd6a19b6d2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Translate for alert setting ([bcf8153](https://github.com/bigstack-oss/cubecos/commit/bcf81533d0cf4db15cd4ddbc954f9d08768baaa7)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add checks before loading the alert_setting policy into the config ([5770a1a](https://github.com/bigstack-oss/cubecos/commit/5770a1af0e817b375fde601033d95ab694f76a1b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add field titlePrefix to alert setting policy ([6ace75b](https://github.com/bigstack-oss/cubecos/commit/6ace75b36a308a51366ffc8df28f3862704b8e71)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add exec shells and bins to alert setting CLI, policy, translate, and sdk_alert.sh ([c66284e](https://github.com/bigstack-oss/cubecos/commit/c66284ecdcba53fda142b1097d64278e71dc12b6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Cli for alert trigger ([6986072](https://github.com/bigstack-oss/cubecos/commit/69860725f2ad74bdae90b8dd1813c7cb622cc5fb)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Policy for alert trigger ([8f67d50](https://github.com/bigstack-oss/cubecos/commit/8f67d50af11cf99b6e8e9e99508ed28c9446ab26)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Sync alert setting and alert trigger policies ([191fc40](https://github.com/bigstack-oss/cubecos/commit/191fc40f65e53c836f91b542967dba91cb5ff5b5)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Check receivers in alert setting while updating triggers for alert trigger ([e5f4e3e](https://github.com/bigstack-oss/cubecos/commit/e5f4e3ed5f87ad0a28e19b2234c80cbf7f08c72b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Sdk function to add or update alert triggers ([a319d9e](https://github.com/bigstack-oss/cubecos/commit/a319d9ebb89eef7ef0be1f81fa313a70574ab760)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Delete on cascade from alert setting to alert trigger ([689d63b](https://github.com/bigstack-oss/cubecos/commit/689d63b44a0541578fc2ba90c334d1a92e5163f2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Hex_translate for alert trigger ([b33732a](https://github.com/bigstack-oss/cubecos/commit/b33732a740cf9c79357276c1ba1c35f905f23ee9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Hex_sdk alert_get_trigger ([c3c52c7](https://github.com/bigstack-oss/cubecos/commit/c3c52c77caeeb88d06320ecbbb9f0ad96f7de480)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Hex_sdk alert_get_full_trigger ([9e2298b](https://github.com/bigstack-oss/cubecos/commit/9e2298b09b9569345cd88ff7bf190f7043ac1ec6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Hex_config for alert setting and alert trigger ([9da6c5e](https://github.com/bigstack-oss/cubecos/commit/9da6c5e5b8d29b3530d9120adddb6b7e4257e7bc)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add the title prefix to alert messages ([#57](https://github.com/bigstack-oss/cubecos/pull/57)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Cli notifications list ([35acc46](https://github.com/bigstack-oss/cubecos/commit/35acc46b00fdb9dbfef63116a2cffec9b69da1d6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Remove the old cli command configure ([#68](https://github.com/bigstack-oss/cubecos/pull/68)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Migrate alert_resp1_0 policy to alert_setting1_0 and alert_resp2_0 policy ([#70](https://github.com/bigstack-oss/cubecos/pull/70)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Api

- Set proxy for api ([5cffc5f](https://github.com/bigstack-oss/cubecos/commit/5cffc5fad39710069e118acdfe4e49f8aa35db7d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Install api to cubecos ([e3ab6e1](https://github.com/bigstack-oss/cubecos/commit/e3ab6e12ebbe65d9a12a78c67bfa25fe0f1981b0)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Hex_config for api ([83cda9a](https://github.com/bigstack-oss/cubecos/commit/83cda9aabf3c861811bbc144475e64bf76c3f923)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Cluster check and repair for api ([f89d5bc](https://github.com/bigstack-oss/cubecos/commit/f89d5bcc9319bc054a370a4876a491d425701bb6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add service dependencies of api ([070a3cc](https://github.com/bigstack-oss/cubecos/commit/070a3cce1a06699f7e19db00d49468631db344c2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add the missing saml client config to api health repair ([#31](https://github.com/bigstack-oss/cubecos/pull/31)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use the hashed mongodb password to access mongodb ([2baaeb5](https://github.com/bigstack-oss/cubecos/commit/2baaeb511c04bcf081437e49a990e178c56a898c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Haproxy

- Adjust cube-cos-api liveness probe endpoint settings in haproxy ([edca79c](https://github.com/bigstack-oss/cubecos/commit/edca79cbfa7976879b925d4f49a4dc0f37f20d10)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_cli

- Add command tree to list out all enabled commands ([d67ba9a](https://github.com/bigstack-oss/cubecos/commit/d67ba9ad44e686b934ffb348553e5b37191493f9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_sdk

- Alert_get_setting to output alert setting as a json ([52391a3](https://github.com/bigstack-oss/cubecos/commit/52391a38e93c2b1a41ffa528bdbe55f758d1528f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add set, put, and delete functions for alert setting ([dcd7c3f](https://github.com/bigstack-oss/cubecos/commit/dcd7c3fb8a30cfbf21e61a91dd3ceee732d19e71)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Filter out the blank child of alert setting receivers ([b74893a](https://github.com/bigstack-oss/cubecos/commit/b74893acfe3903733b59ebea954f3f4db404f9d1)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Influxdb

- Only expose influxdb on mgmt ip and vip ([3b2fda5](https://github.com/bigstack-oss/cubecos/commit/3b2fda5793993da90143a2ce448436da2645f8ed)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Kapacitor

- Change kapacitor self log level from INFO to ERROR ([a16b7bf](https://github.com/bigstack-oss/cubecos/commit/a16b7bff4775d0e0e52c3a8155a8c8531f2656ec)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Keycloak

- Use terraform to insert saml client config to keycloak for api ([f2e3a2b](https://github.com/bigstack-oss/cubecos/commit/f2e3a2b8579b9c2d2b3de4061057b514829524ce)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Install login to cubecos ([00bbcad](https://github.com/bigstack-oss/cubecos/commit/00bbcad754fd8b988fb368f9167b8bb35980a836)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### License

- Add name and rename sla to support plan ([bbe40bb](https://github.com/bigstack-oss/cubecos/commit/bbe40bbdb05de9d7da6852737390b4664dbba9b2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Lmi

- Remove lmi, let ui and api take over ports, and serve rancher node drivers through httpd ([eb52888](https://github.com/bigstack-oss/cubecos/commit/eb528880cd872edb78b4e4c8d303f42c54e6defe)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Miscellaneous

- Json output for hex_config -P and regex validate for str type ([#25](https://github.com/bigstack-oss/cubecos/pull/25)) by [@leechienpang](https://github.com/leechienpang)
- SDK -f json DumpInterface (#17) ([49fe485](https://github.com/bigstack-oss/cubecos/commit/49fe485754488cc202f4437d905bf76bdd71b59e)) by [@leechienpang](https://github.com/leechienpang)
- Tuning_dump to display net interfaces ethx according to settings (#30) ([#32](https://github.com/bigstack-oss/cubecos/pull/32)) by [@leechienpang](https://github.com/leechienpang)
- CLI image import with additional properties (#35) ([#46](https://github.com/bigstack-oss/cubecos/pull/46)) by [@leechienpang](https://github.com/leechienpang)
- SDK opensearch_ops_reqid_url req-id (#54) ([#55](https://github.com/bigstack-oss/cubecos/pull/55)) by [@leechienpang](https://github.com/leechienpang)

#### Mongodb

- Only expose mongodb on mgmt ip and vip ([e9e9c23](https://github.com/bigstack-oss/cubecos/commit/e9e9c23bd77aa1d22ac5af5431f9848c8b86d6b4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Protect mongodb with a hashed password ([99f59be](https://github.com/bigstack-oss/cubecos/commit/99f59befe9b6e9075917b849f6ff0c11f7227151)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Nginx

- Separate nginx from skyline config ([6e0fc84](https://github.com/bigstack-oss/cubecos/commit/6e0fc84599814593f4610b744115c4ca22c8b11d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Set cluster check repair functions ([#14](https://github.com/bigstack-oss/cubecos/pull/14)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Release

- Release configurations ([18bfb36](https://github.com/bigstack-oss/cubecos/commit/18bfb368a03cc793c323eb670b4c50c8a835cac0)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Skyline

- Move path rewrite to backend nginx ([9077337](https://github.com/bigstack-oss/cubecos/commit/9077337f7d1e2c3be951b08d4e5c45557cb9ada3)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Ui

- Serve ui using nginx ([3889c63](https://github.com/bigstack-oss/cubecos/commit/3889c63cd76eed2254cb5b6434ec1735bd734a15)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Install ui to cubecos ([c00309d](https://github.com/bigstack-oss/cubecos/commit/c00309d37917ff81279f42b593e762558f4ec5f8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add a liveness endpoint for haproxy ([8c21019](https://github.com/bigstack-oss/cubecos/commit/8c21019643e87f5efd8ed70be01bca220f48a0c1)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### <!-- 1 -->:bug: Bug fixes

#### Alert

- Allow delete using iterator and avoid iterator invalidation in alert_setting policy ([6ca9430](https://github.com/bigstack-oss/cubecos/commit/6ca9430537fb3213b1d5531fa00622fbc27a2b42)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Convert std::string to C style string for fprintf and use the correct format specifier for std::size_t ([5cee4eb](https://github.com/bigstack-oss/cubecos/commit/5cee4ebb10aee952bbdd744c20a8308bac94becc)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add a blank child if we do not have any to make the yaml parser work ([26298e7](https://github.com/bigstack-oss/cubecos/commit/26298e7ed627ce3567162c0bb52d5c41f39428fe)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add the missing write line to write the yaml tree back to the policy file ([7b75222](https://github.com/bigstack-oss/cubecos/commit/7b75222b7403eb3e63df588b57ef4166e34b380a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Failed to set alert setting and alert trigger policies after syncing them ([2f6eac5](https://github.com/bigstack-oss/cubecos/commit/2f6eac585bfe515a2414696b53607c3b66afabc8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Apache2

- Flush dirty arp records after pacemaker vip moves ([#74](https://github.com/bigstack-oss/cubecos/pull/74)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Api

- Add the missing sdk_api.sh to hex_sdk ([c3a65f2](https://github.com/bigstack-oss/cubecos/commit/c3a65f21432892c986aeb055e3ed395dd24f0fe2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Reset api_idp status during cube_cluster_recreate ([bd1f799](https://github.com/bigstack-oss/cubecos/commit/bd1f79916f3b04c70889f12503309b071a4c37b5)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make api only listen to the mgmt address ([675c998](https://github.com/bigstack-oss/cubecos/commit/675c998686ebf13fd17387f16b295eebb262a56d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Conform the api set up to cubecos customs ([cebc979](https://github.com/bigstack-oss/cubecos/commit/cebc979a1339b545f3eb68145f0843039ac212d0)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Appfw

- Revert changes regarding the node driver name ([#133](https://github.com/bigstack-oss/cubecos/pull/133)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Ceph

- Update hdsentinel download link ([ce1e2fd](https://github.com/bigstack-oss/cubecos/commit/ce1e2fd6d40792c044f2e6656abf25e6f4c2207c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Ci

- Enhance ci security ([063e5a2](https://github.com/bigstack-oss/cubecos/commit/063e5a209395a9451935e812c7399a1dcd98accb)) by [@bigstack-brian-su](https://github.com/bigstack-brian-su)

#### Deps

- Grub2-common-2.06-80.el9.noarch.rpm not found ([c01366d](https://github.com/bigstack-oss/cubecos/commit/c01366d23b12978043ff53c1a1d17ba69500521d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Ha

- Typo ([a2814df](https://github.com/bigstack-oss/cubecos/commit/a2814df401dccc39ef651c2862d8c8e60c1f67cb)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Health

- Repair api on non-ha nodes ([6bbe336](https://github.com/bigstack-oss/cubecos/commit/6bbe3363ea4d3d155a660df4e2c6bfe975621ccd)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Reorder api check logics ([30e5606](https://github.com/bigstack-oss/cubecos/commit/30e5606d4713553d9e007b663b2dd77bb94684a6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Consider the vip key on non-control nodes ([76a5db8](https://github.com/bigstack-oss/cubecos/commit/76a5db887ec93641deb5f02540c0d729674f9cf1)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bootstrap kapacitor in data pipe deep repair ([ff2ec26](https://github.com/bigstack-oss/cubecos/commit/ff2ec2684de233065fc6c32b9e9614ea2cd16928)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Heavyfs

- Build failures due to makefile variable missing, image format change, and skyline yarn using the older version of nodejs ([105b834](https://github.com/bigstack-oss/cubecos/commit/105b83424229147cfc0e25be72e82caefb5043fc)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Install yq to heavyfs ([#33](https://github.com/bigstack-oss/cubecos/pull/33)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_cli

- Reorder update and delete in notifications > configure ([fc3899f](https://github.com/bigstack-oss/cubecos/commit/fc3899f3d69d10ebce827b66330420b84d4858c6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Set the virtual destructor on the abstract class HexPolicy to enable polymorphic deletion through pointers ([8e809fb](https://github.com/bigstack-oss/cubecos/commit/8e809fb2d3071449d5efa7b6c38ba0807a29d4a5)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add the missing header assert.h to policy_notify.h ([dff23ce](https://github.com/bigstack-oss/cubecos/commit/dff23ce7d9467b8ef349f18ad2868a6005a65d95)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Provide the definition to the virtual destructor of the abstract class HexPolicy ([09a204d](https://github.com/bigstack-oss/cubecos/commit/09a204d9ae07be70b9f21757fe75a63b6aa51455)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Set the correct index for usb and local for notifications > configure for exec shell & exec bin ([c80d434](https://github.com/bigstack-oss/cubecos/commit/c80d4347fffbda3f385f38964e3576c92665a617)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Remove the duplicated output line in image > import ([#109](https://github.com/bigstack-oss/cubecos/pull/109)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_sdk

- File inclusion errors during bootstrap ([7e4991f](https://github.com/bigstack-oss/cubecos/commit/7e4991f4afe62b6776b334e88e45485dc99b33e9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Shared_id access denied during first time set up (hex_cli) ([acec212](https://github.com/bigstack-oss/cubecos/commit/acec212f0cc9b4e817fece5ead5693fbcd7a1f33)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Add the missing target ./core/sdk_sh/modules.pre/sdk_license.sh ([e6515db](https://github.com/bigstack-oss/cubecos/commit/e6515dbc177f6b7a2a9f13f367c14f1fa7e106a6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Pass in capitalized env for appfw.tgz deploy.sh to work ([dd08600](https://github.com/bigstack-oss/cubecos/commit/dd0860050d69453b9bb5ff17d48de70ef33ae7fb)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Prevent word splitting ([8f7a9db](https://github.com/bigstack-oss/cubecos/commit/8f7a9dbaa7ab28d5bc6074dc7aa1e6012667b576)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Only handle the word splitting of arguments ([#49](https://github.com/bigstack-oss/cubecos/pull/49)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Output ceph osd tree-from messages ([dc8e25d](https://github.com/bigstack-oss/cubecos/commit/dc8e25d0c7d65d99c7c75da791cfe383309a8eee)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Avoid word splitting of image import name ([e9eae14](https://github.com/bigstack-oss/cubecos/commit/e9eae14d15fe5031b09e5b4da038b13e7a4676ce)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Open output from hex_sdk os_nova_instance_ping to telegraf for grafana vm instance ping graph ([#104](https://github.com/bigstack-oss/cubecos/pull/104)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_translate

- Add the missing reference to hex_translate ([340de32](https://github.com/bigstack-oss/cubecos/commit/340de3266be7656900a9a6bd71df28a94437ec71)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Jail

- Adjust jail settings for the new repo name ([82d9199](https://github.com/bigstack-oss/cubecos/commit/82d9199b0b57e2845bb4bc5bc0390073e21d723b)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Kernel

- Kernel version 6.1.123 not found ([#63](https://github.com/bigstack-oss/cubecos/pull/63)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Keycloak

- Add back the missing prerequisite to keycloak/Makefile ([b3ee3e8](https://github.com/bigstack-oss/cubecos/commit/b3ee3e808d99295b02b217b9c594f36ad1ad13b2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Enable nvm to read parameters ([440c4ac](https://github.com/bigstack-oss/cubecos/commit/440c4ac8e3c788cb0cf7442a45f189b0b4d2372d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Bump keycloak version in the helm chart ([cfec6b4](https://github.com/bigstack-oss/cubecos/commit/cfec6b4394e7d98b63990022f6327c6a2bc9bb9d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Reset keycloak to load the new image during bootstrap ([1347e0d](https://github.com/bigstack-oss/cubecos/commit/1347e0d390325c2809b39e03b05a13f1ee2387d2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Keycloak failed to start during bootstrapping ([3daab06](https://github.com/bigstack-oss/cubecos/commit/3daab060fe041a7b3aecea223944e4c1c186e5e8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Only allow the master node to modify keycloak to stop nodes from tripping over each others' keycloak bootstrapping ([4fed0bf](https://github.com/bigstack-oss/cubecos/commit/4fed0bfc176675e0f44e47bd812e38687814ae12)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Get saml-metadata.xml for saml sp services on non-master nodes ([67fbf27](https://github.com/bigstack-oss/cubecos/commit/67fbf271844ea7d016ff1405165a2ec38f8e4800)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Only update keycloak during cluster_start ([af30e1b](https://github.com/bigstack-oss/cubecos/commit/af30e1bec3ad1c1ea039adf846622d189d89272d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Avoid catching keycloak bootstrapping errors ([b80b9d0](https://github.com/bigstack-oss/cubecos/commit/b80b9d0b93b0aec88fe44251d45c8d66a9f9506d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Sync keycloak saml-metadata.xml after upgrade in cluster start ([#19](https://github.com/bigstack-oss/cubecos/pull/19)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Do not destroy keycloak during node level bootstrapping ([bc021f7](https://github.com/bigstack-oss/cubecos/commit/bc021f745fea7601bc25325d57db5fdef5f5100a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Keycloak-login

- Bump the version to force update images on helm ([64c12b2](https://github.com/bigstack-oss/cubecos/commit/64c12b20e594ad572f016f51a2798a408f11c76c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### License

- Use UTC time to read the expiry date from the license ([#110](https://github.com/bigstack-oss/cubecos/pull/110)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Make

- Stop nvm from slowing down bash ([0ad8e24](https://github.com/bigstack-oss/cubecos/commit/0ad8e24fa7970ba5ebf5d6f678f9fc5773d37fc4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Persist vanishing version and build number ([4467fca](https://github.com/bigstack-oss/cubecos/commit/4467fca37bf5a4d7275032bd66fc16c8707f7f35)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Reorder core component to make hidden dependency of docker on keycloak work ([5feacca](https://github.com/bigstack-oss/cubecos/commit/5feaccab4176e6f72bce1a722a619c709b76e403)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Resolve the hidden docker registry make dependency ([b2a32b5](https://github.com/bigstack-oss/cubecos/commit/b2a32b52b82b3d73ffdf1a5a44be23e988c54c1f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Node command not found while reading version infos ([3690a26](https://github.com/bigstack-oss/cubecos/commit/3690a26799001c2252bd24dadbcbc852dd4faaf6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make docker the first one of the image series to make ([90a3ea3](https://github.com/bigstack-oss/cubecos/commit/90a3ea3192f9cae8e3f1c40de595e79e7f9941d5)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Remove hidden folders while creating the source tarball for rpm ([cae46c1](https://github.com/bigstack-oss/cubecos/commit/cae46c16c0cbadb43ef16233e63b76cb60692b81)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use nodejs 12 to build skyline-console ([720dcd1](https://github.com/bigstack-oss/cubecos/commit/720dcd1f6ca96d7a1cea836deb1ae95a1f767cb0)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use rpm instead of dnf in rc builds ([#81](https://github.com/bigstack-oss/cubecos/pull/81)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Try another mirror for centos stream 9 highavailability ([94dd68d](https://github.com/bigstack-oss/cubecos/commit/94dd68dda7f977724dc81f07c04b376c2b47dfdf)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Miscellaneous

- SDK wait_for_http_endpoint takes too long when curl fails ([ff69cdf](https://github.com/bigstack-oss/cubecos/commit/ff69cdf5e4114c105fe632658b2361841b9084b4)) by [@leechienpang](https://github.com/leechienpang)
- After FW upgrade, ceph mgr pool misses application ([#27](https://github.com/bigstack-oss/cubecos/pull/27)) by [@leechienpang](https://github.com/leechienpang)
- Hex_config sdk_run should return what SDK returns (#29) ([#37](https://github.com/bigstack-oss/cubecos/pull/37)) by [@leechienpang](https://github.com/leechienpang)
- Unable to open unix socket on ext4 with kernel > 6.1.123 ([#64](https://github.com/bigstack-oss/cubecos/pull/64)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- SDK -f json DumpInterface to support bonding interfaces (#60) ([#65](https://github.com/bigstack-oss/cubecos/pull/65)) by [@leechienpang](https://github.com/leechienpang)
- VMs in error state after cluster powercycle (#71) ([#73](https://github.com/bigstack-oss/cubecos/pull/73)) by [@leechienpang](https://github.com/leechienpang)
- SDK tuning_dump net.if.mtu not expanded (#76) ([#78](https://github.com/bigstack-oss/cubecos/pull/78)) by [@leechienpang](https://github.com/leechienpang)
- Bootstrapping in parallel can fail due to vip change (#79) ([ee1854c](https://github.com/bigstack-oss/cubecos/commit/ee1854c611bcc8edcb66ff475789726d0281e9a3)) by [@leechienpang](https://github.com/leechienpang)
- Quiet unwanted msg from su - admin ([#83](https://github.com/bigstack-oss/cubecos/pull/83)) by [@leechienpang](https://github.com/leechienpang)
- SDK mongodb_check syntax errors ([#129](https://github.com/bigstack-oss/cubecos/pull/129)) by [@leechienpang](https://github.com/leechienpang)
- Cmd CEPH variable not expanded #141 ([#138](https://github.com/bigstack-oss/cubecos/pull/138)) by [@leechienpang](https://github.com/leechienpang)
- Rolling upgrade VMs in error status during live-migration #71 ([#151](https://github.com/bigstack-oss/cubecos/pull/151)) by [@leechienpang](https://github.com/leechienpang)

#### Mongodb

- Set the endpoint ip to mgmt_ip for mongosh in config_mongodb ([4e697af](https://github.com/bigstack-oss/cubecos/commit/4e697af2c0394dcdfbf77abe9da733020ed2505d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Restart mongodb after authentication is set up ([e5082e6](https://github.com/bigstack-oss/cubecos/commit/e5082e62705a89ae37556d81b4643fba857cd6bf)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Rearrange the commit flow to make mongodb service and admin user setup more robust ([2f430a6](https://github.com/bigstack-oss/cubecos/commit/2f430a6974f71d054a8898cd750757619fb52aab)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Pass stdout through pipes ([1c8ebfa](https://github.com/bigstack-oss/cubecos/commit/1c8ebfadf721155b5444a7d14efa36d035e6812e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use hostname instead of mgmt ip to initiate the replica set & set role clusterAdmin on user admin to access rs.status() ([09da2aa](https://github.com/bigstack-oss/cubecos/commit/09da2aa0201ac35ecf2ed81a161dfdcadb945ba9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Only set replica set settings on the master node & perform role operations on user admin through replica set mongodb uri ([06296ca](https://github.com/bigstack-oss/cubecos/commit/06296ca7f5b1f69031381f3c62491ed0fa2498f3)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Do not recreate the replica set & allow non-master nodes to use the old admin password to access mongodb ([f992f69](https://github.com/bigstack-oss/cubecos/commit/f992f69a222793d5753477ce3574eb9bf9a46063)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Migrate the mongodb rs created marker ([b848117](https://github.com/bigstack-oss/cubecos/commit/b848117500fa317f26b4f7754bb840a1d8155cd0)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Separate replica set init flow and update password flow ([fed2f35](https://github.com/bigstack-oss/cubecos/commit/fed2f3566ebc5dc3befb92011e9ccafc9bf33e8a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Repair mongodb keyfile ownership ([#125](https://github.com/bigstack-oss/cubecos/pull/125)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Set role readWriteAnyDatabase on user admin ([5209006](https://github.com/bigstack-oss/cubecos/commit/52090060ecd8a5c92645db19e6b090f5a2269d45)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Nginx

- Set the correct module dependency ([e7ec55e](https://github.com/bigstack-oss/cubecos/commit/e7ec55e5f53465e43e05b09e240974e4e2395c69)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Include the full path for path rewrite in skyline-console nginx proxy to cube-cos-api ([#77](https://github.com/bigstack-oss/cubecos/pull/77)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Openstack

- Yoga branch not found ([e02dd24](https://github.com/bigstack-oss/cubecos/commit/e02dd244fa320e6c1a25baa06a21923e4ced50f6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Pacemaker

- Wait longer for remote compute node pcsd to start ([2319e84](https://github.com/bigstack-oss/cubecos/commit/2319e84aa6349994e5c0aadd8002e8a226f768cb)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Rancher

- Terraform tried to use the changed old password to login to rancher but failed ([072397b](https://github.com/bigstack-oss/cubecos/commit/072397b270d94daeb709916a1df3c97da749906d)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Migrate rancher node driver to the new URL ([7c07d01](https://github.com/bigstack-oss/cubecos/commit/7c07d01b555d356a1f6cc73d88510a55189fff47)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Terraform

- Set etcd tag to v3.5.18 after etcd latest tag not found ([75bca53](https://github.com/bigstack-oss/cubecos/commit/75bca53ceb9e5a9c1cf9fbfeb6f68a47c9a5f722)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use flock to create a file lock for terraform actions ([b8f24f5](https://github.com/bigstack-oss/cubecos/commit/b8f24f53cd47d5c4c607847093b5109a91aab42f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use the absolute path to call terraform-action.sh and terraform-cube.sh ([8858492](https://github.com/bigstack-oss/cubecos/commit/8858492494b503f647b5abd1a78ba0b652a80402)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Migrate terraform states to remove and sync lmi configs on keycloak ([a1b13f8](https://github.com/bigstack-oss/cubecos/commit/a1b13f860fe8f703005f434c5bcb427e907297ac)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Ui

- Set the correct path to serve ui files ([6709f1c](https://github.com/bigstack-oss/cubecos/commit/6709f1c455924a9068dcb7c7179b2b46665836d4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Fall back to the index page when serving SPA paths ([63018be](https://github.com/bigstack-oss/cubecos/commit/63018be99d59722adff934792ddc5a19b67f127f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Yml

- Free the yml tree root before reassigning a tree to it ([08d9b07](https://github.com/bigstack-oss/cubecos/commit/08d9b077f91a8e38affdc2dd3a0c0128238155bc)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use c style null check ([86450db](https://github.com/bigstack-oss/cubecos/commit/86450dbcd01398fb55a08687aafb24d99e57b94e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Avoid dereferencing a NULL pointer and set the pointer to NULL after freeing its data ([1af0d00](https://github.com/bigstack-oss/cubecos/commit/1af0d007b41283e02830cf3c20c2412a393ded0f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Restrict null checks to GNode pointers ([7fb74a5](https://github.com/bigstack-oss/cubecos/commit/7fb74a508cd3c7a9759c234608085b068ab68d8a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### <!-- 3 -->:boom: Refactor

#### Alert

- Use MakeTempDir and RemoveTempFiles to manage temp directories ([099a2ad](https://github.com/bigstack-oss/cubecos/commit/099a2ad52207fc417db7fa9bdb17e41b0eb504fa)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Api

- No longer manage configurations for api ([#67](https://github.com/bigstack-oss/cubecos/pull/67)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Banner

- Check if we can change color ([6c8cc8d](https://github.com/bigstack-oss/cubecos/commit/6c8cc8d197a60d1e68675501d617796b50fab99e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Diagnostics

- Use role admin to mitigate skyline-console project listing authorization behaviors ([7dde2e0](https://github.com/bigstack-oss/cubecos/commit/7dde2e093560c8eeb02300bb88165c621ac817aa)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Haproxy

- Remove the duplicated string ([9253f56](https://github.com/bigstack-oss/cubecos/commit/9253f568fc9c303960ae06c9e33f00cf30b142d1)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_cli

- Avoid implicit type conversion of cli function return values ([862313b](https://github.com/bigstack-oss/cubecos/commit/862313bd637ee8dd0f83c70496a368d378af69d2)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Perform null checks ([65f626f](https://github.com/bigstack-oss/cubecos/commit/65f626f76e9d58be1c6a4adbd91db1144c2c98ee)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Hex_sdk

- Use the shared variable to reference /etc/settings.* ([d8df1b1](https://github.com/bigstack-oss/cubecos/commit/d8df1b1b4c691c2ccd0f6055d72cbf39cced14c9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use the global env TERRAFORM_CUBE to refer terraform-cube.sh ([a9b0e72](https://github.com/bigstack-oss/cubecos/commit/a9b0e72782b870d0a5388b2d82fdd68242d5f089)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use string concatenation instead of env passing for yq arguments ([f9aec5d](https://github.com/bigstack-oss/cubecos/commit/f9aec5d385a531c9e6fe75cd260a3c812e313369)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Make

- Move cubecos envs back to cubecos ([09e3771](https://github.com/bigstack-oss/cubecos/commit/09e3771275c26191d6a5bd491360c80e74e001f8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Move cubecos shared build envs to project.mk ([8be72be](https://github.com/bigstack-oss/cubecos/commit/8be72bec345093fa2211c28b001c1cc3aab7f3d8)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop the duplicated build clean target RPMBUILD_DIR ([b05a5ab](https://github.com/bigstack-oss/cubecos/commit/b05a5abbf8cc7474eb7b75b1c239e81641d11000)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Separate rpmbuild directory used by neutron, api, ui, and login components ([053abd7](https://github.com/bigstack-oss/cubecos/commit/053abd7556f8ac3815e91be18fa118fde205b401)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Remove redundant cleans ([1979070](https://github.com/bigstack-oss/cubecos/commit/19790704b7c28a175c9f7b801f7727d1791ffb83)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make nvm disabling more robust ([f7c2fac](https://github.com/bigstack-oss/cubecos/commit/f7c2fac46ec2a467fe792c718adf5dabc22d3752)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make rpm source tarball creation more robust ([11be169](https://github.com/bigstack-oss/cubecos/commit/11be169664ab51e5124152e423edcfaecf476380)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Drop the duplicated build target .push-img in ./core/keycloak/Makefile ([a8437fa](https://github.com/bigstack-oss/cubecos/commit/a8437fa0aeec08910043df3bb1836c243806e4d0)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Mongodb

- Use const variables to set user and group for mongodb keyfile ([812e2d1](https://github.com/bigstack-oss/cubecos/commit/812e2d15f367c8f1fc2fdf40e8a553a7b1d3062a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Separate user admin functions and catch function return status ([c59a4f4](https://github.com/bigstack-oss/cubecos/commit/c59a4f4085d7423fbce50e0405c5e2e64d02be30)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Nginx

- Add back ip change check to config_skyline ([e1b4a55](https://github.com/bigstack-oss/cubecos/commit/e1b4a55e89c70e8678ac3c05db197d12cfaa776e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Remove redundant checks ([c24f471](https://github.com/bigstack-oss/cubecos/commit/c24f47138dd48c305f9d1220cf747ec2d46a5d86)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Openstack

- Move yoga tag into installpip ([0289d40](https://github.com/bigstack-oss/cubecos/commit/0289d400e829ffc72741812c352f506222ff0c8e)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### <!-- 4 -->:memo: Documentation

#### Bash

- Escape underscores ([6bb85f1](https://github.com/bigstack-oss/cubecos/commit/6bb85f1319fbde83e8838bab8a4058b39db2ce70)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Miscellaneous

- Create security.md ([17fd2a1](https://github.com/bigstack-oss/cubecos/commit/17fd2a1006ebe96bc5618c83ee1088cbc4c8d9f1)) by [@bigstack-brian-su](https://github.com/bigstack-brian-su)
- Create code of conduct ([d814cc3](https://github.com/bigstack-oss/cubecos/commit/d814cc3e72bba7c069444b5b5ca692f2e081691f)) by [@bigstack-brian-su](https://github.com/bigstack-brian-su)
- Update readme ([6b433bf](https://github.com/bigstack-oss/cubecos/commit/6b433bf45979d367010e88db61ea92edf007dab0)) by [@bigstack-brian-su](https://github.com/bigstack-brian-su)
- Update readme, created CONTRIBUTING.md ([#75](https://github.com/bigstack-oss/cubecos/pull/75)) by [@bigstack-brian-su](https://github.com/bigstack-brian-su)
- Update readme ([34351b1](https://github.com/bigstack-oss/cubecos/commit/34351b130e9ea4511a44937b6fc20e340ba1e060)) by [@bigstack-brian-su](https://github.com/bigstack-brian-su)
- Update readme for banner and information ([#121](https://github.com/bigstack-oss/cubecos/pull/121)) by [@bigstack-brian-su](https://github.com/bigstack-brian-su)

### Miscellaneous Tasks

#### Alert

- Update the comment of the alert_put_trigger input format ([#51](https://github.com/bigstack-oss/cubecos/pull/51)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Api

- Add the yaml config in rc builds ([1fd925b](https://github.com/bigstack-oss/cubecos/commit/1fd925b17b2929ed9330f15926e52c944efad756)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Appfw

- Untrack core/appfw/appfw.tgz ([a38f135](https://github.com/bigstack-oss/cubecos/commit/a38f135d8b4c5e916a59f13b08455a765e72f192)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Untar appfw.tgz ([ea91744](https://github.com/bigstack-oss/cubecos/commit/ea91744f46451d97cb0ee7491e1e0187e36b43ae)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cubecos

- Update names to CubeCOS ([#103](https://github.com/bigstack-oss/cubecos/pull/103)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Cubectl

- Remove the comment of the resolved issue ([e0adc1f](https://github.com/bigstack-oss/cubecos/commit/e0adc1fb6000ca244005ff1f5746266dc181cb35)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Deps

- Bump ossf/scorecard-action from 2.4.1 to 2.4.2 ([#146](https://github.com/bigstack-oss/cubecos/pull/146)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Image

- Pull the fix for image import as a cinder volume (#5) ([#5](https://github.com/bigstack-oss/cubecos/pull/5)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Keycloak

- Remove not needed fix ([a33927f](https://github.com/bigstack-oss/cubecos/commit/a33927f4a628953bb75f8037764a0eef32905bc3)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### License

- Change sla to support plan ([4706979](https://github.com/bigstack-oss/cubecos/commit/4706979abd9807defb17ad1d826e5f43b1ba12b5)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Login

- Pull login greeting messages on Keycloak login page from the old repo (#6) ([#6](https://github.com/bigstack-oss/cubecos/pull/6)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Make

- Make comments quiet ([b09df11](https://github.com/bigstack-oss/cubecos/commit/b09df11ba46667faa149adf0285589f5a83eb039)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Remove the feature branch in api, ui, and keycloak git clone ([1e42701](https://github.com/bigstack-oss/cubecos/commit/1e427012e515066d6c59d951153057d35ac9f69f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Make nvm use quiet ([1fe548f](https://github.com/bigstack-oss/cubecos/commit/1fe548fd465b7e080ace1f59e81f549fb4f2066a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Use gen instead of build and arc for the make concise output ([e3f5a06](https://github.com/bigstack-oss/cubecos/commit/e3f5a06056531257f9eb02b9441a4fc7eef7d2ad)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Merge

- Add ci for fast forward merge ([fedd0a8](https://github.com/bigstack-oss/cubecos/commit/fedd0a8da2ba8c8144adb735ba64b209bd9f3f1c)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Mongodb

- Pull mongodb service set up from the old repo ([#4](https://github.com/bigstack-oss/cubecos/pull/4)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Release

- Update pull target tag of upstream repos to v3.0.0-rc2 ([#135](https://github.com/bigstack-oss/cubecos/pull/135)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Update pull target tag of upstream repos to v3.0.0-rc3 ([c2fe598](https://github.com/bigstack-oss/cubecos/commit/c2fe5989310bd0592389efb6467d31ecbf06f642)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- V3.0.0-rc4 ([#154](https://github.com/bigstack-oss/cubecos/pull/154)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Template

- Add issue and pr templates ([#15](https://github.com/bigstack-oss/cubecos/pull/15)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Terraform

- Format terraform files ([812dbdc](https://github.com/bigstack-oss/cubecos/commit/812dbdc17d9d3780a1666246eed4af4dacd70cc9)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### New

### Revert

#### Influxdb

- Only expose influxdb on mgmt ip and vip ([6b4bcde](https://github.com/bigstack-oss/cubecos/commit/6b4bcde3e750f7aa633a8253ae0f99840377665f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Lmi

- Keep lmi handlings in hex ([926963b](https://github.com/bigstack-oss/cubecos/commit/926963b31cb1a277b92222662b05f5c015c3804a)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Make

- Revert - resolve the hidden docker registry make dependency ([5b22c4a](https://github.com/bigstack-oss/cubecos/commit/5b22c4a2769b5a19724355193686abc58a066ff0)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)
- Try another mirror for centos stream 9 highavailability ([5e784aa](https://github.com/bigstack-oss/cubecos/commit/5e784aa6a783a2036b3218aa5deaf7185d40898f)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

#### Rancher

- No need to migrate node driver cube to the new url ([ed894f4](https://github.com/bigstack-oss/cubecos/commit/ed894f43e12d1afdaee72ba5a220f38c81e916fc)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)

### Test

#### Make

- Use the feature branch in api, ui, and keycloak git clone ([2e8b72b](https://github.com/bigstack-oss/cubecos/commit/2e8b72b1d692703c76bbafc2d17dd753229f5978)) by [@Eandalf-Bigstack](https://github.com/Eandalf-Bigstack)


