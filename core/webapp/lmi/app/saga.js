// saga.js

import { all } from 'redux-saga/effects';

// import cube app modules
import basic from './basic';
import dashboard from './dashboard';
import logs from './logs';
import mgmt from './mgmt';

export default function* rootSaga(getState) {
  yield all([
    basic.saga(),
    dashboard.saga(),
    logs.saga(),
    mgmt.saga(),
  ]);
}