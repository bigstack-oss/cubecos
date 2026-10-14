"""epoxy_patch host_maintenance.py.patch and
node_resource_consolidation.py.patch: audit-scope-excluded instances
(watcher_exclude) are never planned. host_maintenance refuses a node that
holds any and names the source node by host name; node_resource_consolidation
never drains a node that holds any.

    python3.11 -m unittest discover -s core/watcher/tests -v
"""
import enum
import importlib.machinery
import importlib.util
import os
import subprocess
import sys
import tempfile
import types
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SDIR = os.path.join(HERE, '..', 'epoxy_patch', 'watcher', 'decision_engine',
                    'strategy', 'strategies')


class WatcherException(Exception):
    pass


class ServiceState(enum.Enum):
    ONLINE = 'up'
    OFFLINE = 'down'
    ENABLED = 'enabled'
    DISABLED = 'disabled'


class InstanceState(enum.Enum):
    ACTIVE = 'active'
    STOPPED = 'stopped'


class Solution(object):
    def __init__(self):
        self.actions = []

    def add_action(self, action_type, resource_id, input_parameters):
        self.actions.append(dict(action_type=action_type,
                                 resource_id=resource_id,
                                 input_parameters=input_parameters))


class Base(object):
    MIGRATION = 'migrate'
    REASON_FOR_MAINTAINING = 'watcher_maintaining'

    def __init__(self, config, osc=None):
        self.solution = Solution()
        self.input_parameters = {}


def load(src, name):
    def mod(n, **attrs):
        m = types.ModuleType(n)
        m.__dict__.update(attrs)
        return m

    class _Log(object):
        def __getattr__(self, name):
            return lambda *a, **k: None

    stubs = {
        'oslo_log': mod('oslo_log', log=mod('oslo_log.log',
                                            getLogger=lambda n: _Log())),
        'watcher': mod('watcher'),
        'watcher._i18n': mod('watcher._i18n', _=lambda s: s),
        'watcher.common': mod('watcher.common', exception=mod(
            'watcher.common.exception', WatcherException=WatcherException,
            IllegalArgumentException=WatcherException)),
        'watcher.objects': mod('watcher.objects', audit=types.SimpleNamespace(
            AuditType=types.SimpleNamespace(
                ONESHOT=types.SimpleNamespace(value='ONESHOT')))),
        'watcher.decision_engine': mod('watcher.decision_engine'),
        'watcher.decision_engine.model': mod(
            'watcher.decision_engine.model', element=mod(
                'watcher.decision_engine.model.element',
                ServiceState=ServiceState, InstanceState=InstanceState)),
        'watcher.decision_engine.strategy': mod(
            'watcher.decision_engine.strategy'),
        'watcher.decision_engine.strategy.strategies': mod(
            'watcher.decision_engine.strategy.strategies',
            base=mod('b', HostMaintenanceBaseStrategy=Base,
                     ServerConsolidationBaseStrategy=Base)),
    }
    stubs['watcher'].objects = stubs['watcher.objects']
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


def load_pair(tmp, base):
    src = os.path.join(SDIR, base + '.py')
    tgt = os.path.join(tmp, base + '.py')
    with open(src + '.orig') as f, open(tgt, 'w') as o:
        o.write(f.read())
    subprocess.run(['patch', '--forward', '--no-backup-if-mismatch', '-r',
                    '-', tgt, '-i', src + '.patch'], check=True,
                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    return (load(src + '.orig', base + '_orig'),
            load(tgt, base + '_patched'))


class Inst(object):
    def __init__(self, name, exclude=False, vcpus=1):
        self.uuid = 'uuid-' + name
        self.name = name
        self.vcpus = vcpus
        self.memory = 1024
        self.state = 'active'
        self.metadata = {}
        self.watcher_exclude = exclude


class Node(object):
    def __init__(self, hostname, instances, vcpus=32):
        self.uuid = 'uuid-' + hostname
        self.hostname = hostname
        self.vcpus = vcpus
        self.memory = 65536
        self.state = ServiceState.ONLINE.value
        self.status = ServiceState.ENABLED.value
        self.disabled_reason = None
        self.instances = list(instances)


class Model(object):
    def __init__(self, *nodes):
        self.nodes = nodes

    def get_all_compute_nodes(self):
        return {n.uuid: n for n in self.nodes}

    def get_node_by_name(self, name):
        return [n for n in self.nodes if n.hostname == name][0]

    def get_node_instances(self, node):
        return list(node.instances)

    def get_node_used_resources(self, node):
        return {'vcpu': sum(i.vcpus for i in node.instances),
                'memory': sum(i.memory for i in node.instances)}

    def get_node_free_resources(self, node):
        used = self.get_node_used_resources(node)
        return {'vcpu': node.vcpus - used['vcpu'],
                'memory': node.memory - used['memory']}

    def migrate_instance(self, inst, src, dest):
        src.instances.remove(inst)
        dest.instances.append(inst)
        return True


def strategy(mod_, cls, model, **params):
    s = getattr(mod_, cls)(config=None)
    s.compute_model = model
    s.input_parameters = params
    return s


def migrated(s):
    return [a['input_parameters']['resource_name']
            for a in s.solution.actions if a['action_type'] == 'migrate']


class TestHostMaintenance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.orig, cls.mod = load_pair(cls.tmp.name, 'host_maintenance')

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def _run(self, mod_, insts):
        model = Model(Node('cube45', insts), Node('cube46', []))
        s = strategy(mod_, 'HostMaintenance', model,
                     maintenance_node='cube45')
        s.do_execute()
        return s

    def test_pristine_plans_excluded_instances(self):
        s = self._run(self.orig, [Inst('vm'), Inst('amphora', exclude=True)])
        self.assertIn('amphora', migrated(s))

    def test_excluded_instance_refuses_maintenance(self):
        insts = [Inst('vm'), Inst('amp1', exclude=True),
                 Inst('amp2', exclude=True)]
        s = strategy(self.mod, 'HostMaintenance',
                     Model(Node('cube45', insts), Node('cube46', [])),
                     maintenance_node='cube45')
        with self.assertRaises(WatcherException) as cm:
            s.do_execute()
        self.assertIn('cube45 has 2 audit-excluded instances', str(cm.exception))
        self.assertEqual([], s.solution.actions)

    def test_pristine_source_node_is_uuid(self):
        s = self._run(self.orig, [Inst('vm')])
        a = [a for a in s.solution.actions if a['action_type'] == 'migrate']
        self.assertEqual('uuid-cube45', a[0]['input_parameters']['source_node'])

    def test_source_node_is_hostname(self):
        s = self._run(self.mod, [Inst('vm1'), Inst('vm2')])
        self.assertEqual(['vm1', 'vm2'], migrated(s))
        for a in s.solution.actions:
            if a['action_type'] == 'migrate':
                self.assertEqual('cube45',
                                 a['input_parameters']['source_node'])
        self.assertEqual('change_nova_service_state',
                         s.solution.actions[0]['action_type'])

    def test_backup_node_path_uses_hostname(self):
        model = Model(Node('cube45', [Inst('vm')]), Node('cube46', []))
        s = strategy(self.mod, 'HostMaintenance', model,
                     maintenance_node='cube45', backup_node='cube46')
        s.do_execute()
        a = [a for a in s.solution.actions if a['action_type'] == 'migrate']
        self.assertEqual({'migration_type': 'live', 'source_node': 'cube45',
                          'destination_node': 'cube46', 'resource_name': 'vm'},
                         a[0]['input_parameters'])


class TestNodeResourceConsolidation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.orig, cls.mod = load_pair(cls.tmp.name,
                                      'node_resource_consolidation')

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def _model(self, light):
        # cube47 is the lightest node, so it is the one consolidation drains
        return Model(Node('cube45', [Inst('a%d' % n) for n in range(6)]),
                     Node('cube46', [Inst('b%d' % n) for n in range(4)]),
                     Node('cube47', light))

    def _run(self, mod_, model, host_choice='auto'):
        s = strategy(mod_, 'NodeResourceConsolidation', model,
                     host_choice=host_choice)
        s.host_choice = host_choice
        s.do_execute()
        return s

    def test_pristine_drains_node_with_excluded_instances(self):
        s = self._run(self.orig, self._model(
            [Inst('vm'), Inst('amphora', exclude=True)]))
        self.assertIn('amphora', migrated(s))

    def test_node_with_excluded_instances_is_not_drained(self):
        for choice in ('auto', 'specify'):
            s = self._run(self.mod, self._model(
                [Inst('vm'), Inst('amphora', exclude=True)]), choice)
            self.assertNotIn('amphora', migrated(s), choice)
            self.assertNotIn('vm', migrated(s), choice)
            for a in s.solution.actions:
                self.assertNotEqual('cube47',
                                    a['input_parameters']['resource_name'],
                                    choice)

    def test_next_node_is_drained_instead(self):
        model = Model(Node('cube45', [Inst('a%d' % n) for n in range(6)]),
                      Node('cube46', [Inst('b%d' % n) for n in range(4)]),
                      Node('cube47', [Inst('vm'),
                                      Inst('amp', exclude=True)]))
        s = self._run(self.mod, model)
        self.assertEqual(['b0', 'b1', 'b2', 'b3'], sorted(migrated(s)))
        self.assertNotIn('amp', migrated(s))

    def test_unexcluded_node_still_drained(self):
        s = self._run(self.mod, self._model([Inst('vm1'), Inst('vm2')]))
        self.assertEqual(['vm1', 'vm2'], sorted(migrated(s)))

    def test_excluded_instances_never_migrated(self):
        s = strategy(self.mod, 'NodeResourceConsolidation', Model())
        src = Node('cube47', [Inst('vm'), Inst('amp', exclude=True)])
        s.add_migrate_actions([src], [Node('cube45', [])])
        self.assertEqual(['vm'], migrated(s))


if __name__ == '__main__':
    unittest.main()
