// dashboard/reducer.js

import update from 'immutability-helper';

import * as t from './action-type.js';

// The default state
const DEFAULT_STATE = {
  widgetTitleSelected: {
    host: 'cpu',
    vm: 'cpu',
  },
  partition: {
    active: -1,
    parts: [
      { version: '', boot: '', type: '' },
      { version: '', boot: '', type: '' }
    ],
  },
  clusterUsage: {
    cpu: {
      total: 0,
      trend: 0,
      chart: {}
    },
    mem: {
      total: 0,
      trend: 0,
      chart: {}
    }
  },
  storageUsage: {
    bandwidth: {
      read: { rate: 0, trend: 0, chart: {} },
      write: { rate: 0, trend: 0, chart: {} },
    },
    iops: {
      read: { rate: 0, trend: 0, chart: {} },
      write: { rate: 0, trend: 0, chart: {} },
    },
    latency: {
      read: { rate: 0, trend: 0, chart: {} },
      write: { rate: 0, trend: 0, chart: {} },
    },
  },
  opSummary: {
    cpu: { total: 0, used: 0 },
    mem: { total: 0, used: 0 },
    storage: { total: 0, used: 0 },
  },
  infraSummary: {
    role: {
      total: 0,
      summary: { control: 0, compute: 0, storage: 0 },
    },
    vm: {
      total: 0,
      summary: { running: 0, stopped: 0, suspended: 0, paused: 0, error: 0 },
    },
  },
  topten: {
    host: {
      cpu: [],
      mem: [],
      disk: [],
      netin: [],
      netout: [],
    },
    vm: {
      cpu: [],
      mem: [],
      diskr: [],
      diskw: [],
      netin: [],
      netout: [],
    },
  },
  images: {},
  instances: {},
  userInstances: [],
  exports: [],
};

// Takes care of changing the state
export default function (state = DEFAULT_STATE, action)
{
  switch (action.type) {
    case t.SET_WIDGET_TITLE_SEL:
      return update(state,
        {widgetTitleSelected: {[action.selCat]: {$set: action.selId}}}
      );
    case t.PARTITION_SAVE:
      return update(state,
        {partition: {$set: action.partition}}
      );
    case t.CLUSTER_USAGE_SAVE:
      return update(state,
        {clusterUsage: {[action.cat]: {$set: action.usage}}}
      );
    case t.STORAGE_USAGE_SAVE:
      return update(state,
        {storageUsage: {[action.cat]: {$set: action.usage}}}
      );
    case t.OP_SUMMARY_SAVE:
      return update(state,
        {opSummary: {$set: action.summary}}
      );
    case t.INFRA_SUMMARY_SAVE:
      return update(state,
        {infraSummary: {$set: action.summary}}
      );
    case t.TOPTEN_SAVE:
      return update(state,
        {topten: {[action.cat]: {[action.sub]: {$set: action.topten}}}}
      );
    case t.IMAGES_SAVE:
      return update(state,
        {images: {$set: action.images}}
      );
    case t.INSTANCES_SAVE:
      return update(state,
        {instances: {$set: action.instances}}
      );
    case t.USER_INSTANCES_SAVE:
      return update(state,
        {userInstances: {$set: action.userInstances}}
      );
    case t.EXPORTS_SAVE:
      return update(state,
        {exports: {$set: action.exports}}
      );
    default:
      return state;
  }
}