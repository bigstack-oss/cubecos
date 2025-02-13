// logs/action.js

import * as t from './action-type';

export const fetchAlertSummary = () => ({
  type: t.FETCH_ALERT_SUMMARY,
});

export const fetchSystemAlert = () => ({
  type: t.FETCH_SYSTEM_ALERT,
});

export const fetchHostAlert = () => ({
  type: t.FETCH_HOST_ALERT,
});

export const fetchInstanceAlert = (tenant) => ({
  type: t.FETCH_INSTANCE_ALERT,
  tenant
});

export const fetchAdminResp = () => ({
  type: t.FETCH_ADMIN_RESP,
});

export const fetchInstanceResp = (tenant) => ({
  type: t.FETCH_INSTANCE_RESP,
  tenant
});

export const setAdminRespType = (respType) => ({
  type: t.ADMIN_RESP_TYPE_SET,
  respType
});

export const setInstanceRespType = (respType) => ({
  type: t.INSTANCE_RESP_TYPE_SET,
  respType
});

export const updateAdminResp = (rec, values) => {
  const action = rec.name ? 'update' : 'add';
  const name = `admin-notify`
  let response = {
    action,
    name,
    enabled: values.enabled,
    type: values.type,
    topic: 'events',
    match: `"severity" == 'W' OR "severity" == 'E' OR "severity" == 'C'`,
  }
  if (values.type == 'slack') {
    response.url = values.adminUrl;
    response.channel = values.adminChannel;
  }
  else if (values.type == 'email') {
    response.host = values.adminHost;
    response.port = values.adminPort;
    response.username = values.adminUsername;
    response.password = values.adminPassword;
    response.from = values.adminFrom;
    response.to = values.adminTo;
  }

  return ({ type: t.UPDATE_ADMIN_RESP, response })
};

export const updateInstanceResp = (rec, values, tenant, role) => {

  const action = rec.name ? 'update' : 'add';
  const name = `instance-${tenant}-notify`
  let match;
  if (role == 'admin')
    match = `"severity" == 'W' OR "severity" == 'C'`;
  else
    match = `"tenant" == '${tenant}' AND ("severity" == 'W' OR "severity" == 'C')`;

  let response = {
    action,
    name,
    enabled: values.enabled,
    type: values.type,
    topic: 'instance-events',
    match,
  }
  if (values.type == 'slack') {
    response.url = values.instanceUrl;
    response.channel = values.instanceChannel;
  }
  else if (values.type == 'email') {
    response.host = values.instanceHost;
    response.port = values.instancePort;
    response.username = values.instanceUsername;
    response.password = values.instancePassword;
    response.from = values.instanceFrom;
    response.to = values.instanceTo;
  }

  return ({ type: t.UPDATE_INSTANCE_RESP, response, tenant });
};
