import clone from "clone";
import { newInvoice } from "../../containers/Invoice/config";
import actions from "./actions";

const initState = {
	invoices: [],
	initialInvoices: false,
	currentInvoice: {},
	editableInvoice: {},
	isNewInvoice: false,
	enableEditView: false
};

export default function cardReducer(state = initState, { type, ...action }) {
	switch (type) {
		case actions.UPDATE_INVOICE: {
			const currentInvoice = action.invoice
				? action.invoice
				: state.currentInvoice;
			return {
				...state,
				invoices: action.invoices,
				currentInvoice: clone(currentInvoice),
				initialInvoices: true,
				isNewInvoice: false,
				enableEditView: false
			};
		}
		case actions.SELECT_CURRENT_INVOICE: {
			const invoices = state.invoices;
			const index = invoices.map(invoice => invoice.id).indexOf(action.id);
			const isNewInvoice = index === -1;
			const currentInvoice = isNewInvoice
				? {
						id: action.id,
						number: `#${action.id}`,
						key: action.id,
						...newInvoice
				  }
				: invoices[index];
			const enableEditView = isNewInvoice;
			return {
				...state,
				currentInvoice: currentInvoice,
				editableInvoice: clone(currentInvoice),
				isNewInvoice: isNewInvoice,
				enableEditView: enableEditView
			};
		}
		case actions.TOGGLE_VIEW:
			return {
				...state,
				editableInvoice: clone(state.currentInvoice),
				enableEditView: action.view
			};
		case actions.UPDATE_EDIT_INVOICE:
			return {
				...state,
				editableInvoice: clone(action.invoice),
				enableEditView: action.view
			};
		default:
			return state;
	}
}
