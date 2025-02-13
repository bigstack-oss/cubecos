// basic/action.js

import * as t from './action-type';

export const logout = () => ({
  type: t.LOGOUT,
});

export const profile = () => ({
  type: t.PROFILE,
});

export const selectCluster = ({key}) => ({
  type: t.SELECT_CLUSTER,
  cluster: key,
});