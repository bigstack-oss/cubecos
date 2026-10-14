"""epoxy_patch engine/manager.py.patch: an instance-failure notification from
a host the instance does not run on (e.g. the destination of a failed live
migration) is ignored; pristine masakari restarts the instance.

Masakari is stubbed, so this runs standalone:
    python3.11 -m unittest discover -s core/masakari/tests -v
"""
import importlib.machinery
import importlib.util
import os
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE = os.path.join(HERE, '..', 'epoxy_patch', 'masakari', 'engine')
UUID = 'f85ec18d-db3d-4529-8622-1b5a1270ea9e'


class _Exc(Exception):
    message = 'stub'


EXC = types.SimpleNamespace(
    IgnoreInstanceRecoveryException=type('Ignore', (_Exc,), {}),
    SkipInstanceRecoveryException=type('Skip', (_Exc,), {}),
    MasakariException=type('Masakari', (_Exc,), {}),
    InstanceRecoveryFailureException=type('Failure', (_Exc,), {}),
)
STATUS = types.SimpleNamespace(FINISHED='finished', IGNORED='ignored',
                               ERROR='error', NEW='new', RUNNING='running',
                               FAILED='failed')


def _stub_modules(hosts, nova_host):
    """Fake the modules manager.py imports; returns them by name."""
    def mod(name, **attrs):
        m = types.ModuleType(name)
        m.__dict__.update(attrs)
        return m

    class Manager(object):
        def __init__(self, *a, **k):
            pass

    host_obj = mock.Mock()
    host_obj.get_by_uuid.side_effect = (
        lambda ctx, uuid: types.SimpleNamespace(name=hosts[uuid]))
    server = types.SimpleNamespace(**{'OS-EXT-SRV-ATTR:host': nova_host})
    nova_api = mock.Mock()
    nova_api.API.return_value.get_server.return_value = server

    fields = mod('masakari.objects.fields', NotificationStatus=STATUS,
                 EventNotificationAction=mock.Mock(),
                 EventNotificationPhase=mock.Mock())
    objects = mod('masakari.objects', Host=host_obj, fields=fields)
    engine = mod('masakari.engine',
                 driver=mod('masakari.engine.driver',
                            load_masakari_driver=mock.Mock()),
                 instance_events=mod('masakari.engine.instance_events',
                                     is_valid_event=lambda p: True),
                 rpcapi=mod('masakari.engine.rpcapi',
                            EngineAPI=types.SimpleNamespace(
                                RPC_API_VERSION='1.1')),
                 utils=mod('masakari.engine.utils',
                           notify_about_notification_update=mock.Mock()))
    compute = mod('masakari.compute', nova=nova_api)
    masakari = mod('masakari', conf=mod('masakari.conf', CONF=mock.Mock()),
                   engine=engine, compute=compute, objects=objects,
                   exception=mod('masakari.exception', **vars(EXC)),
                   i18n=mod('masakari.i18n', _=lambda s: s),
                   manager=mod('masakari.manager', Manager=Manager),
                   utils=mod('masakari.utils'))
    mods = {
        'oslo_log': mod('oslo_log', log=mod('oslo_log.log',
                                            getLogger=mock.Mock())),
        'oslo_messaging': mod('oslo_messaging', Target=mock.Mock()),
        'oslo_service': mod('oslo_service', periodic_task=mod(
            'oslo_service.periodic_task',
            periodic_task=lambda **k: (lambda f: f))),
        'oslo_utils': mod('oslo_utils', timeutils=mock.Mock()),
        'masakari': masakari,
    }
    for name in ('oslo_log.log', 'oslo_service.periodic_task'):
        mods[name] = getattr(mods[name.split('.')[0]], name.split('.')[1])
    for name in ('conf', 'engine', 'compute', 'objects', 'exception', 'i18n',
                 'manager', 'utils'):
        mods['masakari.' + name] = getattr(masakari, name)
    for name in ('driver', 'instance_events', 'rpcapi', 'utils'):
        mods['masakari.engine.' + name] = getattr(engine, name)
    mods['masakari.compute.nova'] = nova_api
    mods['masakari.objects.fields'] = fields
    return mods


def _load(path, reporter, nova_host):
    """Load manager.py at path; returns (manager, driver)."""
    hosts = {'reporter-uuid': reporter}
    with mock.patch.dict(sys.modules, _stub_modules(hosts, nova_host)):
        loader = importlib.machinery.SourceFileLoader('mgr_under_test', path)
        spec = importlib.util.spec_from_loader(loader.name, loader)
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
    mgr = object.__new__(m.MasakariManager)
    mgr.driver = mock.Mock()
    return mgr, mgr.driver


def _notification():
    return types.SimpleNamespace(
        notification_uuid='n1', source_host_uuid='reporter-uuid', type='VM',
        payload={'event': 'LIFECYCLE', 'vir_domain_event': 'STOPPED_FAILED',
                 'instance_uuid': UUID})


class TestInstanceFailureReportingHost(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.orig = os.path.join(ENGINE, 'manager.py.orig')
        cls.patched = os.path.join(cls.tmp.name, 'manager.py')
        with open(cls.orig) as f, open(cls.patched, 'w') as o:
            o.write(f.read())
        with open(os.path.join(ENGINE, 'manager.py.patch')) as p:
            subprocess.run(['patch', '--forward', '--no-backup-if-mismatch',
                            '-r', '-', cls.patched], stdin=p, check=True,
                           stdout=subprocess.DEVNULL)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def _run(self, path, reporter, nova_host):
        mgr, drv = _load(path, reporter, nova_host)
        status = mgr._handle_notification_type_instance(None, _notification())
        return status, drv.execute_instance_failure

    def test_pristine_restarts_from_another_host(self):
        # failed-migration destination cube45 reports; VM runs on cube46
        status, recover = self._run(self.orig, 'cube45', 'cube46')
        recover.assert_called_once_with(None, UUID, 'n1')
        self.assertEqual(STATUS.FINISHED, status)

    def test_patched_ignores_another_host(self):
        status, recover = self._run(self.patched, 'cube45', 'cube46')
        recover.assert_not_called()
        self.assertEqual(STATUS.IGNORED, status)

    def test_patched_recovers_on_own_host(self):
        status, recover = self._run(self.patched, 'cube46', 'cube46')
        recover.assert_called_once_with(None, UUID, 'n1')
        self.assertEqual(STATUS.FINISHED, status)

    def test_patched_matches_short_and_fqdn(self):
        status, recover = self._run(self.patched, 'CUBE46.lab', 'cube46')
        recover.assert_called_once()
        self.assertEqual(STATUS.FINISHED, status)

    def test_patched_recovers_when_nova_has_no_host(self):
        status, recover = self._run(self.patched, 'cube45', None)
        recover.assert_called_once()
        self.assertEqual(STATUS.FINISHED, status)


if __name__ == '__main__':
    unittest.main()
