const actions = {
	GET_INVOICE: "GET_INVOICE",
	UPDATE_INVOICE: "UPDATE_INVOICE",
	UPDATE_INVOICE_SAGA: "UPDATE_INVOICE_SAGA",
	SELECT_CURRENT_INVOICE: "SELECT_CURRENT_INVOICE",
	TOGGLE_VIEW: "INVOICE_TOGGLE_VIEW",
	UPDATE_EDIT_INVOICE: "INVOICE_UPDATE_EDIT_INVOICE",
	initData: () => {
		return { type: actions.GET_INVOICE };
	},
	deleteInvoice: selected => {
		return (dispatch, getState) => {
			const invoices = getState().Invoices.invoices;
			const newInvoices = [];
			invoices.forEach(invoice => {
				const selectedIndex = selected.indexOf(invoice.key);
				if (selectedIndex === -1) {
					newInvoices.push(invoice);
				}
			});
			dispatch({
				type: actions.UPDATE_INVOICE_SAGA,
				invoices: newInvoices
			});
		};
	},
	updateInvoice: invoice => {
		return (dispatch, getState) => {
			const invoices = getState().Invoices.invoices;
			const index = invoices.map(inv => inv.id).indexOf(invoice.id);
			if (index === -1) {
				invoices.push(invoice);
			} else {
				invoices[index] = invoice;
			}
			dispatch({
				type: actions.UPDATE_INVOICE_SAGA,
				invoices,
				invoice
			});
		};
	},
	selectCurrentInvoice: id => ({ type: actions.SELECT_CURRENT_INVOICE, id }),
	toggleView: view => ({ type: actions.TOGGLE_VIEW, view }),
	editInvoice: invoice => ({ type: actions.UPDATE_EDIT_INVOICE, invoice })
};
export default actions;
