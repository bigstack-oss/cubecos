// logs/reducer.js

import update from 'immutability-helper';

import * as t from './action-type.js';

// The default state
const DEFAULT_STATE = {
  summary : {
    date:0,
    system: { info: 0, warn: 0, crit:0},
    host: { info: 0, warn: 0, crit:0},
    instance: { info: 0, warn: 0, crit:0},
  },
  systemAlerts: [],
  hostAlerts: [],
  instanceAlerts: [],
  adminResps: [{enabled: false}],
  instanceResps: [{enabled: false}],
};

// Takes care of changing the state
export default function (state = DEFAULT_STATE, action)
{
  switch (action.type) {
    case t.ALERT_SUMMARY_SAVE:
      return update(state,
        {summary: {$set: action.summary}}
      );
    case t.SYSTEM_ALERT_SAVE:
      return update(state,
        {systemAlerts: {$set: action.alerts}}
      );
    case t.HOST_ALERT_SAVE:
      return update(state,
        {hostAlerts: {$set: action.alerts}}
      );
    case t.INSTANCE_ALERT_SAVE:
      return update(state,
        {instanceAlerts: {$set: action.alerts}}
      );
    case t.ADMIN_RESP_SAVE:
      return update(state,
        {adminResps: {$set: action.resps}}
      );
    case t.ADMIN_RESP_SET:
      return update(state,
        {adminResps: {[0]: {$set: action.response}}}
      );
    case t.ADMIN_RESP_TYPE_SET:
      return update(state,
        {adminResps: {[0]: {type: {$set: action.respType}}}}
      );
    case t.INSTANCE_RESP_SAVE:
      return update(state,
        {instanceResps: {$set: action.resps}}
      );
    case t.INSTANCE_RESP_SET:
      return update(state,
        {instanceResps: {[0]: {$set: action.response}}}
      );
    case t.INSTANCE_RESP_TYPE_SET:
      return update(state,
        {instanceResps: {[0]: {type: {$set: action.respType}}}}
      );
    default:
      return state;
  }
}