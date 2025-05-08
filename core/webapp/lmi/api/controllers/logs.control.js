// api/controllers/stats.control.js

const httpStatus = require('http-status');
const yaml = require('js-yaml');
const fs = require('fs');

const { HexSdk } = require('../services/hex-cmds');
const logger = require('../../config-server/logger');

const parseCount = (value) => {
  return value.length ? parseInt(value) : 0;
}

/**
 * Returns alert summary
 * @public
 */
exports.alertSummary = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('logs_alert_summary');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    let summary = {
      date: parseInt(out.date),
      system: {
        info: parseCount(out.system_I),
        warn: parseCount(out.system_W),
        crit: parseCount(out.system_C),
      },
      host: {
        info: parseCount(out.host_I),
        warn: parseCount(out.host_W),
        crit: parseCount(out.host_C),
      },
      instance: {
        info: parseCount(out.instance_I),
        warn: parseCount(out.instance_W),
        crit: parseCount(out.instance_C),
      },
    }

    return res.json(summary);
  } catch (error) {
    return next(error);
  }
};

/**
 * Returns system alert list
 * @public
 */
exports.systemAlerts = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('logs_system_alerts');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    const output = JSON.parse(out.events != 'null' ? out.events : '[]');

    let alerts = []
    for (var i = 0; i < output.length ; i++) {
      alerts[i] = {
        mid: i,
        date: output[i][0],
        severity: output[i][1],
        eventid: output[i][2],
        message: output[i][3],
        metadata: JSON.parse(output[i][4]),
      }
    }

    return res.json(alerts);
  } catch (error) {
    return next(error);
  }
};

/**
 * Returns host alert list
 * @public
 */
exports.hostAlerts = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('logs_host_alerts');
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    const output = JSON.parse(out.events != 'null' ? out.events : '[]');

    let alerts = []
    for (var i = 0; i < output.length ; i++) {
      alerts[i] = {
        mid: i,
        date: output[i][0],
        severity: output[i][1],
        eventid: output[i][2],
        message: output[i][3],
        metadata: JSON.parse(output[i][4]),
      }
    }

    return res.json(alerts);
  } catch (error) {
    return next(error);
  }
};

/**
 * Returns instance alert list
 * @public
 */
exports.instanceAlerts = async (req, res, next) => {
  try {
    // typeof(req.params.tid) is 'string'
    const tid = (req.params.tid && req.params.tid != 'undefined') ? req.params.tid : '';
    const info = await new HexSdk().run(`logs_instance_alerts 500 ${tid}`);
    const out = info.split('\n').reduce(function(o, pair) {
       pair = pair.split('=');
       return o[pair[0]] = pair[1], o;
    }, {});

    const output = JSON.parse(out.events != 'null' ? out.events : '[]');

    let alerts = []
    for (var i = 0; i < output.length ; i++) {
      alerts[i] = {
        date: output[i][0],
        severity: output[i][1],
        eventid: output[i][2],
        message: output[i][3],
        metadata: JSON.parse(output[i][4]),
      }
    }

    return res.json(alerts);
  } catch (error) {
    return next(error);
  }
};

/**
 * Returns alert response list
 * @public
 */
exports.responses = async (req, res, next) => {
  try {
    const policyStr = await new HexSdk().run('cube_read_policy alert_resp/alert_resp 1_0');
    const policyResps = yaml.safeLoad(policyStr);
    const resps = policyResps.responses;

    out = [];
    if (resps) {
      if (req.params.category == 'admin') {
        for (var i = 0; i < resps.length ; i++) {
          if (resps[i].topic != 'events')
            continue;
          if (resps[i].name != 'admin-notify')
            continue;
          out.push(resps[i]);
        }
      }
      else if (req.params.category == 'instance') {
        for (var i = 0; i < resps.length ; i++) {
          if (resps[i].topic != 'instance-events')
            continue;
          if (resps[i].name != `instance-${tenant}-notify`)
            continue;
          if (resps[i].match.search(`"tenant" == '${req.params.tid}'`) == -1)
            continue;
          out.push(resps[i]);
        }
      }
    }

    if (out.length == 0)
      out.push({ enabled: false });

    return res.json(out);
  } catch (error) {
    return next(error);
  }
};

/**
 * Update alert response
 * @public
 */
exports.responseUpdate = async (req, res, next) => {
  try {
    let sub;
    if (req.body.type == 'email') {
      sub = `${req.body.host} ${req.body.port} ${req.body.username} ${req.body.password} ${req.body.from} ${req.body.to}`;
    }
    else if (req.body.type == 'slack') {
      let channel = 'null';
      if (req.body.channel)
        channel = req.body.channel.length > 0 ? req.body.channel : 'null';

      sub = `${req.body.url} ${channel}`;
    }
    const info = "";
    if (info.indexOf('Policy changes were successfully applied') != -1)
      return res.status(200).json({ status: 'success' });
    else
      return res.status(400).json({ status: 'failed' });
  } catch (error) {
    return next(error);
  }
};
