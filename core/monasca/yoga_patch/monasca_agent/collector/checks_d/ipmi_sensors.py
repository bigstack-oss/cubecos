# Monasca agent check: host hardware sensors via IPMI.
# Feeds Watcher thermal_optimization / airflow_optimization / saving_energy.
import re
import subprocess

import monasca_agent.collector.checks as checks

# first numeric token in a `sensor reading` value cell ("45", "36.500",
# or a unit-bearing "12.3 degrees C" from other firmware)
_NUM = re.compile(r'[-+]?[0-9]*\.?[0-9]+')


class IpmiSensors(checks.AgentCheck):
    """Publish host_outlet_temp / host_inlet_temp / host_airflow / host_power
    read from the local BMC via `ipmitool sensor reading`.

    The logical-metric -> IPMI sensor-name map is hardware specific; override it
    per node via the instance `sensors:` dict. Missing sensors / no BMC are
    skipped, so the check is safe on hosts without IPMI.
    """

    DEFAULT_SENSORS = {
        'host_outlet_temp': 'Outlet-TMP',
        'host_inlet_temp': 'PSU1_Inlet_TEMP',
        'host_airflow': 'FAN1-SPEED',
        'host_power': 'PSU1_POUT',
    }

    def check(self, instance):
        dimensions = self._set_dimensions(None, instance)
        sensors = instance.get('sensors') or self.DEFAULT_SENSORS
        # one batched ipmitool call (one sudo) per cycle; a missing sensor is
        # omitted from output and forces exit 1 while the rest still print, so
        # parse stdout regardless of return code (do NOT gate on it)
        try:
            proc = subprocess.run(
                ['sudo', '-n', 'ipmitool', 'sensor', 'reading'] + list(sensors.values()),
                timeout=15, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            out = proc.stdout.decode()
        except (OSError, subprocess.SubprocessError) as e:
            self.log.debug('ipmi sensors unavailable: %s', e)
            return
        readings = {}
        for line in out.splitlines():
            name, sep, value = line.partition('|')
            if not sep:
                continue
            m = _NUM.search(value)
            if m:
                readings[name.strip()] = float(m.group())
        for metric, sensor in sensors.items():
            if sensor in readings:
                self.gauge(metric, readings[sensor], dimensions=dimensions)
            else:
                self.log.debug('ipmi sensor %s unavailable', sensor)
