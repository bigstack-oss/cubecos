import notes from "../../containers/Notes/fakeData";
import actions from "./actions";
const colors = ["#7ED321", "#de1b1b", "#511E78", "#ff9009", "#42a5f5"];
const initState = {
	notes,
	colors,
	selectedId: notes[0].id,
	seectedColor: notes[0].color
};

export default function noteReducer(state = initState, action) {
	switch (action.type) {
		case actions.CHANGE_NOTE:
			return {
				...state,
				selectedId: action.selectedId,
				seectedColor: action.seectedColor
			};
		case actions.ADD_NOTE:
			return {
				...state,
				selectedId: action.selectedId,
				notes: action.notes
			};
		case actions.EDIT_NOTE:
			return {
				...state,
				notes: action.notes
			};
		case actions.DELETE_NOTE:
			return {
				...state,
				selectedId: action.selectedId,
				notes: action.notes
			};
		case actions.CHANGE_COLOR:
			return {
				...state,
				seectedColor: action.seectedColor,
				notes: action.notes
			};
		default:
			return state;
	}
}
