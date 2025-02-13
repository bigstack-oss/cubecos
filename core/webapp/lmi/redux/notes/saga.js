import { all, takeEvery, put } from 'redux-saga/effects';
import actions from './actions';

export function* changeColor() {}
export function* addNote() {}
export function* editNote() {}
export function* deleteNote() {}
export default function* rootSaga() {
  yield all([
    takeEvery(actions.CHANGE_COLOR, changeColor),
    takeEvery(actions.ADD_NOTE, addNote),
    takeEvery(actions.EDIT_NOTE, editNote),
    takeEvery(actions.DELETE_NOTE, deleteNote)
  ]);
}
