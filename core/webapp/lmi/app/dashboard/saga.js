// dashboard/saga.js

import { all, takeEvery, call, fork, put } from 'redux-saga/effects';

import * as t from './action-type';

function* onFetchPartition() {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/stats/partition`);
    const partition = yield call([resp, resp.json])
    yield put({ type: t.PARTITION_SAVE, partition });
  } catch (e) {
    return;
  }
}

function* onFetchClusterUsage({ cat, api }) {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/${api}`);
    const usage = yield call([resp, resp.json])
    yield put({ type: t.CLUSTER_USAGE_SAVE, cat, usage });
  } catch (e) {
    return;
  }
}

function* onFetchStorageUsage({ cat, api }) {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/${api}`);
    const usage = yield call([resp, resp.json])
    yield put({ type: t.STORAGE_USAGE_SAVE, cat, usage });
  } catch (e) {
    return;
  }
}

function* onFetchOpSummary() {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/stats/op-summary`);
    const summary = yield call([resp, resp.json])
    yield put({ type: t.OP_SUMMARY_SAVE, summary });
  } catch (e) {
    return;
  }
}

function* onFetchInfraSummary() {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/stats/infra-summary`);
    const summary = yield call([resp, resp.json])
    yield put({ type: t.INFRA_SUMMARY_SAVE, summary });
  } catch (e) {
    return;
  }
}

function* onFetchTopten({ cat, api, sub }) {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/${api}-${sub}`);
    const topten = yield call([resp, resp.json])
    yield put({ type: t.TOPTEN_SAVE, cat, sub, topten });
  } catch (e) {
    return;
  }
}

function* onFetchImages() {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/manage/images`);
    const images = yield call([resp, resp.json])
    yield put({ type: t.IMAGES_SAVE, images });
  } catch (e) {
    return;
  }
}

function* onFetchInstances() {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/manage/instances`);
    const instances = yield call([resp, resp.json])
    yield put({ type: t.INSTANCES_SAVE, instances });
  } catch (e) {
    return;
  }
}

function* onFetchUserInstances({ username }) {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/manage/instances/${username}`);
    const userInstances = yield call([resp, resp.json])
    yield put({ type: t.USER_INSTANCES_SAVE, userInstances });
  } catch (e) {
    return;
  }
}

function* onFetchExports() {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/manage/exports`);
    const exports = yield call([resp, resp.json])
    yield put({ type: t.EXPORTS_SAVE, exports });
  } catch (e) {
    return;
  }
}

export default function* saga() {
  yield takeEvery(t.FETCH_PARTITION, onFetchPartition);
  yield takeEvery(t.FETCH_CLUSTER_USAGE, onFetchClusterUsage);
  yield takeEvery(t.FETCH_STORAGE_USAGE, onFetchStorageUsage);
  yield takeEvery(t.FETCH_OP_SUMMARY, onFetchOpSummary);
  yield takeEvery(t.FETCH_INFRA_SUMMARY, onFetchInfraSummary);
  yield takeEvery(t.FETCH_TOPTEN, onFetchTopten);
  yield takeEvery(t.FETCH_IMAGES, onFetchImages);
  yield takeEvery(t.FETCH_INSTANCES, onFetchInstances);
  yield takeEvery(t.FETCH_USER_INSTANCES, onFetchUserInstances);
  yield takeEvery(t.FETCH_EXPORTS, onFetchExports);
}