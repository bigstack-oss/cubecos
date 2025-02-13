import { all, takeEvery, fork } from 'redux-saga/effects';
import actions from './actions';

export function* filterAction() {
  yield takeEvery(actions.FILTER_ATTRIBUTE, function*() {});
}
export default function* rootSaga() {
  yield all([fork(filterAction)]);
}
