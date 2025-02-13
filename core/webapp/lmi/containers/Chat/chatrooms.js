import React, { Component } from "react";
import { connect } from "react-redux";
// import Input from '../../components/uielements/input';
import Scrollbars from "../../components/utility/customScrollBar.js";
import Button from "../../components/uielements/button";
import actions from "../../redux/chat/actions";
import { timeDifference } from "../../helpers/utility";
import HelperText from "../../components/utility/helper-text";
import {
	UserListsWrapper,
	UserLists,
	SidebarSearchBox,
	Input,
	ChatSidebar
} from "./message.style";

class ChatRooms extends Component {
	state = {
		value: "",
		searchedChatRooms: this.props.chatRooms
	};
	componentWillReceiveProps(nextProps) {
		this.setState({ value: "", searchedChatRooms: nextProps.chatRooms });
	}
	onSearch = event => {
		const value = event.target.value;
		const searchedChatRooms = value ? [] : this.props.chatRooms;
		if (value) {
			this.props.chatRooms.forEach(chatRoom => {
				if (
					chatRoom.otherUserInfo.name
						.toLowerCase()
						.includes(value.toLowerCase())
				) {
					searchedChatRooms.push(chatRoom);
				}
			});
		}
		this.setState({ value, searchedChatRooms });
	};
	render() {
		const {
			setSelectedChatroom,
			selectedChatRoom,
			toggleMobileList,
			toggleCompose
		} = this.props;
		const { value, searchedChatRooms } = this.state;
		const singleChatRoom = (chatRoom, index) => {
			const { otherUserInfo, lastMessage, lastMessageTime } = chatRoom;
			const { name, profileImageUrl } = otherUserInfo;
			const selected = selectedChatRoom.id === chatRoom.id;
			const style = {
				background: selected ? "#f7f7f7" : "rgba(0,0,0,0)"
			};
			const selectChatroom = event => {
				event.stopPropagation();
				if (!selected) {
					setSelectedChatroom(chatRoom);
				}
				if (toggleMobileList) {
					toggleMobileList(false);
				}
			};
			return (
				<UserLists key={index} style={style} onClick={selectChatroom}>
					<div className="userListsGravatar">
						<img
							alt="#"
							style={{ width: 45, height: 45 }}
							src={profileImageUrl}
						/>
					</div>
					<div className="userListsContent">
						<h4>{name}</h4>
						<div className="chatExcerpt">
							<p>{lastMessage}</p>
							<span className="userListsTime">
								{timeDifference(lastMessageTime)}
							</span>
						</div>
					</div>
				</UserLists>
			);
		};
		return (
			<ChatSidebar>
				<SidebarSearchBox>
					<Input
						value={value}
						onChange={this.onSearch}
						placeholder="Search Contact"
					/>
				</SidebarSearchBox>
				<UserListsWrapper>
					<Scrollbars>
						{searchedChatRooms.length === 0 ? (
							<HelperText
								text="No Conversation"
								className="messageHelperText"
							/>
						) : (
							searchedChatRooms.map(singleChatRoom)
						)}
					</Scrollbars>
				</UserListsWrapper>
				<div className="ComposeMessageButton">
					<Button onClick={toggleCompose} type="primary">
						Compose
					</Button>
				</div>
			</ChatSidebar>
		);
	}
}
function mapStateToProps(state) {
	const { chatRooms, openCompose, selectedChatRoom } = state.Chat;
	const { view } = state.App;
	return {
		chatRooms: chatRooms.filter(chatRoom => chatRoom.lastMessageTime > 0),
		selectedChatRoom: view === "DesktopView" ? selectedChatRoom : {},
		openCompose
	};
}
export default connect(mapStateToProps, actions)(ChatRooms);
