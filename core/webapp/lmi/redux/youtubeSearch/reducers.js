import actions from "./actions";

const initState = {
	searcText: "React JS Conf",
	total_count: 0,
	result: [],
	loading: false,
	error: false
};

export default function reducer(state = initState, action) {
	switch (action.type) {
		case actions.YOUTUBE_SEARCH:
			return { ...state, loading: true, searcText: action.payload.searcText };

		case actions.YOUTUBE_SUCCESS_RESULT:
			return {
				...state,
				result: action.result,
				total_count: action.total_count,
				nextPageToken: action.nextPageToken,
				prevPageToken: action.prevPageToken,
				loading: false,
				error: false
			};
		case actions.YOUTUBE_ERROR_RESULT:
			return {
				...state,
				result: [],
				loading: false,
				error: false
			};
		default:
			return state;
	}
}
