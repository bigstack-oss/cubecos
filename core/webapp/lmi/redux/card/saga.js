import { all, takeEvery, fork } from 'redux-saga/effects';
import actions from './actions';

export function* changedCard() {
  yield takeEvery(actions.CHANGE_CARDS, function*() {});
}
export default function* rootSaga() {
  yield all([fork(changedCard)]);
}
