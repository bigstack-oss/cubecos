"""epoxy_patch storage_capacity_balance.py.patch: get_pools() filters on the
pool part of the cinder pool name when the driver reports no pool_name
(Ceph RBD), instead of raising AttributeError on every audit, and
max_over_subscription_ratio, a string from cinder, is coerced to float,
and the strategy is planned by the weight planner, which has a weight for
volume_migrate.

    python3.11 -m unittest discover -s core/watcher/tests -v
"""
import importlib.machinery
import importlib.util
import os
import subprocess
import sys
import tempfile
import types
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'epoxy_patch', 'watcher', 'decision_engine',
                   'strategy', 'strategies', 'storage_capacity_balance.py')


def load(src, name):
    def mod(n, **attrs):
        m = types.ModuleType(n)
        m.__dict__.update(attrs)
        return m

    class _Log(object):
        def __getattr__(self, name):
            return lambda *a, **k: None

    class Base(object):
        # as upstream WorkloadStabilizationBaseStrategy
        def __init__(self, config, osc=None):
            self._planner = 'workload_stabilization'

        @property
        def planner(self):
            return self._planner

        @classmethod
        def get_config_opts(cls):
            return []

    stubs = {
        'oslo_config': mod('oslo_config', cfg=mod(
            'oslo_config.cfg', ListOpt=lambda *a, **k: None)),
        'oslo_log': mod('oslo_log', log=mod('oslo_log.log',
                                            getLogger=lambda n: _Log())),
        'watcher': mod('watcher'),
        'watcher._i18n': mod('watcher._i18n', _=lambda s: s),
        'watcher.common': mod('watcher.common',
                              cinder_helper=mod('watcher.common.cinder_helper')),
        'watcher.decision_engine': mod('watcher.decision_engine'),
        'watcher.decision_engine.strategy': mod(
            'watcher.decision_engine.strategy'),
        'watcher.decision_engine.strategy.strategies': mod(
            'watcher.decision_engine.strategy.strategies',
            base=mod('b', WorkloadStabilizationBaseStrategy=Base)),
    }
    saved = {k: sys.modules.get(k) for k in stubs}
    sys.modules.update(stubs)
    try:
        spec = importlib.util.spec_from_file_location(
            name, src, loader=importlib.machinery.SourceFileLoader(name, src))
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        return m
    finally:
        for k, v in saved.items():
            if v is None:
                sys.modules.pop(k, None)
            else:
                sys.modules[k] = v


class Pool(object):
    def __init__(self, name, **caps):
        self.name = name
        self.__dict__.update(caps)


class Cinder(object):
    def __init__(self, pools):
        self.pools = pools

    def get_storage_pool_list(self):
        return self.pools


def strategy(mod_, ex_pools):
    s = object.__new__(mod_.StorageCapacityBalance)
    s.config = types.SimpleNamespace(ex_pools=ex_pools)
    return s


CEPH = Pool('cube@ceph#ceph', volume_backend_name='ceph', vendor_name='Ceph')
LVM = Pool('cube@lvm#vg0', pool_name='vg0')
VSTOR = Pool('cube@vz#local_vstorage')


class TestGetPools(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        tgt = os.path.join(cls.tmp.name, 'storage_capacity_balance.py')
        with open(SRC + '.orig') as f, open(tgt, 'w') as o:
            o.write(f.read())
        subprocess.run(['patch', '--forward', '--no-backup-if-mismatch', '-r',
                        '-', tgt, '-i', SRC + '.patch'], check=True,
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
        cls.mod = load(tgt, 'scb_patched')
        cls.orig = load(SRC + '.orig', 'scb_orig')

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_pristine_raises_on_ceph_pool(self):
        with self.assertRaises(AttributeError):
            strategy(self.orig, ['local_vstorage']).get_pools(Cinder([CEPH]))

    def test_ceph_pool_without_pool_name_is_kept(self):
        got = strategy(self.mod, ['local_vstorage']).get_pools(
            Cinder([CEPH, LVM]))
        self.assertEqual(got, [CEPH, LVM])

    def test_exclusion_uses_name_suffix(self):
        s = strategy(self.mod, ['local_vstorage', 'ceph'])
        self.assertEqual(s.get_pools(Cinder([CEPH, LVM, VSTOR])), [LVM])

    def test_pool_name_still_wins(self):
        s = strategy(self.mod, ['vg0'])
        self.assertEqual(s.get_pools(Cinder([CEPH, LVM])), [CEPH])


class Vol(object):
    def __init__(self, size):
        self.id = self.name = 'v%d' % size
        self.size = size
        self.volume_type = None


def ceph_pool(ratio):
    # cinder volume backend pool list --long output
    p = Pool('cube@ceph#ceph', total_capacity_gb=752.26,
             free_capacity_gb=745.55, allocated_capacity_gb=10,
             volume_backend_name='ceph')
    if ratio is not None:
        p.max_over_subscription_ratio = ratio
    return p


class TestOverSubscriptionRatio(unittest.TestCase):
    setUpClass = classmethod(TestGetPools.setUpClass.__func__)
    tearDownClass = classmethod(TestGetPools.tearDownClass.__func__)

    def _fit(self, mod_, ratio, size=10):
        s = strategy(mod_, [])
        s.dest_pools = [ceph_pool(ratio)]
        return s.migrate_fit(Vol(size), 0.5)

    def test_pristine_raises_on_string_ratio(self):
        with self.assertRaises(TypeError):
            self._fit(self.orig, '20.0')

    def test_string_ratio_is_coerced(self):
        self.assertEqual(self._fit(self.mod, '20.0'), 'cube@ceph#ceph')

    def test_string_ratio_still_limits(self):
        # 752 * 1.0 < 10 + 800
        self.assertIsNone(self._fit(self.mod, '1.0', size=800))

    def test_auto_or_missing_ratio_reads_as_one(self):
        for ratio in ('auto', None):
            self.assertEqual(self._fit(self.mod, ratio), 'cube@ceph#ceph')
            self.assertIsNone(self._fit(self.mod, ratio, size=800))

    def test_retype_fit_coerces_string_ratio(self):
        s = strategy(self.mod, [])
        s.dest_pools = [ceph_pool('20.0')]
        s.get_volume_type_by_name = lambda c, n: ['ceph']
        s.check_pool_type = lambda v, p: 'ceph-type'
        s._cinder = object()
        self.assertEqual(s.retype_fit(Vol(10), 0.5), 'ceph-type')


# action weights of the two 14.1.2 planners: weight.py WeightPlanner
# action_weights, workload_stabilization.py weights_dict
PLANNER_WEIGHTS = {
    'weight': {'nop': 70, 'volume_migrate': 60,
               'change_nova_service_state': 50, 'sleep': 40, 'migrate': 30,
               'resize': 20, 'turn_host_to_acpi_s3_state': 10,
               'change_node_power_state': 9},
    'workload_stabilization': {'turn_host_to_acpi_s3_state': 0, 'resize': 1,
                               'migrate': 2, 'sleep': 3,
                               'change_nova_service_state': 4, 'nop': 5},
}


class Solution(object):
    def __init__(self):
        self.actions = []

    def add_action(self, action_type, resource_id, input_parameters):
        self.actions.append(dict(action_type=action_type,
                                 resource_id=resource_id,
                                 input_parameters=input_parameters))


class TestPlanner(unittest.TestCase):
    setUpClass = classmethod(TestGetPools.setUpClass.__func__)
    tearDownClass = classmethod(TestGetPools.tearDownClass.__func__)

    def _plan(self, mod_):
        s = mod_.StorageCapacityBalance(types.SimpleNamespace(ex_pools=[]))
        s.solution = Solution()
        s._cinder = object()
        s.volume_threshold = 80.0
        vols = [Vol(10), Vol(20)]
        s.get_pools = lambda c: []
        s.get_volumes = lambda c: vols
        s.group_pools = lambda p, t: (['src'], ['dst'])
        s.get_actions = lambda p, v, t: ({'v10': 'ceph-type'},
                                         {'v20': 'cube@ceph#ceph'})
        s.do_execute()
        types_ = [a['input_parameters']['migration_type']
                  for a in s.solution.actions]
        self.assertEqual(['retype', 'migrate'], types_)
        # what planner.schedule() does with each action
        weights = PLANNER_WEIGHTS[s.planner]
        return [weights[a['action_type']] for a in s.solution.actions]

    def test_pristine_planner_raises_on_volume_actions(self):
        with self.assertRaises(KeyError):
            self._plan(self.orig)

    def test_weight_planner_schedules_retype_and_migrate(self):
        self.assertEqual([60, 60], self._plan(self.mod))


if __name__ == '__main__':
    unittest.main()
