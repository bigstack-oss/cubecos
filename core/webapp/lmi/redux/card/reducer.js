import { fakedata } from "../../containers/Ecommerce/card/config";
import cardActions from "./actions";

const cards = fakedata;

const initState = {
	cards
};

export default function cardReducer(state = initState, action) {
	switch (action.type) {
		case cardActions.CHANGE_CARDS:
			return { ...state, cards: action.cards };
		default:
			return state;
	}
}
