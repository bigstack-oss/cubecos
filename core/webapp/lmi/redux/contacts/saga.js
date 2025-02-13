import { all, takeEvery, fork } from 'redux-saga/effects';
import actions from './actions';

export function* addContact() {
  yield takeEvery(actions.ADD_CONTACT, function*() {});
}
export function* editContact() {
  yield takeEvery(actions.EDIT_CONTACT, function*() {});
}
export function* deleteContact() {
  yield takeEvery(actions.DELETE__CONTACT, function*() {});
}
export default function* rootSaga() {
  yield all([fork(addContact), fork(editContact), fork(deleteContact)]);
}
