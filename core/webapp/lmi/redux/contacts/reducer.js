import fakeData from "../../containers/Contacts/fakeData";
import contactActions from "./actions";

const contacts = new fakeData(10).getAll();

const initState = {
	contacts,
	seectedId: contacts[0].id,
	editView: false
};

export default function contactReducer(state = initState, action) {
	switch (action.type) {
		case contactActions.CHANGE_CONTACT:
			return { ...state, seectedId: action.id, editView: false };
		case contactActions.ADD_CONTACT:
			return {
				...state,
				contacts: action.contacts,
				seectedId: action.selectedId,
				editView: true
			};
		case contactActions.EDIT_CONTACT:
			return { ...state, contacts: action.contacts };
		case contactActions.DELETE__CONTACT:
			return {
				...state,
				contacts: action.contacts,
				seectedId: action.selectedId
			};
		case contactActions.EDIT_VIEW:
			return {
				...state,
				editView: action.view
			};
		default:
			return state;
	}
}

export { contacts };
