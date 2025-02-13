import React, { Component } from "react";
import { connect } from "react-redux";
import { Layout } from "antd";
import Input from "../../components/uielements/input";
import todoAction from "../../redux/todos/actions.js";
import TodoList from "./todoList";
import { TodoWrapper } from "./todo.style";

const {
	addTodo,
	edittodo,
	deleteTodo,
	allCompleted,
	deleteCompleted
} = todoAction;
const { Header, Content } = Layout;

class ToDo extends Component {
	constructor(props) {
		super(props);
		this.state = {
			newTodo: ""
		};
	}
	render() {
		const {
			todos,
			colors,
			addTodo,
			edittodo,
			deleteTodo,
			allCompleted,
			deleteCompleted
		} = this.props;
		return (
			<Layout style={{ background: "none" }}>
				<TodoWrapper className="isomorphicTodoComponent">
					<Header className="isoTodoHeader">
						<Input
							placeholder={"Type here for add a new todo"}
							value={this.state.newTodo}
							className="isoTodoInput"
							onChange={event => this.setState({ newTodo: event.target.value })}
							onPressEnter={event => {
								this.setState({ newTodo: "" });
								addTodo(event.target.value);
							}}
						/>
					</Header>
					<Content className="isoTodoContentBody">
						<TodoList
							todos={todos}
							deleteTodo={deleteTodo}
							edittodo={edittodo}
							colors={colors}
							allCompleted={allCompleted}
							deleteCompleted={deleteCompleted}
						/>
					</Content>
				</TodoWrapper>
			</Layout>
		);
	}
}

function mapStateToProps(state) {
	const { todos, colors } = state.Todos;
	return {
		todos,
		colors
	};
}
export default connect(mapStateToProps, {
	addTodo,
	edittodo,
	deleteTodo,
	deleteCompleted,
	allCompleted
})(ToDo);
