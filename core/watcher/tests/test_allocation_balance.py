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
    def __init__(self, uuid, state='active', exclude=False):
        self.uuid = uuid
        self.name = uuid
        self.vcpus = 1
        self.memory = 1024
        self.state = state
        self.watcher_exclude = exclude


class FakeNode(object):
    def __init__(self, uuid, instances):
        self.uuid = uuid
        self.hostname = uuid
        self.vcpus = 64
        self.memory = 65536
        self.instances = list(instances)


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

    def get_node_free_resources(self, node):
        return {'vcpu': node.vcpus - sum(i.vcpus for i in node.instances),
                'memory': node.memory - sum(i.memory for i in node.instances)}

    def migrate_instance(self, inst, src, dest):
        src.instances.remove(inst)
        dest.instances.append(inst)
        return True


class Strategy(allocation_balance.AllocationBalance):
    def __init__(self, model):
        # skip the base __init__: it wants config and clients
        self._compute_model = model
        self._metric = 'instance'
        self.instance_migrations_count = 0
        self.moved = []

    def add_action_migrate(self, instance, migration_type, src, dest):
        self.moved.append(instance.uuid)


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


if __name__ == '__main__':
    unittest.main()
