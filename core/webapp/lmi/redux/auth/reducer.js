import Router from "next/router";
import actions from "./actions";

const initState = {
	idToken: null
};

export default function authReducer(state = initState, action) {
	switch (action.type) {
		case actions.LOGIN_SUCCESS:
			Router.replace("/dashboard");
			return { ...state, idToken: action.token };
		case actions.LOGOUT:
			Router.replace("/");
			return initState;
		default:
			return state;
	}
}
