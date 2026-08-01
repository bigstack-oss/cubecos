# Monasca agent check: host hardware sensors via IPMI.
# Feeds Watcher thermal_optimization / airflow_optimization / saving_energy.
import subprocess

import monasca_agent.collector.checks as checks


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
        for metric, sensor in sensors.items():
            try:
                out = subprocess.check_output(
                    ['sudo', '-n', 'ipmitool', 'sensor', 'reading', sensor],
                    timeout=15, stderr=subprocess.DEVNULL).decode()
                value = float(out.split('|')[1].strip())
            except (OSError, subprocess.SubprocessError, IndexError, ValueError) as e:
                self.log.debug('ipmi sensor %s unavailable: %s', sensor, e)
                continue
            self.gauge(metric, value, dimensions=dimensions)
