// logs/saga.js

import { all, takeEvery, call, fork, put } from 'redux-saga/effects';
import { notification } from '../../components';

import * as t from './action-type';

function* onFetchAlertSummary() {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/logs/alert-summary`);
    const summary = yield call([resp, resp.json])
    yield put({ type: t.ALERT_SUMMARY_SAVE, summary });
  } catch (e) {
    return;
  }
}

function* onFetchSystemAlert() {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/logs/system-alerts`);
    const alerts = yield call([resp, resp.json])
    yield put({ type: t.SYSTEM_ALERT_SAVE, alerts });
  } catch (e) {
    return;
  }
}

function* onFetchHostAlert() {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/logs/host-alerts`);
    const alerts = yield call([resp, resp.json])
    yield put({ type: t.HOST_ALERT_SAVE, alerts });
  } catch (e) {
    return;
  }
}

function* onFetchInstanceAlert({ tenant }) {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/logs/instance-alerts/${tenant}`);
    const alerts = yield call([resp, resp.json])
    yield put({ type: t.INSTANCE_ALERT_SAVE, alerts });
  } catch (e) {
    return;
  }
}

function* onFetchAdminResp() {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/logs/responses/admin`);
    const resps = yield call([resp, resp.json])
    yield put({ type: t.ADMIN_RESP_SAVE, resps });
  } catch (e) {
    return;
  }
}

function* onFetchInstanceResp({ tenant }) {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/logs/responses/instance/${tenant}`);
    const resps = yield call([resp, resp.json])
    yield put({ type: t.INSTANCE_RESP_SAVE, resps });
  } catch (e) {
    return;
  }
}

function* onUpdateAdminResp({ response }) {
  const params = {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(response),
  };

  const loadingResp = {
    loading: true,
    ...response
  };
  yield put({ type: t.ADMIN_RESP_SET, response: loadingResp });
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/logs/responses/admin`, params);
    if (parseInt(resp.status) == 200) {
      notification('success', 'Applying policy changes', 'Policy changes were successfully applied');
      const resps = yield call([resp, resp.json]);
    }
    else {
      notification('error', 'Applying policy changes', 'Please verify input data and try again');
    }
  } catch (e) {}
  yield put({ type: t.ADMIN_RESP_SET, response });
}

function* onUpdateInstanceResp({ response, tenant }) {
  const params = {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(response),
  };

  const loadingResp = {
    loading: true,
    ...response
  };
  yield put({ type: t.INSTANCE_RESP_SET, response: loadingResp });
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/logs/responses/instance/${tenant}`, params);
    if (parseInt(resp.status) == 200) {
      notification('success', 'Applying policy changes', 'Policy changes were successfully applied');
      const resps = yield call([resp, resp.json]);
    }
    else {
      notification('error', 'Applying policy changes', 'Please verify input data and try again');
    }
  } catch (e) {}
  yield put({ type: t.INSTANCE_RESP_SET, response });
}

export default function* saga() {
  yield takeEvery(t.FETCH_ALERT_SUMMARY, onFetchAlertSummary);
  yield takeEvery(t.FETCH_SYSTEM_ALERT, onFetchSystemAlert);
  yield takeEvery(t.FETCH_HOST_ALERT, onFetchHostAlert);
  yield takeEvery(t.FETCH_INSTANCE_ALERT, onFetchInstanceAlert);
  yield takeEvery(t.FETCH_ADMIN_RESP, onFetchAdminResp);
  yield takeEvery(t.FETCH_INSTANCE_RESP, onFetchInstanceResp);
  yield takeEvery(t.UPDATE_ADMIN_RESP, onUpdateAdminResp);
  yield takeEvery(t.UPDATE_INSTANCE_RESP, onUpdateInstanceResp);
}