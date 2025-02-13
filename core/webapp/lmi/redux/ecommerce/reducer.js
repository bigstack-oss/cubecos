import clone from "clone";
import actions from "./actions";

const initState = {
	loadingInitData: false,
	view: "gridView",
	viewTopbarCart: false,
	productQuantity: [],
	products: {}
};
export default (state = initState, action) => {
	switch (action.type) {
		case actions.INIT_DATA:
			return {
				...state,
				productQuantity: action.payload.productQuantity,
				products: action.payload.products,
				loadingInitData: true
			};
		case actions.CHANGE_VIEW:
			return {
				...state,
				view: action.view
			};
		case actions.VIEW_TOPBAR_CART:
			return { ...state, viewTopbarCart: action.viewTopbarCart };

		case actions.UPDATE_DATA:
			return {
				...state,
				products: clone(action.products),
				productQuantity: clone(action.productQuantity)
			};
		default:
			return state;
	}
};
