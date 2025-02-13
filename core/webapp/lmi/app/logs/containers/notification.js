// logs/containers/notification.js

import { connect } from 'react-redux';

import * as c from '../constant';
import { fetchAdminResp, fetchInstanceResp, setAdminRespType, setInstanceRespType, updateAdminResp, updateInstanceResp } from '../action';

import Notification from '../components/notification';

const mapStateToProps = (state, ownProps) => {
  return {
    adminResp: state[c.NAME].adminResps[0],
    instanceResp: state[c.NAME].instanceResps[0],
    role: state['basic'].userInfo.role,
    tenantId: state['basic'].userInfo.tenantId,
  };
};

export default connect(mapStateToProps, { fetchAdminResp, fetchInstanceResp, setAdminRespType, setInstanceRespType, updateAdminResp, updateInstanceResp })(Notification);