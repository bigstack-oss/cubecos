// api/controllers/stats.control.js

const httpStatus = require('http-status');
const { HexCli, HexSdk, HexConfig } = require('../services/hex-cmds');
const logger = require('../../config-server/logger');

/**
 * Returns partition information
 * @public
 */
exports.partition = async (req, res, next) => {
  try {
    const info = await new HexCli().run('-c firmware list shell');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});
    const partition = {
      active: out.active,
      parts: [
        { version: out.firmware_version_1,
          date: out.install_date_1,
          type: out.install_type_1,
          boot: out.last_boot_1 },
        { version: out.firmware_version_2,
          date: out.install_date_2,
          type: out.install_type_2,
          boot: out.last_boot_2 },
      ],
    };
    return res.json(partition);
  } catch (error) {
    return next(error);
  }
};

exports.clusterCpu = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_cluster_cpu_usage');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});
    const usage = {
      total: parseFloat(out.total) || 0,
      trend: parseFloat(out.trend) || 0,
      chart: JSON.parse(out.chart) || [],
    };
    return res.json(usage);
  } catch (error) {
    return next(error);
  }
};

exports.clusterMem = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_cluster_mem_usage');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});
    const usage = {
      total: parseFloat(out.total) || 0,
      trend: parseFloat(out.trend) || 0,
      chart: JSON.parse(out.chart) || [],
    };
    return res.json(usage);
  } catch (error) {
    return next(error);
  }
};

exports.storageBandwidth = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_storage_bandwidth_usage');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});
    const usage = {
      read: {
        rate: parseFloat(out.read_rate) || 0,
        trend: parseFloat(out.read_trend) || 0,
        chart: JSON.parse(out.read_chart) || [],
      },
      write: {
        rate: parseFloat(out.write_rate) || 0,
        trend: parseFloat(out.write_trend) || 0,
        chart: JSON.parse(out.write_chart) || [],
      },
    };
    return res.json(usage);
  } catch (error) {
    return next(error);
  }
};

exports.storageIops = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_storage_iops_usage');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});
    const usage = {
      read: {
        rate: parseFloat(out.read_rate) || 0,
        trend: parseFloat(out.read_trend) || 0,
        chart: JSON.parse(out.read_chart) || [],
      },
      write: {
        rate: parseFloat(out.write_rate) || 0,
        trend: parseFloat(out.write_trend) || 0,
        chart: JSON.parse(out.write_chart) || [],
      },
    };
    return res.json(usage);
  } catch (error) {
    return next(error);
  }
};

exports.storageLatency = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_storage_latency_usage');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    const readOp = JSON.parse(out.read_op) || [];
    const readLat = JSON.parse(out.read_latency) || [];
    const writeOp = JSON.parse(out.write_op) || [];
    const writeLat = JSON.parse(out.write_latency) || [];
    let readChart = [];
    let writeChart = [];

    // timestamp should match
    const rIdx = (readOp[0][0] == readLat[0][0]) ? 0 : 1;
    const wIdx = (writeOp[0][0] == writeLat[0][0]) ? 0 : 1;

    for (let i = rIdx; i < readOp.length ; i++) {
      const latency =  readLat[i - rIdx][1] / 1000000 / readOp[i][1];
      readChart.push([ readOp[i][0], latency != null ? latency : 0 ]);
    }

    for (let i = wIdx; i < writeOp.length ; i++) {
      const latency =  writeLat[i - wIdx][1] / 1000000 / writeOp[i][1];
      writeChart.push([ writeOp[i][0], latency != null ? latency : 0 ]);
    }

    const usage = {
      read: {
        rate: readChart[readChart.length - 1][1] || 0,
        trend: readChart[readChart.length - 1][1] - readChart[readChart.length - 2][1] || 0,
        chart: readChart || [],
      },
      write: {
        rate: writeChart[writeChart.length - 1][1] || 0,
        trend: writeChart[writeChart.length - 1][1] - writeChart[writeChart.length - 2][1] || 0,
        chart: writeChart || [],
      },
    };
    return res.json(usage);
  } catch (error) {
    return next(error);
  }
};

exports.opSummary = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_op_summary');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});
    const summary = {
      cpu: { total: parseInt(out.vcpu_total) || 0, used: parseInt(out.vcpu_used) || 0 },
      mem: { total: parseInt(out.memory_mb_total) || 0, used: parseInt(out.memory_mb_used) || 0 },
      storage: { total: parseInt(out.storage_bytes_total) || 0, used: parseInt(out.storage_bytes_used) || 0 },
    };
    return res.json(summary);
  } catch (error) {
    return next(error);
  }
};

exports.infraSummary = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_infra_summary');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});
    const summary = {
      role: {
        total: parseInt(out.role_total),
        summary: {
          control: parseInt(out.role_control) || 0,
          compute: parseInt(out.role_compute) || 0,
          storage: parseInt(out.role_storage) || 0,
        },
      },
      vm: {
        total: parseInt(out.vm_total),
        summary: {
          running: parseInt(out.vm_running) || 0,
          stopped: parseInt(out.vm_stopped) || 0,
          suspended: parseInt(out.vm_suspended) || 0,
          paused: parseInt(out.vm_paused) || 0,
          error: parseInt(out.vm_error) || 0,
        },
      },
    };
    return res.json(summary);
  } catch (error) {
    return next(error);
  }
};

async function fetchHostChart(id, host, usage, type, factor = 1) {
  let result = [];
  for (let i = 0; i < host.length ; i++) {
    // skip duplicate
    const found = result.some(function (el) {
      return el.id === id[i];
    });
    if (found)
      continue;

    const chart = await new HexSdk().run(`stats_host_chart ${id[i]} ${type}`);
    const cdata = chart.split('\n').reduce(function(c, pair) {
       pair = pair.split('=');
       return c[pair[0]] = pair[1], c;
    }, {});
    result.push({
      id: id[i],
      name: host[i],
      usage: usage[i] / factor,
      chart: JSON.parse(cdata.chart),
    });
  }
  return result;
}

exports.toptenHostCpu = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_topten_host cpu');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    const cpuHost = JSON.parse(out.cpu_host);
    const cpuUsage = JSON.parse(out.cpu_usage);

    let cpuTbl = await fetchHostChart(cpuHost, cpuHost, cpuUsage, 'cpu');

    return res.json(cpuTbl);
  } catch (error) {
    return next(error);
  }
};

exports.toptenHostMem = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_topten_host mem');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    const memHost = JSON.parse(out.mem_host);
    const memUsage = JSON.parse(out.mem_usage);

    let memTbl = await fetchHostChart(memHost, memHost, memUsage, 'mem');

    return res.json(memTbl);
  } catch (error) {
    return next(error);
  }
};

exports.toptenHostDisk = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_topten_host disk');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    const diskHost = JSON.parse(out.disk_host);
    const diskUsage = JSON.parse(out.disk_usage);

    let diskTbl = await fetchHostChart(diskHost, diskHost, diskUsage, 'disk');

    return res.json(diskTbl);
  } catch (error) {
    return next(error);
  }
};

exports.toptenHostNetin = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_topten_host netin');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    const inHost = JSON.parse(out.in_host);
    const inUsage = JSON.parse(out.in_usage);

    let inTbl = await fetchHostChart(inHost, inHost, inUsage, 'netin');

    return res.json(inTbl);
  } catch (error) {
    return next(error);
  }
};

exports.toptenHostNetout = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_topten_host netout');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    const outHost = JSON.parse(out.out_host);
    const outUsage = JSON.parse(out.out_usage);

    let outTbl = await fetchHostChart(outHost, outHost, outUsage, 'netout');

    return res.json(outTbl);
  } catch (error) {
    return next(error);
  }
};

async function fetchVmChart(id, vm_name, usage, type, device, factor = 1) {
  let result = [];
  for (let i = 0; i < id.length ; i++) {
    // skip duplicate
    const found = result.some(function (el) {
      return el.id === id[i];
    });
    if (found)
      continue;

    const chart = await new HexSdk().run(`stats_vm_chart ${id[i]} ${type} ${device[i]}`);
    const cdata = chart.split('\n').reduce(function(c, pair) {
       pair = pair.split('=');
       return c[pair[0]] = pair[1], c;
    }, {});
    result.push({
      id: id[i],
      name: device == 'na' ? vm_name[i] : vm_name[i] + ': ' + device[i],
      usage: usage[i] / factor,
      chart: JSON.parse(cdata.chart),
    });
  }
  return result;
}

exports.toptenVmCpu = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_topten_vm cpu');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    const id = JSON.parse(out.rcs_id);
    const name = JSON.parse(out.vm_name);
    const usage = JSON.parse(out.usage);
    let table = await fetchVmChart(id, name, usage, 'cpu', 'na');

    return res.json(table);
  } catch (error) {
    return next(error);
  }
};

exports.toptenVmMem = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_topten_vm mem');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    const id = JSON.parse(out.rcs_id);
    const name = JSON.parse(out.vm_name);
    const usage = JSON.parse(out.usage);
    let table = await fetchVmChart(id, name, usage, 'mem', 'na');

    return res.json(table);
  } catch (error) {
    return next(error);
  }
};

exports.toptenVmDiskr = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_topten_vm diskr');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    const id = JSON.parse(out.rcs_id);
    const name = JSON.parse(out.vm_name);
    const usage = JSON.parse(out.usage);
    const device = JSON.parse(out.device);
    let table = await fetchVmChart(id, name, usage, 'diskr', device);

    return res.json(table);
  } catch (error) {
    return next(error);
  }
};

exports.toptenVmDiskw = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_topten_vm diskw');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    const id = JSON.parse(out.rcs_id);
    const name = JSON.parse(out.vm_name);
    const usage = JSON.parse(out.usage);
    const device = JSON.parse(out.device);
    let table = await fetchVmChart(id, name, usage, 'diskw', device);

    return res.json(table);
  } catch (error) {
    return next(error);
  }
};

exports.toptenVmNetin = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_topten_vm netin');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    const id = JSON.parse(out.rcs_id);
    const name = JSON.parse(out.vm_name);
    const usage = JSON.parse(out.usage);
    const device = JSON.parse(out.device);
    let table = await fetchVmChart(id, name, usage, 'netin', device);

    return res.json(table);
  } catch (error) {
    return next(error);
  }
};

exports.toptenVmNetout = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('stats_topten_vm netout');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    const id = JSON.parse(out.rcs_id);
    const name = JSON.parse(out.vm_name);
    const usage = JSON.parse(out.usage);
    const device = JSON.parse(out.device);
    let table = await fetchVmChart(id, name, usage, 'netout', device);

    return res.json(table);
  } catch (error) {
    return next(error);
  }
};

exports.health = async (req, res, next) => {
  try {
    const info = await new HexConfig().run('sdk_health ' + req.params.comp);
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    return res.json(out);
  } catch (error) {
    return next(error);
  }
};