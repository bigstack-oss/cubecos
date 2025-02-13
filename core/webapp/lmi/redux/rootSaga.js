import { all } from 'redux-saga/effects';
import authSagas from './auth/saga';
import noteSagas from './notes/saga';
import mailSagas from './mail/saga';
import todoSagas from './todos/saga';
import invoicesSagas from './invoice/saga';
import contactSagas from './contacts/saga';
import youtubeSearchSagas from './youtubeSearch/sagas';
import githubSearchSagas from './githubSearch/sagas';
import chatSagas from './chat/sagas';
import ecommerceSaga from './ecommerce/saga';

export default function* rootSaga(getState) {
	yield all([
		authSagas(),
		noteSagas(),
		mailSagas(),
		todoSagas(),
		contactSagas(),
		youtubeSearchSagas(),
		githubSearchSagas(),
		ecommerceSaga(),
		chatSagas(),
		invoicesSagas(),
	]);
}
