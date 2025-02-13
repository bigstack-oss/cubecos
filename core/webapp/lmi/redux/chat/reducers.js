import clone from "clone";
import actions from "./actions";

const initState = {
	userId: "wt4TiasxgPrQ3dNwVZ55",
	user: {
		id: "wt4TiasxgPrQ3dNwVZ55",
		dob: "06-Apr-1993",
		gender: "Male",
		language: "Burmese",
		mobileNo: "5726784596",
		name: "Zondra Kulic",
		profileImageUrl:
			"https://s3.amazonaws.com/redqteam.com/mateadmin/support-male-zonra.png"
	},
	users: null,
	chatRooms: [],
	messages: [],
	selectedChatRoom: null,
	openCompose: false,
	viewProfile: false,
	composedId: null,
	loading: true,
	error: false,
	mobileActiveList: true,
	mobileActiveProfile: false,
	restoringData: false
};
const sortTimeStamp = (optionA, optionB) =>
	optionB.lastMessageTime - optionA.lastMessageTime;
export default function reducer(state = initState, action) {
	switch (action.type) {
		case actions.CHAT_INIT_SAGA: {
			return {
				...state,
				users: action.users,
				chatRooms: action.chatRooms,
				messages: action.messages,
				selectedChatRoom: action.chatRooms[0],
				loading: false
			};
		}
		case actions.CHAT_UPDATE_CHATROOM: {
			const chatRooms = clone(state.chatRooms);
			const { chatRoom, messages, selected } = action;
			const { id, lastMessage, lastMessageTime } = chatRoom;
			chatRooms.forEach((chatroom, index) => {
				if (chatroom.id === id) {
					chatRooms[index].lastMessage = lastMessage;
					chatRooms[index].lastMessageTime = lastMessageTime;
				}
			});
			state = {
				...state,
				chatRooms: chatRooms.sort(sortTimeStamp),
				composedId: null,
				openCompose: false
			};
			if (selected) {
				state = {
					...state,
					selectedChatRoom: chatRoom,
					viewProfile: false
				};
			}
			if (messages) {
				state = {
					...state,
					messages: messages
				};
			}
			return state;
		}
		case actions.CHAT_TOGGLE_COMPOSE:
			return {
				...state,
				openCompose: !state.openCompose,
				viewProfile: false
			};
		case actions.CHAT_SET_TOGGLE_COMPOSED_ID:
			return {
				...state,
				composedId: action.id
			};
		case actions.CHAT_SET_TOGGLE_VIEW_PROFILE:
			return {
				...state,
				viewProfile: action.viewProfile
			};
		case actions.TOGGLE_MOBILE_LIST:
			return {
				...state,
				mobileActiveList: action.mobileActiveList
			};
		case actions.TOGGLE_MOBILE_PROFILE:
			return {
				...state,
				mobileActiveProfile: action.mobileActiveProfile
			};
		case actions.RESTORE_DEMO_DATA:
			return {
				...state,
				restoringData: action.true
			};
		case actions.RESTORE_DEMO_DATA_DONE:
			return {
				...state,
				restoringData: action.false
			};
		default:
			return state;
	}
}
