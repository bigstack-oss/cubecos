import fakeData from "../../containers/Todo/fakeData";
import todoActions from "./actions";

const colors = ["#7ED321", "#de1b1b", "#511E78", "#ff9009", "#42a5f5"];
const todos = new fakeData(5, colors.length).getAll();

const initState = {
	todos,
	colors
};

export default function todoReducer(state = initState, action) {
	const todos = state.todos;
	const newtodos = [];
	switch (action.type) {
		case todoActions.CHANGE_TODO:
			return { ...state, todos: action.todos };
		case todoActions.ALL_COMPLETED:
			todos.forEach(todo => {
				todo.completed = true;
				newtodos.push(todo);
			});
			return { ...state, todos: newtodos };
		case todoActions.DELETE_COMPLETED:
			todos.forEach(todo => {
				if (todo.completed !== true) {
					newtodos.push(todo);
				}
			});
			return { ...state, todos: newtodos };
		default:
			return state;
	}
}
