// mgmt/reducer.js

import update from 'immutability-helper';

import * as t from './action-type.js';

// The default state
const DEFAULT_STATE = {
};

// Takes care of changing the state
export default function (state = DEFAULT_STATE, action)
{
  switch (action.type) {
    case t.COMP_HEALTH_SAVE:
      return update(state,
        {[action.comp]: {$set: action.health}}
      );
    case t.LICENSE_STATUS_SAVE:
      return update(state,
        {license: {$set: action.license}}
      );
    default:
      return state;
  }
}