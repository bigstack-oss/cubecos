"""epoxy_patch prometheus.py.patch + noisy_neighbor.py.patch: the Prometheus
datasource serves host_outlet_temp / host_inlet_temp / host_airflow /
host_power from ipmi_exporter and instance_l3_cache_usage from hex_sdk's
ceilometer_cpu_l3_cache and renders whole-second ranges; noisy_neighbor calls
the L3 getter with the base signature, ranks flagged hosts by watcher-priority
and migrates by host name. Applies each patch to its pristine .orig and
loads it with stubs.

    python3.11 -m unittest discover -s core/watcher/tests -v
"""
import importlib.machinery
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import types
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
WATCHER = os.path.join(HERE, '..', 'epoxy_patch', 'watcher')
PROM = os.path.join(WATCHER, 'decision_engine', 'datasources', 'prometheus.py')
NOISY = os.path.join(WATCHER, 'decision_engine', 'strategy', 'strategies',
                     'noisy_neighbor.py')


def patched(path, d):
    tgt = os.path.join(d, os.path.basename(path))
    with open(path + '.orig') as f, open(tgt, 'w') as o:
        o.write(f.read())
    subprocess.run(['patch', '--forward', '--no-backup-if-mismatch', '-r', '-',
                    tgt, '-i', path + '.patch'], check=True,
                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    return tgt


class _Log(object):
    def __getattr__(self, name):
        return lambda *a, **k: None


def load(src, name, extra):
    """exec src with stub modules installed only for the import"""
    def mod(n, **attrs):
        m = types.ModuleType(n)
        m.__dict__.update(attrs)
        return m

    class MetricNotAvailable(Exception):
        def __init__(self, metric=None, **kw):
            super().__init__(metric)

    class InvalidParameter(Exception):
        def __init__(self, message=None, **kw):
            super().__init__(message)

    class Base(object):
        def _get_meter(self, meter_name):
            meter = self.METRIC_MAP.get(meter_name)
            if meter is None:
                raise MetricNotAvailable(metric=meter_name)
            return meter

        def query_retry(self, f, *args, ignored_exc=None, **kwargs):
            return f(*args, **kwargs)

    conf = types.SimpleNamespace(prometheus_client=types.SimpleNamespace(
        fqdn_label='fqdn', instance_uuid_label='resource'))
    stubs = {
        'observabilityclient': mod('observabilityclient'),
        'observabilityclient.prometheus_client': mod(
            'observabilityclient.prometheus_client',
            PrometheusAPIClientError=Exception),
        'oslo_config': mod('oslo_config', cfg=mod(
            'oslo_config.cfg', CONF=conf,
            IntOpt=lambda *a, **k: None, FloatOpt=lambda *a, **k: None)),
        'oslo_log': mod('oslo_log', log=mod('oslo_log.log',
                                            getLogger=lambda n: _Log())),
        'watcher': mod('watcher'),
        'watcher._i18n': mod('watcher._i18n', _=lambda s: s),
        'watcher.common': mod('watcher.common'),
        'watcher.common.exception': mod(
            'watcher.common.exception', MetricNotAvailable=MetricNotAvailable,
            InvalidParameter=InvalidParameter, MissingParameter=Exception),
        'watcher.decision_engine': mod('watcher.decision_engine'),
        'watcher.decision_engine.datasources': mod(
            'watcher.decision_engine.datasources'),
        'watcher.decision_engine.datasources.base': mod(
            'watcher.decision_engine.datasources.base', DataSourceBase=Base),
    }
    stubs['observabilityclient'].prometheus_client = \
        stubs['observabilityclient.prometheus_client']
    stubs['watcher.common'].exception = stubs['watcher.common.exception']
    stubs['watcher.decision_engine.datasources'].base = \
        stubs['watcher.decision_engine.datasources.base']
    stubs.update(extra(mod))
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


class FakeClient(object):
    def __init__(self, value='31'):
        self.queries = []
        self.value = value

    def query(self, q):
        self.queries.append(q)
        return [types.SimpleNamespace(value=self.value)]


def helper(mod_):
    h = object.__new__(mod_.PrometheusHelper)
    h.prometheus = FakeClient()
    h.prometheus_fqdn_label = 'fqdn'
    h.prometheus_fqdn_labels = {'cube45', 'cube46'}
    h.prometheus_host_instance_map = {}
    return h


NODE = types.SimpleNamespace(hostname='cube45',
                             uuid='aaaaaaaa-0000-0000-0000-000000000000')
VM = types.SimpleNamespace(uuid='11111111-1111-1111-1111-111111111111',
                           vcpus=1)


def promql_name_regex(selector):
    """the name=~ regex of a selector, as an anchored python regex"""
    rx = re.search(r'name=~"([^"]*)"', selector).group(1)
    flags = re.I if rx.startswith('(?i)') else 0
    return re.compile('^(?:%s)$' % rx.replace('(?i)', ''), flags)


class TestPrometheusHwMetrics(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.mod = load(patched(PROM, cls.tmp.name), 'prom_patched',
                       lambda mod: {})
        cls.orig = load(PROM + '.orig', 'prom_orig', lambda mod: {})

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_pristine_maps_hw_meters_to_none(self):
        for m in ('host_outlet_temp', 'host_inlet_temp', 'host_airflow',
                  'host_power', 'instance_l3_cache_usage'):
            self.assertIsNone(self.orig.PrometheusHelper.METRIC_MAP[m])

    def test_hw_meters_are_mapped(self):
        for m in ('host_outlet_temp', 'host_inlet_temp', 'host_airflow',
                  'host_power', 'instance_l3_cache_usage'):
            self.assertIsNotNone(self.mod.PrometheusHelper.METRIC_MAP[m])

    def test_outlet_temp_query_pins_host_and_takes_max(self):
        h = helper(self.mod)
        v = h.statistic_aggregation(NODE, 'compute_node', 'host_outlet_temp',
                                    period=300, aggregate='mean')
        self.assertEqual(v, 31.0)
        self.assertEqual(
            h.prometheus.queries[0],
            "max(avg_over_time(ipmi_temperature_celsius{fqdn='cube45',"
            "name=~\"(?i).*(exhaust|outlet).*\"}[300s]))")

    def test_airflow_scaled_cfm_to_tenth_cfm(self):
        h = helper(self.mod)
        h.get_host_airflow(NODE, 300, 'mean')
        q = h.prometheus.queries[0]
        self.assertTrue(q.endswith(') * 10'), q)
        self.assertIn("ipmi_sensor_value{fqdn='cube45',", q)

    def test_power_falls_back_from_dcmi(self):
        h = helper(self.mod)
        h.get_host_power(NODE, 300, 'max')
        self.assertEqual(
            h.prometheus.queries[0],
            "max(max_over_time(ipmi_dcmi_power_consumption_watts"
            "{fqdn='cube45'}[300s])) or "
            "max(max_over_time(ipmi_power_watts{fqdn='cube45',"
            "name=~\"(?i).*(pwr|power) ?consumption.*\"}[300s]))")

    def test_host_meter_with_instance_resource_type_uses_node(self):
        # uniform_airflow asks for host_inlet_temp with resource_type instance
        h = helper(self.mod)
        h.statistic_aggregation(resource=NODE, resource_type='instance',
                                meter_name='host_inlet_temp', period=300)
        self.assertIn("fqdn='cube45'", h.prometheus.queries[0])
        self.assertNotIn(NODE.uuid, h.prometheus.queries[0])

    def test_unknown_host_returns_none(self):
        h = helper(self.mod)
        h._build_prometheus_fqdn_labels = lambda: {'cube45'}
        h._build_prometheus_host_instance_map = lambda: {}
        node = types.SimpleNamespace(hostname='nope', uuid='x')
        self.assertIsNone(h.get_host_outlet_temp(node, 300, 'mean'))
        self.assertEqual(h.prometheus.queries, [])

    def test_l3_cache_query(self):
        h = helper(self.mod)
        h.get_instance_l3_cache_usage(VM, 600, 'mean')
        self.assertEqual(
            h.prometheus.queries[0],
            "max(avg_over_time(ceilometer_cpu_l3_cache"
            "{resource='%s'}[600s]))" % VM.uuid)

    def test_float_period_renders_whole_seconds(self):
        # noisy_neighbor's schema default period is 100.0
        h = helper(self.mod)
        h.get_instance_l3_cache_usage(VM, 100.0, 'mean')
        h.get_host_outlet_temp(NODE, 299.7, 'mean')
        h.get_host_cpu_usage(NODE, 0.4, 'mean')
        self.assertIn('[100s]', h.prometheus.queries[0])
        self.assertIn('[299s]', h.prometheus.queries[1])
        self.assertIn('[1s]', h.prometheus.queries[2])
        for q in h.prometheus.queries:
            self.assertNotRegex(q, r'\[[0-9]+\.[0-9]*s\]')

    def test_pristine_renders_float_period(self):
        h = helper(self.orig)
        h.get_host_cpu_usage(NODE, 100.0, 'mean')
        self.assertIn('[100.0s]', h.prometheus.queries[0])

    def test_metric_map_override_is_honoured(self):
        h = helper(self.mod)
        h.METRIC_MAP = dict(h.METRIC_MAP, host_inlet_temp=(
            'ipmi_temperature_celsius{name=~"System Temp"}'))
        h.get_host_inlet_temp(NODE, 300, 'mean')
        self.assertIn('name=~"System Temp"', h.prometheus.queries[0])

    def test_default_regexes_on_r630_sensor_names(self):
        mm = self.mod.PrometheusHelper.METRIC_MAP
        outlet = promql_name_regex(mm['host_outlet_temp'])
        inlet = promql_name_regex(mm['host_inlet_temp'])
        airflow = promql_name_regex(mm['host_airflow'])
        power = promql_name_regex(mm['host_power'].split(' or ')[1])
        self.assertTrue(outlet.match('Exhaust Temp'))
        self.assertTrue(inlet.match('Inlet Temp'))
        self.assertTrue(airflow.match('System Airflow'))   # iDRAC9
        self.assertTrue(power.match('Pwr Consumption'))
        for cpu in ('Temp', 'CPU1 Temp'):
            self.assertFalse(outlet.match(cpu) or inlet.match(cpu))
        self.assertFalse(airflow.match('Fan1A'))
        self.assertFalse(outlet.match('Inlet Temp'))
        self.assertFalse(inlet.match('Exhaust Temp'))


class TestNoisyNeighborL3Call(unittest.TestCase):
    def _strategy(self, src):
        def extra(mod):
            class NoisyNeighborBaseStrategy(object):
                def __init__(self, config, osc=None):
                    pass
            return {
                'watcher.decision_engine.strategy': mod(
                    'watcher.decision_engine.strategy'),
                'watcher.decision_engine.strategy.strategies': mod(
                    'watcher.decision_engine.strategy.strategies',
                    base=mod('b', NoisyNeighborBaseStrategy=(
                        NoisyNeighborBaseStrategy))),
            }
        m = load(src, 'noisy_%d' % id(src), extra)
        s = object.__new__(m.NoisyNeighbor)
        s.meter_name = 'instance_l3_cache_usage'
        s.period = 100
        calls = []

        class Backend(object):
            # the base datasource signature
            def get_instance_l3_cache_usage(self, resource, period,
                                            aggregate, granularity=None):
                calls.append(period)
                return {100: 6.0, 200: 5.0}[period]
        s.datasource_backend = Backend()
        return s, calls

    def test_patched_reads_current_and_previous(self):
        with tempfile.TemporaryDirectory() as d:
            s, calls = self._strategy(patched(NOISY, d))
            self.assertEqual(s.get_current_and_previous_cache(VM), (6.0, 4.0))
            self.assertEqual(calls, [100, 200])

    def _group(self, src, meta=None):
        meta = meta or {}
        s, _ = self._strategy(src)
        s.DEFAULT_WATCHER_PRIORITY = 5
        s.cache_threshold = 35.0

        class Inst(object):
            def __init__(self, uuid, exclude=False):
                self.uuid = uuid
                self.watcher_exclude = exclude

                self.metadata = {}

            def get(self, key):
                return self.metadata
        # current / 2-period means: A dropped, X and B rose
        cache = {'A': {100: 2.0, 200: 6.0}, 'X': {100: 9.0, 200: 5.0},
                 'B': {100: 9.0, 200: 5.0}}

        class Backend(object):
            def get_instance_l3_cache_usage(self, resource, period,
                                            aggregate, granularity=None):
                return cache[resource.uuid][period]
        insts = [Inst('A'), Inst('B'), Inst('X', exclude=True)]
        for i in insts:
            i.metadata.update(meta.get(i.uuid, {}))
        node = types.SimpleNamespace(uuid='n1')
        s.datasource_backend = Backend()
        s._compute_model = types.SimpleNamespace(
            get_all_compute_nodes=lambda: {'n1': node},
            get_node_instances=lambda n: insts)
        type(s).compute_model = property(lambda self: self._compute_model)
        release, _ = s.group_hosts()
        return release['n1']['priority_vm'].uuid, release['n1']['noisy_vm'].uuid

    def test_patched_skips_excluded_noisy_candidate(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(self._group(patched(NOISY, d)), ('A', 'B'))

    def test_patched_sorts_mixed_watcher_priority(self):
        # only some instances carry the property, as on a shared host;
        # B first by value, so A must still be found as the priority VM
        meta = {'A': {'watcher-priority': '1'}, 'B': {'watcher-priority': '9'}}
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(self._group(patched(NOISY, d), meta), ('A', 'B'))

    def test_pristine_sort_raises_on_mixed_watcher_priority(self):
        with self.assertRaises(TypeError):
            self._group(NOISY + '.orig', {'A': {'watcher-priority': '1'}})

    def _execute(self, src):
        # n1 and n2 both flagged; n2's priority VM ranks higher; n3 is free
        s, _ = self._strategy(src)
        s.DEFAULT_WATCHER_PRIORITY = 5
        s.MIGRATION = 'migrate'
        s.input_parameters = types.SimpleNamespace(cache_threshold=35.0,
                                                   period=100.0)

        class Inst(object):
            def __init__(self, uuid, prio):
                self.uuid = self.name = uuid
                self.watcher_exclude = False
                self.vcpus = self.disk = self.memory = 1
                self.metadata = {'watcher-priority': prio}

            def get(self, key):
                return self.metadata
        # P* dropped (priority), N* rose (noisy)
        drop, rise = {100: 2.0, 200: 6.0}, {100: 9.0, 200: 5.0}
        nodes = {'u1': types.SimpleNamespace(uuid='u1', hostname='cube45'),
                 'u2': types.SimpleNamespace(uuid='u2', hostname='cube46'),
                 'u3': types.SimpleNamespace(uuid='u3', hostname='cube47')}
        insts = {'u1': [Inst('P1', '3'), Inst('N1', '9')],
                 'u2': [Inst('P2', '1'), Inst('N2', '9')], 'u3': []}
        cache = {'P1': drop, 'P2': drop, 'N1': rise, 'N2': rise}

        class Backend(object):
            # accepts the pristine (meter_name, period) call too
            def get_instance_l3_cache_usage(self, resource, *args, **kw):
                period = [a for a in args if isinstance(a, (int, float))][0]
                return cache[resource.uuid][int(period)]
        s.datasource_backend = Backend()
        s._compute_model = types.SimpleNamespace(
            get_all_compute_nodes=lambda: nodes,
            get_node_instances=lambda n: insts[n.uuid],
            get_node_free_resources=lambda n: dict(vcpu=8, disk=8, memory=8),
            get_node_by_uuid=lambda u: nodes[u],
            migrate_instance=lambda i, a, b: True)
        type(s).compute_model = property(lambda self: self._compute_model)
        actions = []
        s.solution = types.SimpleNamespace(
            add_action=lambda **kw: actions.append(kw))
        s.do_execute()
        return actions

    def test_patched_two_flagged_hosts_migrate_by_hostname(self):
        with tempfile.TemporaryDirectory() as d:
            actions = self._execute(patched(NOISY, d))
        self.assertEqual(len(actions), 1)
        self.assertEqual(actions[0]['resource_id'], 'N2')
        p = actions[0]['input_parameters']
        self.assertEqual((p['source_node'], p['destination_node']),
                         ('cube46', 'cube47'))

    def test_pristine_two_flagged_hosts_raise(self):
        with self.assertRaises(TypeError):
            self._execute(NOISY + '.orig')

    def test_pristine_call_raises_and_reads_nothing(self):
        s, calls = self._strategy(NOISY + '.orig')
        self.assertEqual(s.get_current_and_previous_cache(VM), (None, None))
        self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()
