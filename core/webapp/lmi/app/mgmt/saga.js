// mgmt/saga.js

import { all, takeEvery, call, fork, put } from 'redux-saga/effects';
import { notification } from '../../components';

import * as t from './action-type';

function* onFetchCompHealth({ comp }) {
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/stats/health/${comp}`);
    const health = yield call([resp, resp.json])
    yield put({ type: t.COMP_HEALTH_SAVE, comp, health });
  } catch (e) {
    return;
  }
}

function* onFetchLicenseStatus({ license }) {
  const LICENSE_VALID = 1;
  const LICENSE_BADHW = 253;
  const LICENSE_NOEXIST = 252;
  const LICENSE_EXPIRED = 251;
  try {
    const resp = yield call(fetch, `${window.cluster[window.env.CLUSTER].API_URL}/v1/manage/license-status`);
    const current = yield call([resp, resp.json])
    for (let i = 0; i < current.length; i++) {
      const c = current[i];

      // check if the saved license data has updates
      let hasUpdate = true;
      if (license) {
        for (let j = 0; j < license.length; j++) {
          const l = license[j];
          if (c.hostname == l.hostname && c.type == l.type && c.days == l.days)
            hasUpdate = false;
        }
      }

      if (hasUpdate) {
        switch (c.check) {
          case LICENSE_VALID:
            if (c.days <= 45)
              notification('warn', 'Notice', `${c.hostname} license will expire in ${c.days} days`);
            break;
          case LICENSE_BADHW:
            notification('warn', 'Notice', `${c.hostname} license dosen't match its hardware property`);
            break;
          case LICENSE_NOEXIST:
            notification('warn', 'Notice', `${c.hostname} license is not installed`);
            break;
          case LICENSE_EXPIRED:
            if (c.type != 'perpetual')
              notification('warn', 'Notice', `${c.hostname} ${c.type} license has expired`);
            break;
        }
      }
    }
    yield put({ type: t.LICENSE_STATUS_SAVE, license: current });
  } catch (e) {
    return;
  }
}

export default function* saga() {
  yield takeEvery(t.FETCH_COMP_HEALTH, onFetchCompHealth);
  yield takeEvery(t.FETCH_LICENSE_STATUS, onFetchLicenseStatus);
}