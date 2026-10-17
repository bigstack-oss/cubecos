# -*- encoding: utf-8 -*-
# Copyright (c) 2017  ZTE Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

from oslo_config import cfg
from oslo_log import log

from watcher._i18n import _
from watcher.common import cinder_helper
from watcher.decision_engine.strategy.strategies import base

LOG = log.getLogger(__name__)


class StorageCapacityBalance(base.WorkloadStabilizationBaseStrategy):
    """Storage capacity balance using cinder volume migration

    *Description*

    This strategy migrates volumes based on the workload of the
    cinder pools.
    It makes decision to migrate a volume whenever a pool's used
    utilization % is higher than the specified threshold. The volume
    to be moved should make the pool close to average workload of all
    cinder pools.

    *Requirements*

    * You must have at least 2 cinder volume pools to run
      this strategy.

    *Limitations*

    * Volume migration depends on the storage device.
      It may take a long time.

    *Spec URL*

    http://specs.openstack.org/openstack/watcher-specs/specs/queens/implemented/storage-capacity-balance.html
    """

    def __init__(self, config, osc=None):
        """VolumeMigrate using cinder volume migration

        :param config: A mapping containing the configuration of this strategy
        :type config: :py:class:`~.Struct` instance
        :param osc: :py:class:`~.OpenStackClients` instance
        """
        super(StorageCapacityBalance, self).__init__(config, osc)
        self._cinder = None
        self.volume_threshold = 80.0
        self.pool_type_cache = dict()
        self.source_pools = []
        self.dest_pools = []

    @property
    def cinder(self):
        if not self._cinder:
            self._cinder = cinder_helper.CinderHelper(osc=self.osc)
        return self._cinder

    @classmethod
    def get_name(cls):
        return "storage_capacity_balance"

    @classmethod
    def get_display_name(cls):
        return _("Storage Capacity Balance Strategy")

    @classmethod
    def get_translatable_display_name(cls):
        return "Storage Capacity Balance Strategy"

    @classmethod
    def get_schema(cls):
        # Mandatory default setting for each element
        return {
            "properties": {
                "volume_threshold": {
                    "description": "volume threshold for capacity balance",
                    "type": "number",
                    "default": 80.0
                },
            },
        }

    @classmethod
    def get_config_opts(cls):
        return super(StorageCapacityBalance, cls).get_config_opts() + [
            cfg.ListOpt(
                "ex_pools",
                help="exclude pools",
                default=['local_vstorage']),
        ]

    def get_pools(self, cinder):
        """Get all volume pools excepting ex_pools.

        :param cinder: cinder client
        :return: volume pools
        """
        ex_pools = self.config.ex_pools
        pools = cinder.get_storage_pool_list()
        filtered_pools = [p for p in pools
                          if p.pool_name not in ex_pools]
        return filtered_pools

    def get_volumes(self, cinder):
        """Get all volumes with status in available or in-use and no snapshot.

        :param cinder: cinder client
        :return: all volumes
        """
        all_volumes = cinder.get_volume_list()
        valid_status = ['in-use', 'available']

        volume_snapshots = cinder.get_volume_snapshots_list()
        snapshot_volume_ids = []
        for snapshot in volume_snapshots:
            snapshot_volume_ids.append(snapshot.volume_id)

        nosnap_volumes = list(filter(lambda v: v.id not in snapshot_volume_ids,
                              all_volumes))
        LOG.info("volumes in snap: %s", snapshot_volume_ids)
        status_volumes = list(
            filter(lambda v: v.status in valid_status, nosnap_volumes))
        valid_volumes = [v for v in status_volumes
                         if getattr(v, 'migration_status') == 'success' or
                         getattr(v, 'migration_status') is None]
        LOG.info("valid volumes: %s", valid_volumes)

        return valid_volumes

    def group_pools(self, pools, threshold):
        """group volume pools by threshold.

        :param pools: all volume pools
        :param threshold: volume threshold
        :return: under and over threshold pools
        """
        under_pools = list(
            filter(lambda p: float(p.total_capacity_gb) -
                   float(p.free_capacity_gb) <
                   float(p.total_capacity_gb) * threshold, pools))

        over_pools = list(
            filter(lambda p: float(p.total_capacity_gb) -
                   float(p.free_capacity_gb) >=
                   float(p.total_capacity_gb) * threshold, pools))

        return over_pools, under_pools

    def get_volume_type_by_name(self, cinder, backendname):
        # return list of pool type
        if backendname in self.pool_type_cache.keys():
            return self.pool_type_cache.get(backendname)

        volume_type_list = cinder.get_volume_type_list()
        volume_type = list(filter(
            lambda volume_type:
                volume_type.extra_specs.get(
                    'volume_backend_name') == backendname, volume_type_list))
        if volume_type:
            self.pool_type_cache[backendname] = volume_type
            return self.pool_type_cache.get(backendname)
        else:
            return []

    def migrate_fit(self, volume, threshold):
        target_pool_name = None
        if volume.volume_type:
            LOG.info("volume %s type %s", volume.id, volume.volume_type)
            return target_pool_name
        self.dest_pools.sort(
            key=lambda p: float(p.free_capacity_gb) /
            float(p.total_capacity_gb))
        for pool in reversed(self.dest_pools):
            total_cap = float(pool.total_capacity_gb)
            allocated = float(pool.allocated_capacity_gb)
            ratio = pool.max_over_subscription_ratio
            if total_cap * ratio < allocated + float(volume.size):
                LOG.info("pool %s allocated over", pool.name)
                continue
            free_cap = float(pool.free_capacity_gb) - float(volume.size)
            if free_cap > (1 - threshold) * total_cap:
                target_pool_name = pool.name
                index = self.dest_pools.index(pool)
                setattr(self.dest_pools[index], 'free_capacity_gb',
                        str(free_cap))
                LOG.info("volume: get pool %s for vol %s", target_pool_name,
                         volume.name)
                break
        return target_pool_name

    def check_pool_type(self, volume, dest_pool):
        target_type = None
        src_extra_specs = {}
        # check type feature
        if not volume.volume_type:
            return target_type
        volume_type_list = self.cinder.get_volume_type_list()
        volume_type = list(filter(
            lambda volume_type:
                volume_type.name == volume.volume_type, volume_type_list))
        if volume_type:
            src_extra_specs = volume_type[0].extra_specs
            src_extra_specs.pop('volume_backend_name', None)

        backendname = getattr(dest_pool, 'volume_backend_name')
        dst_pool_type = self.get_volume_type_by_name(self.cinder, backendname)

        for src_key in src_extra_specs.keys():
            dst_pool_type = [pt for pt in dst_pool_type
                             if pt.extra_specs.get(src_key) ==
                             src_extra_specs.get(src_key)]
        if dst_pool_type:
            if volume.volume_type:
                if dst_pool_type[0].name != volume.volume_type:
                    target_type = dst_pool_type[0].name
            else:
                target_type = dst_pool_type[0].name
        return target_type

    def retype_fit(self, volume, threshold):
        target_type = None
        self.dest_pools.sort(
            key=lambda p: float(p.free_capacity_gb) /
            float(p.total_capacity_gb))
        for pool in reversed(self.dest_pools):
            backendname = getattr(pool, 'volume_backend_name')
            pool_type = self.get_volume_type_by_name(self.cinder, backendname)
            LOG.info("volume: pool %s, type %s", pool.name, pool_type)
            if pool_type is None:
                continue
            total_cap = float(pool.total_capacity_gb)
            allocated = float(pool.allocated_capacity_gb)
            ratio = pool.max_over_subscription_ratio
            if total_cap * ratio < allocated + float(volume.size):
                LOG.info("pool %s allocated over", pool.name)
                continue
            free_cap = float(pool.free_capacity_gb) - float(volume.size)
            if free_cap > (1 - threshold) * total_cap:
                target_type = self.check_pool_type(volume, pool)
                if target_type is None:
                    continue
                index = self.dest_pools.index(pool)
                setattr(self.dest_pools[index], 'free_capacity_gb',
                        str(free_cap))
                LOG.info("volume: get type %s for vol %s", target_type,
                         volume.name)
                break
        return target_type

    def get_actions(self, pool, volumes, threshold):
        """get volume, pool key-value action

        return: retype, migrate dict
        """
        retype_dicts = dict()
        migrate_dicts = dict()
        total_cap = float(pool.total_capacity_gb)
        used_cap = float(pool.total_capacity_gb) - float(pool.free_capacity_gb)
        seek_flag = True

        volumes_in_pool = list(
            filter(lambda v: getattr(v, 'os-vol-host-attr:host') == pool.name,
                   volumes))
        LOG.info("volumes in pool: %s", str(volumes_in_pool))
        if not volumes_in_pool:
            return retype_dicts, migrate_dicts
        ava_volumes = list(filter(lambda v: v.status == 'available',
                           volumes_in_pool))
        ava_volumes.sort(key=lambda v: float(v.size))
        LOG.info("available volumes in pool: %s ", str(ava_volumes))
        for vol in ava_volumes:
            vol_flag = False
            migrate_pool = self.migrate_fit(vol, threshold)
            if migrate_pool:
                migrate_dicts[vol.id] = migrate_pool
                vol_flag = True
            else:
                target_type = self.retype_fit(vol, threshold)
                if target_type:
                    retype_dicts[vol.id] = target_type
                    vol_flag = True
            if vol_flag:
                used_cap -= float(vol.size)
                if used_cap < threshold * total_cap:
                    seek_flag = False
                    break
        if seek_flag:
            noboot_volumes = list(
                filter(lambda v: v.bootable.lower() == 'false' and
                       v.status == 'in-use', volumes_in_pool))
            noboot_volumes.sort(key=lambda v: float(v.size))
            LOG.info("noboot volumes: %s ", str(noboot_volumes))
            for vol in noboot_volumes:
                vol_flag = False
                migrate_pool = self.migrate_fit(vol, threshold)
                if migrate_pool:
                    migrate_dicts[vol.id] = migrate_pool
                    vol_flag = True
                else:
                    target_type = self.retype_fit(vol, threshold)
                    if target_type:
                        retype_dicts[vol.id] = target_type
                        vol_flag = True
                if vol_flag:
                    used_cap -= float(vol.size)
                    if used_cap < threshold * total_cap:
                        seek_flag = False
                        break

        if seek_flag:
            boot_volumes = list(
                filter(lambda v: v.bootable.lower() == 'true' and
                       v.status == 'in-use', volumes_in_pool)
            )
            boot_volumes.sort(key=lambda v: float(v.size))
            LOG.info("boot volumes: %s ", str(boot_volumes))
            for vol in boot_volumes:
                vol_flag = False
                migrate_pool = self.migrate_fit(vol, threshold)
                if migrate_pool:
                    migrate_dicts[vol.id] = migrate_pool
                    vol_flag = True
                else:
                    target_type = self.retype_fit(vol, threshold)
                    if target_type:
                        retype_dicts[vol.id] = target_type
                        vol_flag = True
                if vol_flag:
                    used_cap -= float(vol.size)
                    if used_cap < threshold * total_cap:
                        seek_flag = False
                        break
        return retype_dicts, migrate_dicts

    def pre_execute(self):
        LOG.info("Initializing " + self.get_display_name() + " Strategy")
        self.volume_threshold = self.input_parameters.volume_threshold

    def do_execute(self, audit=None):
        """Strategy execution phase

        This phase is where you should put the main logic of your strategy.
        """
        all_pools = self.get_pools(self.cinder)
        all_volumes = self.get_volumes(self.cinder)
        threshold = float(self.volume_threshold) / 100
        self.source_pools, self.dest_pools = self.group_pools(
            all_pools, threshold)
        LOG.info(" source pools: %s dest pools:%s",
                 self.source_pools, self.dest_pools)
        if not self.source_pools:
            LOG.info("No pools require optimization")
            return

        if not self.dest_pools:
            LOG.info("No enough pools for optimization")
            return
        for source_pool in self.source_pools:
            retype_actions, migrate_actions = self.get_actions(
                source_pool, all_volumes, threshold)
            for vol_id, pool_type in retype_actions.items():
                vol = [v for v in all_volumes if v.id == vol_id]
                parameters = {'migration_type': 'retype',
                              'destination_type': pool_type,
                              'resource_name': vol[0].name}
                self.solution.add_action(action_type='volume_migrate',
                                         resource_id=vol_id,
                                         input_parameters=parameters)
            for vol_id, pool_name in migrate_actions.items():
                vol = [v for v in all_volumes if v.id == vol_id]
                parameters = {'migration_type': 'migrate',
                              'destination_node': pool_name,
                              'resource_name': vol[0].name}
                self.solution.add_action(action_type='volume_migrate',
                                         resource_id=vol_id,
                                         input_parameters=parameters)

    def post_execute(self):
        """Post-execution phase

        """
        self.solution.set_efficacy_indicators(
            instance_migrations_count=0,
            instances_count=0,
        )
