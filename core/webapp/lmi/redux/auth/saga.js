import { all, takeEvery, put, call, fork } from 'redux-saga/effects';
import { setCookie, removeCookie } from '../../helpers/session';
import { notification } from '../../components';
import JwtAuthentication from '../../helpers/jwtAuthentication';
import actions from './actions';

const fakeApiCall = true;
export function* loginRequest() {
  yield takeEvery(actions.LOGIN_REQUEST, function*({ payload }) {
    if (fakeApiCall) {
      yield put({
        type: actions.LOGIN_SUCCESS,
        token: 'secret token',
        profile: 'Profile',
      });
    } else {
      yield put({ type: actions.LOGIN_ERROR });
    }
  });
}

export function* jwtLoginRequest() {
  yield takeEvery(actions.JWT_LOGIN_REQUEST, function*({ payload }) {
    const result = yield call(JwtAuthentication.login, payload.userInfo);
    if (result.error) {
      notification('error', result.error);
      yield put({ type: actions.LOGIN_ERROR });
    } else {
      payload.history.push('/dashboard');
      yield put({
        type: actions.LOGIN_SUCCESS,
        token: result.token,
        profile: result.profile,
      });
    }
  });
}

export function* loginSuccess() {
  yield takeEvery(actions.LOGIN_SUCCESS, function*(payload) {
    setCookie('login_saga', payload.token);
    yield setCookie('id_token', payload.token);
  });
}

export function* loginError() {
  yield takeEvery(actions.LOGIN_ERROR, function*() {});
}

export function* logout() {
  yield takeEvery(actions.LOGOUT, function*() {
    removeCookie('id_token');
  });
}
export default function* rootSaga() {
  yield all([
    fork(loginRequest),
    fork(jwtLoginRequest),
    fork(loginSuccess),
    fork(loginError),
    fork(logout),
  ]);
}
