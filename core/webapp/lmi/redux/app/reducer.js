import { getDefaultPath } from "../../helpers/urlSync";
import actions, { getView } from "./actions";

const preKeys = []; //getDefaultPath();
const initState = {
	collapsed: false,
	view: getView(0),
	height: 0,
	openDrawer: false,
	openKeys: preKeys,
	current: preKeys
};
export default function appReducer(state = initState, action) {
	const { collapsed, openDrawer, view } = state;
	switch (action.type) {
		case actions.COLLPSE_CHANGE:
			return { ...state, collapsed: !collapsed };
		case actions.COLLPSE_OPEN_DRAWER:
			return { ...state, openDrawer: !openDrawer };
		case actions.TOGGLE_ALL:
			if (view !== action.view || action.height !== state.height) {
				const height = action.height ? action.height : state.height;
				return {
					...state,
					collapsed: action.collapsed,
					view: action.view,
					height: height
				};
			}
			break;
		case actions.CHANGE_OPEN_KEYS:
			return { ...state, openKeys: action.openKeys };
		case actions.CHANGE_CURRENT:
			return { ...state, current: action.current };
		default:
			return state;
	}
	return state;
}
