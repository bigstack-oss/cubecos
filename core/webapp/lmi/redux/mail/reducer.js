import allMails from "../../containers/Mail/fakeData";
import actions from "./actions";

const initState = {
	allMails,
	tag: undefined,
	selectedMail: -1,
	filterAttr: { bucket: "Inbox" },
	composeMail: false,
	replyMail: false,
	searchString: ""
};

export default function mailReducer(state = initState, action) {
	switch (action.type) {
		case actions.FILTER_ATTRIBUTE:
			return {
				...state,
				filterAttr: { ...action.filterAttr },
				selectedMail: -1,
				composeMail: false,
				replyMail: false
			};
		case actions.SELECTED_MAIL:
			return {
				...state,
				selectedMail: action.selectedMail,
				allMails: action.allMails,
				replyMail: false
			};
		case actions.COMPOSE_MAIL:
			return { ...state, composeMail: action.composeMail, replyMail: false };
		case actions.REPLY_MAIL:
			return { ...state, replyMail: action.replyMail };
		case actions.SEARCH_STRING:
			return { ...state, searchString: action.searchString };
		default:
			return state;
	}
}
