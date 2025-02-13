import React, { Component } from "react";
import { connect } from "react-redux";
import Modal from "../../components/feedback/modal";
import InputName from "../../components/chat/inputName";
import ChatRooms from "./chatrooms";
import Messages from "./messages";
import ComposeMessage from "./composMessage";
import ViewProfile from "../../components/chat/viewProfile";
import Loader from "../../components/utility/loader";
import {
	ChatWindow,
	ChatBox,
	Button,
	MessageDialog,
	ToggleViewProfile
} from "./message.style";

import actions from "../../redux/chat/actions";

class MobileView extends Component {
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
			viewProfile,
			toggleCompose,
			openCompose,
			setComposedId,
			selectedChatRoom,
			toggleViewProfile,
			mobileActiveList,
			mobileActiveProfile,
			toggleMobileList,
			toggleMobileProfile,
			className
		} = this.props;
		if (loading) {
			return <Loader />;
		}
		let CurrentView = <Loader />;
		if (mobileActiveList) {
			CurrentView = (
				<div>
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
					<ChatRooms toggleMobileList={toggleMobileList} />
				</div>
			);
		} else if (mobileActiveProfile) {
			CurrentView = (
				<ViewProfile
					viewProfile={viewProfile}
					toggleViewProfile={toggleViewProfile}
					toggleMobileProfile={toggleMobileProfile}
				/>
			);
		} else {
			CurrentView = (
				<ChatBox className="ChatBox">
					<ToggleViewProfile>
						<Button onClick={() => toggleMobileList(true)}>
							<i className="ion-chevron-left" />
						</Button>
						<span
							onClick={() => {
								toggleViewProfile(selectedChatRoom.otherUserInfo);
								toggleMobileProfile(true);
							}}
						>
							{selectedChatRoom.otherUserInfo.name}
						</span>
					</ToggleViewProfile>

					<Messages toggleMobileProfile={toggleMobileProfile} />
					<ComposeMessage
						InputProps={{
							disableUnderline: true
						}}
					/>
				</ChatBox>
			);
		}
		return <ChatWindow className="ChatWindow">{CurrentView}</ChatWindow>;
	}
}
function mapStateToProps(state) {
	return state.Chat;
}
export default connect(mapStateToProps, actions)(MobileView);
