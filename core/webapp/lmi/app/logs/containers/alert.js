// logs/containers/alert.js

import { connect } from 'react-redux';

import * as c from '../constant';
import { fetchSystemAlert, fetchHostAlert, fetchInstanceAlert } from '../action';

import Alert from '../components/alert';

const mapStateToProps = (state, ownProps) => {
  return {
    systemAlerts: state[c.NAME].systemAlerts,
    hostAlerts: state[c.NAME].hostAlerts,
    instanceAlerts: state[c.NAME].instanceAlerts,
    role: state['basic'].userInfo.role,
    tenantId: state['basic'].userInfo.tenantId,
  };
};

export default connect(mapStateToProps, { fetchSystemAlert, fetchHostAlert, fetchInstanceAlert })(Alert);