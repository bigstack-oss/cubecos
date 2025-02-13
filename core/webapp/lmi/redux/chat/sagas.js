import { all, takeEvery, put, call, fork } from 'redux-saga/effects';
import actions from './actions';
import FirebaseHelper from '../../helpers/firebase';

const { database, createBatch, rsfFirestore, createNewRef } = FirebaseHelper;
const fsProps = {};
const reverseString = str =>
  str
    .split('')
    .reverse()
    .join('');

const sortChatrooms = (optionA, optionB) =>
  optionB.lastMessageTime - optionA.lastMessageTime;
const sortMessages = (optionA, optionB) =>
  optionA.messageTime - optionB.messageTime;
const initialization = payload => {
  fsProps.userId = payload.userId;
  fsProps.usersCollections = database.collection('users');
  fsProps.chatroomCollections = database.collection('chatRooms');
  fsProps.chatroomsUserCollections = fsProps.chatroomCollections.where(
    'userId',
    '==',
    payload.userId
  );
  fsProps.messagesCollections = database.collection('messages');
};

const readUsers = async () =>
  await fsProps.usersCollections.get().then(querySnapshot => {
    const users = [];
    try {
      querySnapshot.forEach(doc => {
        if (doc.id !== fsProps.userId) {
          users.push({ id: doc.id, ...doc.data() });
        }
      });
    } catch (e) {}
    return users;
  });
const readChatrooms = async () =>
  await fsProps.chatroomsUserCollections.get().then(querySnapshot => {
    const chatRooms = [];
    try {
      querySnapshot.forEach(doc => {
        chatRooms.push(doc.data());
      });
    } catch (e) {}
    return chatRooms.sort(sortChatrooms);
  });
const readMessages = async ({ id }) =>
  await fsProps.messagesCollections
    .where('chatRoomId', '==', id)
    .get()
    .then(querySnapshot => {
      const messages = [];
      try {
        querySnapshot.forEach(doc => {
          messages.push(doc.data());
        });
      } catch (e) {}
      return messages.sort(sortMessages);
    });

const readAllMessages = async () =>
  await fsProps.messagesCollections.get().then(querySnapshot => {
    const messages = [];
    try {
      querySnapshot.forEach(doc => {
        messages.push(doc.id);
      });
    } catch (e) {}
    return messages;
  });
const sendMessageBatch = async payload => {
  const batch = createBatch();
  const { chatRoom, text } = payload;
  const id = chatRoom.id;
  const revId = reverseString(id);
  const messageTime = new Date().getTime();
  const chatRoomModified = {
    lastMessage: text,
    lastMessageTime: messageTime
  };
  batch.update(fsProps.chatroomCollections.doc(id), chatRoomModified);
  batch.update(fsProps.chatroomCollections.doc(revId), chatRoomModified);
  batch.set(fsProps.messagesCollections.doc(createNewRef()), {
    sender: chatRoom.userId,
    text,
    messageTime,
    chatRoomId: chatRoom.id
  });
  batch.commit();
};
function* importDemoData({ demoData }) {
  const messageKeys = yield call(readAllMessages);
  const batch = createBatch();
  const { users, chatRooms, messages } = demoData;
  messageKeys.forEach(key =>
    batch.delete(fsProps.messagesCollections.doc(key))
  );
  const userInfos = {};
  users.forEach(user => {
    userInfos[user.key] = user.data;
    const doc = fsProps.usersCollections.doc(user.key);
    batch.set(doc, user.data);
  });
  messages.forEach(message => {
    const doc = fsProps.messagesCollections.doc(message.key);
    batch.set(doc, message.data);
  });
  chatRooms.forEach(room => {
    const doc = fsProps.chatroomCollections.doc(room.key);
    if (userInfos[room.data.otherUserId]) {
      batch.set(doc, {
        ...room.data,
        otherUserInfo: userInfos[room.data.otherUserId]
      });
    }
  });
  batch.commit();
  yield put({ type: actions.RESTORE_DEMO_DATA_DONE });
}
function* initChat({ payload }) {
  initialization(payload);
  const users = yield call(readUsers);
  const chatRooms = yield call(readChatrooms);
  const messages = yield call(readMessages, chatRooms[0]);
  fsProps.selectedChatRoom = chatRooms[0];
  yield fork(updateChatrooms);
  yield put({
    type: actions.CHAT_INIT_SAGA,
    users,
    chatRooms,
    messages
  });
}

function* sendMessage({ payload }) {
  fsProps.selectedChatRoom = payload.chatRoom;
  yield call(sendMessageBatch, payload);
}
function* updateChatrooms() {
  const successActionCreator = data => {
    const { type, newIndex } = data.docChanges[0];
    const dataMoodified = type === 'modified';
    if (!dataMoodified) {
      return { type: 'NO_CHANGE' };
    }
    const chatRoom = data.docs[newIndex].data();

    return {
      type: actions.CHAT_UPDATE_CHATROOM_SAGA,
      payload: { chatRoom }
    };
  };
  yield call(rsfFirestore.syncCollection, fsProps.chatroomsUserCollections, {
    successActionCreator
  });
}
function* updateChatroomSaga({ payload }) {
  const { chatRoom } = payload;
  let { selected } = payload;
  let messages;
  if (selected || chatRoom.id === fsProps.selectedChatRoom.id) {
    fsProps.selectedChatRoom = chatRoom;
    messages = yield call(readMessages, chatRoom);
    selected = true;
  }
  yield put({
    type: actions.CHAT_UPDATE_CHATROOM,
    chatRoom,
    messages,
    selected
  });
}
export default function* rootSaga() {
  yield all([
    takeEvery(actions.CHAT_INIT, initChat),
    takeEvery(actions.CHAT_UPDATE_CHATROOM_SAGA, updateChatroomSaga),
    takeEvery(actions.CHAT_SEND_MESSAGE, sendMessage),
    takeEvery(actions.RESTORE_DEMO_DATA, importDemoData)
  ]);
}
