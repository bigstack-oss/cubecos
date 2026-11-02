# Unit tests for the cube allocation_balance strategy.
#
# Outside core/watcher/epoxy_patch/ because watcher.mk installs everything in
# the patch dir verbatim onto the rootfs.
#
# Runs standalone (watcher is stubbed when not importable):
#   python3.11 -m unittest discover -s core/watcher/tests -v
# or against a node's epoxy venv with the real watcher base classes.

import importlib.util
import os
import sys
import types
import unittest

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir,
                   'epoxy_patch', 'watcher', 'decision_engine', 'strategy',
                   'strategies', 'allocation_balance.py')


def _stub_watcher():
    """Minimal stand-ins for the watcher modules the strategy imports."""
    def mod(name, **attrs):
        m = types.ModuleType(name)
        m.__dict__.update(attrs)
        sys.modules[name] = m
        return m

    class _Log(object):
        def __getattr__(self, name):
            return lambda *a, **k: None

    class WorkloadStabilizationBaseStrategy(object):
        def __init__(self, config, osc=None):
            self._compute_model = None

        @property
        def compute_model(self):
            return self._compute_model

    mod('oslo_log', log=mod('oslo_log.log', getLogger=lambda n: _Log()))
    mod('watcher')
    mod('watcher._i18n', _=lambda s: s)
    mod('watcher.decision_engine')
    mod('watcher.decision_engine.model')
    mod('watcher.decision_engine.model.element',
        InstanceState=types.SimpleNamespace(
            ACTIVE=types.SimpleNamespace(value='active')))
    mod('watcher.decision_engine.strategy')
    mod('watcher.decision_engine.strategy.strategies', base=mod(
        'watcher.decision_engine.strategy.strategies.base',
        WorkloadStabilizationBaseStrategy=WorkloadStabilizationBaseStrategy))


try:
    import watcher.decision_engine.strategy.strategies.base  # noqa: F401
except ImportError:
    _stub_watcher()

_spec = importlib.util.spec_from_file_location('allocation_balance', SRC)
allocation_balance = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(allocation_balance)


class FakeInstance(object):
    def __init__(self, uuid, state='active', exclude=False, memory=1024):
        self.uuid = uuid
        self.name = uuid
        self.vcpus = 1
        self.memory = memory
        self.state = state
        self.watcher_exclude = exclude


class FakeNode(object):
    def __init__(self, uuid, instances, vcpus=64, vcpu_reserved=0,
                 memory=65536, memory_mb_reserved=0, vcpu_ratio=1.0):
        self.uuid = uuid
        self.hostname = uuid
        self.vcpus = vcpus
        self.vcpu_reserved = vcpu_reserved
        self.vcpu_ratio = vcpu_ratio
        self.memory = memory
        self.memory_mb_reserved = memory_mb_reserved
        self.memory_ratio = 1.0
        self.instances = list(instances)

    # as watcher's ComputeNode
    @property
    def vcpu_capacity(self):
        return (self.vcpus - self.vcpu_reserved) * self.vcpu_ratio

    @property
    def memory_mb_capacity(self):
        return (self.memory - self.memory_mb_reserved) * self.memory_ratio


class FakeModel(object):
    stale = False

    def __init__(self, *nodes):
        self.nodes = nodes

    def get_all_compute_nodes(self):
        return dict((n.uuid, n) for n in self.nodes)

    def get_all_instances(self):
        return dict((i.uuid, i) for n in self.nodes for i in n.instances)

    def get_node_instances(self, node):
        return list(node.instances)

    # as watcher's ModelRoot: free is measured from capacity, not the total
    def get_node_used_resources(self, node):
        return {'vcpu': sum(i.vcpus for i in node.instances),
                'memory': sum(i.memory for i in node.instances)}

    def get_node_free_resources(self, node):
        used = self.get_node_used_resources(node)
        return {'vcpu': node.vcpu_capacity - used['vcpu'],
                'memory': node.memory_mb_capacity - used['memory']}

    def migrate_instance(self, inst, src, dest):
        src.instances.remove(inst)
        dest.instances.append(inst)
        return True


class Strategy(allocation_balance.AllocationBalance):
    def __init__(self, model, metric='instance'):
        # skip the base __init__: it wants config and clients
        self._compute_model = model
        self._metric = metric
        self.instance_migrations_count = 0
        self.moved = []
        self.dests = []

    def add_action_migrate(self, instance, migration_type, src, dest):
        self.moved.append(instance.uuid)
        self.dests.append(dest.uuid)


def _converged(packed_on):
    """cube45 (#2196): control nodes reserve more than computes."""
    def control(uuid, n):
        return FakeNode(uuid, [FakeInstance('%s-%d' % (uuid, i), exclude=True,
                                            memory=2048) for i in range(n)],
                        vcpus=48, vcpu_reserved=4, vcpu_ratio=16.0,
                        memory=128784, memory_mb_reserved=32768)

    def compute(uuid, memory):
        return FakeNode(uuid, [], vcpus=32, vcpu_ratio=16.0, memory=memory,
                        memory_mb_reserved=24576)

    nodes = [control('cc1', 1), control('cc2', 1), control('cc3', 0),
             compute('p4', 96536), compute('p5', 128792)]
    by_name = dict((n.uuid, n) for n in nodes)
    by_name['p5'].instances += [
        FakeInstance('p5-%d' % i, exclude=True, memory=2048) for i in range(2)]
    by_name[packed_on].instances += [
        FakeInstance('t%d' % i, memory=2048) for i in range(6)]
    return FakeModel(*nodes)


def _plan(src_instances):
    s = Strategy(FakeModel(FakeNode('src', src_instances), FakeNode('dst', [])))
    s.do_execute()
    return s.moved


class TestAllocationBalance(unittest.TestCase):
    def test_unbalanced_node_is_drained_to_the_spread(self):
        moved = _plan([FakeInstance('i%d' % n) for n in range(4)])
        self.assertEqual(2, len(moved))

    def test_excluded_instances_are_never_planned(self):
        # #2103: scope exclusions only flag the instance
        insts = [FakeInstance('i%d' % n, exclude=True) for n in range(4)]
        self.assertEqual([], _plan(insts))

    def test_only_unexcluded_instances_move(self):
        insts = [FakeInstance('x%d' % n, exclude=True) for n in range(4)]
        insts += [FakeInstance('i%d' % n) for n in range(2)]
        moved = _plan(insts)
        self.assertTrue(moved)
        self.assertTrue(all(u.startswith('i') for u in moved), moved)

    def test_stopped_instances_are_not_live_migrated(self):
        # #2104: only ACTIVE instances can be live migrated
        insts = [FakeInstance('i%d' % n, state='stopped') for n in range(4)]
        self.assertEqual([], _plan(insts))

    def test_only_active_instances_move(self):
        insts = [FakeInstance('s%d' % n, state='stopped') for n in range(2)]
        insts += [FakeInstance('e%d' % n, state='error') for n in range(2)]
        insts += [FakeInstance('i%d' % n) for n in range(2)]
        moved = _plan(insts)
        self.assertTrue(moved)
        self.assertTrue(all(u.startswith('i') for u in moved), moved)

    def test_metrics_rank_nodes_by_what_instances_hold(self):
        # #2196: reserved capacity and the allocation ratio are not load, so
        # every metric levels the six VMs to two per node, empty nodes included
        for packed_on, moves, empty in (('p4', 4, 'cc3'), ('p5', 6, 'p4')):
            for metric in ('instance', 'vcpu', 'memory'):
                s = Strategy(_converged(packed_on), metric)
                s.do_execute()
                self.assertEqual(moves, len(s.moved), (packed_on, metric))
                self.assertEqual(2, s.dests.count(empty), (packed_on, metric))
                for n in s.compute_model.nodes:
                    self.assertEqual(2, len(n.instances), (packed_on, metric))

    def test_busiest_node_with_nothing_to_move_is_skipped(self):
        # #2196: a node holding only excluded instances does not end the plan
        held = [FakeInstance('x%d' % n, exclude=True) for n in range(6)]
        held += [FakeInstance('s%d' % n, state='stopped') for n in range(2)]
        s = Strategy(FakeModel(
            FakeNode('held', held),
            FakeNode('src', [FakeInstance('i%d' % n) for n in range(4)]),
            FakeNode('dst', [])))
        s.do_execute()
        self.assertEqual(2, len(s.moved))
        self.assertEqual(['dst', 'dst'], s.dests)


if __name__ == '__main__':
    unittest.main()
