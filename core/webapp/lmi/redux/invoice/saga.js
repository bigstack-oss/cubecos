import { all, takeEvery, put } from 'redux-saga/effects';
import { localDataName, createDemoData } from '../../containers/Invoice/config';
import actions from './actions';

export function* getInvoice() {
	console.log('called 3');
	yield put({
		type: actions.UPDATE_INVOICE,
		invoices: createDemoData(),
	});
}
export function* updateInvoiceSaga({ invoices, invoice }) {
	// yield localStorage.setItem(localDataName, JSON.stringify(invoices));
	yield put({
		type: actions.UPDATE_INVOICE,
		invoices,
		invoice,
	});
}
export default function* rootSaga() {
	yield all([
		yield takeEvery(actions.GET_INVOICE, getInvoice),
		yield takeEvery(actions.UPDATE_INVOICE_SAGA, updateInvoiceSaga),
	]);
}
