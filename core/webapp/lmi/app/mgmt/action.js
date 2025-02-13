// mgmt/action.js

import * as t from './action-type';

export const fetchCompHealth = (comp) => ({
  type: t.FETCH_COMP_HEALTH,
  comp
});

export const fetchLicenseStatus = (license) => ({
  type: t.FETCH_LICENSE_STATUS,
  license
});
