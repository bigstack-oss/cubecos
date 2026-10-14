"""epoxy_patch outlet_temp_control.py.patch: the migrate action names the
source and destination by host name, which nova accepts, not by node UUID.

    python3.11 -m unittest discover -s core/watcher/tests -v
"""
import os
import tempfile
import types
import unittest

from test_prometheus_hw_metrics import load, patched

HERE = os.path.dirname(os.path.abspath(__file__))
OTC = os.path.join(HERE, '..', 'epoxy_patch', 'watcher', 'decision_engine',
                   'strategy', 'strategies', 'outlet_temp_control.py')


def extra(mod):
    class ThermalOptimizationBaseStrategy(object):
        pass
    return {
        'watcher.decision_engine.model': mod(
            'watcher.decision_engine.model',
            element=mod('watcher.decision_engine.model.element')),
        'watcher.decision_engine.strategy': mod(
            'watcher.decision_engine.strategy'),
        'watcher.decision_engine.strategy.strategies': mod(
            'watcher.decision_engine.strategy.strategies',
            base=mod('b', ThermalOptimizationBaseStrategy=(
                ThermalOptimizationBaseStrategy))),
    }


def execute(src):
    m = load(src, 'otc_%d' % id(src), extra)
    s = object.__new__(m.OutletTempControl)
    s.MIGRATION = 'migrate'
    hot = types.SimpleNamespace(uuid='u1', hostname='cube45')
    cool = types.SimpleNamespace(uuid='u2', hostname='cube46')
    vm = types.SimpleNamespace(uuid='vm1', name='vm1', vcpus=1, disk=1,
                               memory=1)
    s.group_hosts_by_outlet_temp = lambda: (
        [{'compute_node': hot, 'outlet_temp': 40}],
        [{'compute_node': cool, 'outlet_temp': 20}])
    s.choose_instance_to_migrate = lambda hosts: (hot, vm)
    s._compute_model = types.SimpleNamespace(
        get_node_free_resources=lambda n: dict(vcpu=8, disk=8, memory=8),
        migrate_instance=lambda i, a, b: True)
    type(s).compute_model = property(lambda self: self._compute_model)
    actions = []
    s.solution = types.SimpleNamespace(
        add_action=lambda **kw: actions.append(kw))
    s.do_execute()
    return actions


class TestOutletTempMigrateNodes(unittest.TestCase):
    def test_patched_migrates_by_hostname(self):
        with tempfile.TemporaryDirectory() as d:
            actions = execute(patched(OTC, d))
        self.assertEqual(len(actions), 1)
        p = actions[0]['input_parameters']
        self.assertEqual((p['source_node'], p['destination_node']),
                         ('cube45', 'cube46'))

    def test_pristine_migrates_by_uuid(self):
        p = execute(OTC + '.orig')[0]['input_parameters']
        self.assertEqual((p['source_node'], p['destination_node']),
                         ('u1', 'u2'))


if __name__ == '__main__':
    unittest.main()
