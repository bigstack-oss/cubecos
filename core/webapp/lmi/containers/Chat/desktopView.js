import React, { Component } from "react";
import { connect } from "react-redux";
import ChatRooms from "./chatrooms";
import Messages from "./messages";
import ComposeMessage from "./composMessage";
import ViewProfile from "../../components/chat/viewProfile";
import InputName from "../../components/chat/inputName";
import Loader from "../../components/utility/loader";
import Modal from "../../components/feedback/modal";
import {
	ChatWindow,
	ChatBox,
	ToggleViewProfile,
	MessageDialog
} from "./message.style";

import actions from "../../redux/chat/actions";

class DesktopView extends Component {
	componentDidMount() {
		const { users, userId, chatInit } = this.props;
		if (!users) {
			chatInit(userId);
		}
	}
	render() {
		const {
			loading,
			users,
			toggleCompose,
			openCompose,
			setComposedId,
			selectedChatRoom,
			viewProfile,
			toggleViewProfile,
			className
		} = this.props;
		if (loading) {
			return <Loader />;
		}
		return (
			<ChatWindow className="ChatWindow">
				<ChatRooms />
				<ChatBox style={{ height: "100%" }}>
					<Modal
						visible={openCompose}
						onCancel={toggleCompose}
						title="Compose Message"
						footer={null}
					>
						<MessageDialog>
							<h5>Starting your chat with...</h5>
							<InputName
								users={users}
								setComposedId={setComposedId}
								className={className}
							/>
							<ComposeMessage
								autosize={{ minRows: 5, maxRows: 9 }}
								showButton
								rows={8}
							/>
						</MessageDialog>
					</Modal>
					<ToggleViewProfile>
						<span
							onClick={() => toggleViewProfile(selectedChatRoom.otherUserInfo)}
						>
							{selectedChatRoom.otherUserInfo.name}
						</span>
					</ToggleViewProfile>
					<Messages />

					<ComposeMessage autosize={{ minRows: 2, maxRows: 6 }} />
				</ChatBox>
				{viewProfile !== false ? (
					<ViewProfile
						user={selectedChatRoom.otherUserInfo}
						toggleViewProfile={toggleViewProfile}
						viewProfile={viewProfile}
					/>
				) : (
					""
				)}
			</ChatWindow>
		);
	}
}
function mapStateToProps(state) {
	return state.Chat;
}
export default connect(mapStateToProps, actions)(DesktopView);
