import React, { Component } from "react";
import { connect } from "react-redux";
import Button from "../../components/uielements/button";
import notification from "../../components/notification";
import actions from "../../redux/chat/actions";
import { ComposeMessageWrapper, Textarea } from "./message.style";
const { sendMessage } = actions;

class ComposeMessage extends Component {
	state = {
		value: ""
	};
	componentWillReceiveProps(nextProps) {
		this.setState({ value: "" });
	}
	onChange = event => {
		this.setState({ value: event.target.value });
	};
	onKeyPress = event => {
		if (event.key === "Enter") {
			event.preventDefault();
			const { value } = this.state;
			if (value && value.length > 0) {
				this.props.sendMessage(value);
				this.setState({ value: "" });
			} else {
				notification("error", "Please type something");
			}
		}
	};
	render() {
		const { value } = this.state;
		return (
			<ComposeMessageWrapper>
				<Textarea
					autosize={this.props.autosize}
					value={value}
					onChange={this.onChange}
					onKeyPress={this.onKeyPress}
					placeholder="Type your message"
				/>
				{this.props.showButton ? (
					<div className="sendMessageButton">
						<Button type="primary" onClick={this.sendMessage}>
							Send Message
						</Button>
					</div>
				) : (
					""
				)}
			</ComposeMessageWrapper>
		);
	}
}

function mapStateToProps(state) {
	const { selectedChatRoom, openCompose } = state.Chat;
	return { selectedChatRoom, openCompose };
}
export default connect(mapStateToProps, {
	sendMessage
})(ComposeMessage);
