import React, { Component } from "react";
import { connect } from "react-redux";
import { timeDifference } from "../../helpers/utility";
import { MessageSingle, MessageChatWrapper } from "./message.style";
import actions from "../../redux/chat/actions";

class Messages extends Component {
	scrollToBottom = () => {
		const messageChat = document.getElementById("messageChat");
		messageChat.scrollTop = messageChat.scrollHeight;
	};
	componentDidMount() {
		this.scrollToBottom();
	}
	componentDidUpdate() {
		this.scrollToBottom();
	}
	render() {
		const {
			user,
			userId,
			selectedChatRoom,
			messages,
			toggleViewProfile,
			toggleMobileProfile
		} = this.props;
		const renderMessage = message => {
			const isUser = userId === message.sender;
			const messageUser = isUser ? user : selectedChatRoom.otherUserInfo;
			if (isUser) {
				return (
					<MessageSingle className="loggedUser" key={message.messageTime}>
						<div className="messageContent isUser">
							<div className="messageContentText">
								<p>{message.text}</p>
							</div>
							<div className="messageTime">
								<p>{timeDifference(message.messageTime)}</p>
							</div>
						</div>
						<div className="messageGravatar">
							<img
								alt="#"
								src={messageUser.profileImageUrl}
								onClick={() => {
									toggleMobileProfile(true);
									toggleViewProfile(messageUser);
								}}
							/>
						</div>
					</MessageSingle>
				);
			} else {
				return (
					<MessageSingle key={message.messageTime}>
						<div className="messageGravatar">
							<img
								alt="#"
								src={messageUser.profileImageUrl}
								onClick={() => {
									toggleMobileProfile(true);
									toggleViewProfile(messageUser);
								}}
							/>
						</div>
						<div className="messageContent notUser">
							<div className="messageContentText">
								<p>{message.text}</p>
							</div>
							<div className="messageTime">
								<p>{timeDifference(message.messageTime)}</p>
							</div>
						</div>
					</MessageSingle>
				);
			}
		};
		return (
			<MessageChatWrapper id="messageChat">
				{messages.map(renderMessage)}
			</MessageChatWrapper>
		);
	}
}
function mapStateToProps(state) {
	const { user, userId, selectedChatRoom, messages } = state.Chat;
	return {
		user,
		userId,
		selectedChatRoom,
		messages
	};
}
export default connect(mapStateToProps, actions)(Messages);
