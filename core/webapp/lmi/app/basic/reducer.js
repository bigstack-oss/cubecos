// basic/reducer.js

import update from 'immutability-helper';

import * as t from './action-type.js';

// The default state
const DEFAULT_STATE = {
  userInfo: { role: '_member_' },
  authenticated: false,
  loading: false,
};

// Takes care of changing the state
export default function (state = DEFAULT_STATE, action)
{
  switch (action.type) {
    case t.SET_USERINFO:
      return update(state,
        {userInfo: {$set: action.userInfo}}
      );
    case t.SET_AUTH:
      return update(state,
        {authenticated: {$set: action.authenticated }}
      );
    case t.SET_LOADING:
      return update(state,
        {loading: {$set: action.loading }}
      );
    case t.SET_CLUSTER:
      return update(state,
        {selectedCluster: {$set: action.cluster }}
      );
    default:
      return state;
  }
}