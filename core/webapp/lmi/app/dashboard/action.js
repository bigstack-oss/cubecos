// dashboard/action.js

import * as t from './action-type';

export const setWidgetTitleSel = (selCat, selId) => ({
  type: t.SET_WIDGET_TITLE_SEL,
  selCat, selId,
});

export const fetchPartition = () => ({
  type: t.FETCH_PARTITION,
});

export const fetchClusterUsage = (cat, api) => ({
  type: t.FETCH_CLUSTER_USAGE,
  cat, api,
});

export const fetchStorageUsage = (cat, api) => ({
  type: t.FETCH_STORAGE_USAGE,
  cat, api,
});

export const fetchOpSummary = () => ({
  type: t.FETCH_OP_SUMMARY,
});

export const fetchInfraSummary = () => ({
  type: t.FETCH_INFRA_SUMMARY,
});

export const fetchTopten = (cat, api, sub) => ({
  type: t.FETCH_TOPTEN,
  cat, api, sub,
});

export const fetchImages = () => ({
  type: t.FETCH_IMAGES,
});

export const fetchInstances = () => ({
  type: t.FETCH_INSTANCES,
});

export const fetchUserInstances = (username) => ({
  type: t.FETCH_USER_INSTANCES,
  username,
});

export const fetchExports = () => ({
  type: t.FETCH_EXPORTS,
});