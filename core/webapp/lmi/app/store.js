// store.js

import { createStore, applyMiddleware } from 'redux';
import { persistStore, persistReducer } from 'redux-persist'
import storage from 'redux-persist/lib/storage' // defaults to localStorage for web
import withRedux from 'next-redux-wrapper';
import nextReduxSaga from 'next-redux-saga';
import createSagaMiddleware from 'redux-saga';
import thunk from 'redux-thunk';

import reducer from './reducer';
import saga from './saga';

const persistConfig = {
  key: 'root',
  storage,
};
const sagaMiddleware = createSagaMiddleware();

let middlewares = [thunk, sagaMiddleware];

export function makeStore(initialState, {isServer}) {
  if (process.env.NODE_ENV === 'development') {
    const { logger } = require('redux-logger');
    middlewares.push(logger);
  }

  let store;
  if (isServer) {
    store = createStore(reducer, initialState, applyMiddleware(...middlewares));
  }
  else {
    const persistedReducer = persistReducer(persistConfig, reducer);
    store = createStore(persistedReducer, initialState, applyMiddleware(...middlewares));
    store.persistor = persistStore(store);
  }

  store.sagaTask = sagaMiddleware.run(saga);
  return store;
}

export function withReduxSaga(BaseComponent) {
  return withRedux(makeStore)(nextReduxSaga(BaseComponent));
}