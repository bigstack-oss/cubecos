// basic/saga.js

import Router from 'next/router';
import { all, takeEvery, call, fork, put } from 'redux-saga/effects';
import { removeCookie } from '../../helpers/session';
import * as t from './action-type';

function* onLogout() {
  try {
    const resp = yield call(fetch, `${window.cluster['local'].API_URL}/v1/auth/logout`);
    yield put({ type: t.SET_USERINFO, userInfo: {} });
    yield put({ type: t.SET_AUTH, authenticated: false });
    removeCookie('connect.sid');
    // using window.location.href for forcing page reload and cleaning up redux stats
    window.location.href = '/login';
    //yield call(Router.push, '/login');
  } catch (e) {
    return;
  }
}

function* onProfile() {
  try {
    const resp = yield call(fetch, `${window.cluster['local'].API_URL}/v1/auth/profile`);
    const userInfo = yield call([resp, resp.json])
    if (userInfo.username) {
      yield put({ type: t.SET_USERINFO, userInfo });
      yield put({ type: t.SET_AUTH, authenticated: true });
      if (userInfo.role == 'admin')
        yield call(Router.push, '/dashboard');
      else if (userInfo.role == '_member_')
        yield call(Router.push, '/logs/alert');
      else
        yield call(Router.push, '/dashboard/application');
    }
  } catch (e) {
    return;
  }
}

function* onSelectCluster({cluster}) {
  try {
    yield put({ type: t.SET_CLUSTER, cluster });
  } catch (e) {
    return;
  }
}

export default function* saga() {
  yield takeEvery(t.LOGOUT, onLogout);
  yield takeEvery(t.PROFILE, onProfile);
  yield takeEvery(t.SELECT_CLUSTER, onSelectCluster);
}