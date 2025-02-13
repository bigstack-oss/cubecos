import styled from 'styled-components';
import { palette } from 'styled-theme';
import Buttons from '../../components/uielements/button';
import Inputs from '../../components/uielements/input';
import { Textarea as Textareas } from '../../components/uielements/input';
import ReactDrawers from 'react-motion-drawer';

const Input = styled(Inputs)``;
const Textarea = styled(Textareas)``;
const ReactDrawer = styled(ReactDrawers)`
	width: 100%;
	background: #ffffff;
`;

const MessageSingle = styled.div`
	display: flex;
	flex-wrap: wrap;
	margin: 15px 0;
	align-items: flex-start;
	flex-shrink: 0;

	@media only screen and (max-width: 767px) {
		margin: 10px 0;
	}

	&.loggedUser {
		justify-content: flex-end;
	}
	.messageGravatar {
		width: 40px;
		height: 40px;
		flex-shrink: 0;
		overflow: hidden;
		margin: 0px 20px;

		img {
			border-radius: 50%;
			width: 100%;
			height: 100%;
			object-fit: cover;
		}
	}
	.messageContent {
		display: flex;
		flex-direction: column;
		max-width: calc(100% - 110px);
		flex-shrink: 0;
		.messageContentText {
			position: relative;
			font-size: 14px;
			vertical-align: top;
			display: inline-block;
			padding: 10px 15px;

			p {
				margin: 0;
			}
		}
		.messageTime {
			font-size: 12px;
			color: ${palette('text', 3)};
			margin-top: 5px;
		}
		&.isUser {
			justify-content: flex-end;
			.messageContentText {
				background: ${palette('primary', 1)};
				color: #ffffff;
				border-radius: 3px 0 3px 3px;

				&:after {
					content: '';
					position: absolute;
					border-style: solid;
					display: block;
					width: 0;
					top: 0;
					bottom: auto;
					left: auto;
					right: -9px;
					border-width: 0px 0 10px 10px;
					border-color: transparent ${palette('primary', 1)};
					margin-top: 0;
				}
			}
			.messageTime {
				margin-left: auto;
			}
		}
		&.notUser {
			.messageContentText {
				background: ${palette('grayscale', 4)};
				color: ${palette('text', 0)};
				border-radius: 0 3px 3px 3px;

				&:after {
					content: '';
					position: absolute;
					border-style: solid;
					display: block;
					width: 0;
					top: 0;
					bottom: auto;
					left: -9px;
					border-width: 0px 10px 10px 0;
					border-color: transparent ${palette('grayscale', 4)};
					margin-top: 0;
				}
			}
			.messageTime {
				margin-right: auto;
			}
		}
	}
`;
const ChatWindow = styled.div`
	display: flex;
	width: 100%;
	height: 100%;
	overflow: hidden;
	position: relative;

	@media only screen and (max-width: 767px) {
		> div {
			width: 100%;
			max-width: 100%;
		}
	}
`;
const ChatBox = styled.div`
	width: calc(100% - 350px);
	background-color: #ffffff;
	border: 1px solid ${palette('border', 0)};
	border-left-width: 0;
	display: flex;
	flex-direction: column;

	@media only screen and (max-width: 767px) {
		border-left-width: 1px;
	}
`;
const ChatSidebar = styled.div`
	flex-shrink: 0;
	border: 1px solid ${palette('border', 0)};
	height: 100%;
	display: flex;
	flex-direction: column;
	background-color: #ffffff;

	.UserListsWrapper {
		.messageHelperText {
			background: #ffffff;
			height: 100%;
			padding: 0 !important;
		}
	}

	.ComposeMessageButton {
		margin-top: auto;
		padding: 20px;
		flex-shrink: 0;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 100%;
		text-align: center;
		background: #ffffff;

		button {
			width: 100%;
			margin: 0;
		}
	}
	@media only screen and (min-width: 768px) {
		width: 350px;
	}
`;

const Button = styled(Buttons)`
	width: calc(100% - 60px);
	margin-left: 30px;
	margin-top: 30px;
	span {
		&:last-child {
			span {
				background-color: #ffffff;
			}
		}
	}
`;

const ComposeMessageWrapper = styled.div`
	background: ${palette('grayscale', 5)};
	flex-shrink: 0;
	border-top: 1px solid ${palette('border', 0)};
	border-bottom: 0;

	${Textarea} {
		padding: 20px;
		border: 0;
		background-color: transparent;
		resize: none;

		&:focus {
			box-shadow: none;
		}
	}
`;
const ComposeInputWrapper = styled.div`
	background: #ffffff;
	height: 65vh;
	padding: 30px 30px 0;
	> div {
		margin-top: -8px;
		width: 100%;
		margin-left: 20px;
	}
`;

const UserListsWrapper = styled.div`
	width: 100%;
	display: flex;
	flex-direction: column;
`;

const UserLists = styled.div`
	width: 100%;
	margin: 0;
	padding: 10px 20px;
	display: -webkit-box;
	display: -webkit-flex;
	display: -ms-flexbox;
	display: flex;
	-webkit-box-pack: start;
	-webkit-justify-content: flex-start;
	-ms-flex-pack: start;
	justify-content: flex-start;
	-webkit-flex-shrink: 0;
	-ms-flex-negative: 0;
	flex-shrink: 0;
	text-align: left;
	position: relative;
	margin: 0;
	margin-bottom: 3px;
	align-items: center;
	cursor: pointer;
	box-sizing: border-box;
	transition: all 0.25s ease;
	background-color: #fff;

	* {
		box-sizing: border-box;
	}

	&:hover {
		background-color: ${palette('grayscale', 3)};
	}

	.userListsGravatar {
		width: 50px;
		margin: 0 15px 0 0;
		flex-shrink: 0;
		img {
			border-radius: 50%;
		}
	}
	.userListsContent {
		width: 100%;
		display: flex;
		flex-direction: column;
		overflow: hidden;

		h4 {
			font-size: 14px;
			margin: 0;
			font-weight: 500;
		}

		.chatExcerpt {
			width: 100%;
			display: flex;
			justify-content: space-between;
			align-items: flex-start;

			p {
				color: ${palette('text', 1)};
				margin: 0;
				font-size: 12px;
				white-space: nowrap;
				overflow: hidden;
				text-overflow: ellipsis;
				width: 100%;
				display: inline-block;
			}

			.userListsTime {
				color: ${palette('grayscale', 0)};
				font-size: 10px;
				flex-shrink: 0;
			}
		}
	}
`;

const ToggleViewProfile = styled.div`
	background: #ffffff;
	height: 65px;
	flex-shrink: 0;
	padding-left: 30px;
	display: flex;
	align-items: center;

	> span {
		font-size: 17px;
		color: ${palette('text', 0)};
		cursor: pointer;
	}

	@media only screen and (max-width: 767px) {
		padding-left: 20px;
	}

	${Button} {
		width: auto;
		padding: 0;
		border: 0;
		margin: 0;
		margin-right: 10px;
		width: 30px;
		height: 30px;
		display: flex;
		align-items: center;
		justify-content: center;

		&:focus {
			box-shadow: none;
		}

		i {
			font-size: 12px;
			color: ${palette('text', 0)};
		}
	}
`;

const SidebarSearchBox = styled.div`
	padding: 15px 20px;
	background: #ffffff;
	display: flex;
	flex-shrink: 0;
	align-items: center;
	justify-content: center;
	border-bottom: 1px solid ${palette('border', 2)};

	${Input} {
		padding: 0;
		border: 0;

		&:focus {
			box-shadow: none;
		}
	}
`;

const MessageChatWrapper = styled.div`
	display: flex;
	width: 100%;
	height: calc(100% - 136px);
	flex-direction: column;
	overflow: hidden;
	overflow-y: auto;
	background: #ffffff;
	border-top: 1px solid ${palette('border', 0)};

	::-webkit-scrollbar {
		display: none;
	}
`;

const ChatViewWrapper = styled.div`
	height: 100%;
	padding: 30px;

	@media only screen and (max-width: 767px) {
		padding: 0;
	}
`;

const MessageDialog = styled.div`
	h5 {
		font-size: 13px;
		color: ${palette('text', 0)};
		margin-bottom: 10px;
	}

	${ComposeMessageWrapper} {
		background: #ffffff;
		flex-shrink: 0;
		border: 0;

		${Textarea} {
			padding: 4px 10px;
			border: 1px solid ${palette('border', 0)};
			margin-bottom: 10px;

			&:focus {
				border-color: #4482ff;
				box-shadow: 0 0 0 2px rgba(68, 130, 255, 0.2);
			}
		}
	}
`;

export {
	MessageSingle,
	ChatWindow,
	ChatBox,
	ChatSidebar,
	Button,
	Input,
	Textarea,
	ComposeMessageWrapper,
	UserLists,
	UserListsWrapper,
	ToggleViewProfile,
	ComposeInputWrapper,
	SidebarSearchBox,
	MessageChatWrapper,
	ChatViewWrapper,
	ReactDrawer,
	MessageDialog,
};
