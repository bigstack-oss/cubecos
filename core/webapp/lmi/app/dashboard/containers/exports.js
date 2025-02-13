// dashboard/containers/exports.js

import { connect } from 'react-redux';

import * as c from '../constant';

import Exports from '../components/exports';

import { fetchInstances, fetchUserInstances, fetchExports } from '../action';

const mapStateToProps = (state, ownProps) => {
  return {
    instances: state[c.NAME].instances,
    userInstances: state[c.NAME].userInstances,
    exports: state[c.NAME].exports,
    username: state['basic'].userInfo.username,
    groups: state['basic'].userInfo.groups.toString().split(","),
    role: state['basic'].userInfo.role,
  };
};

export default connect(mapStateToProps, { fetchInstances, fetchUserInstances, fetchExports })(Exports);