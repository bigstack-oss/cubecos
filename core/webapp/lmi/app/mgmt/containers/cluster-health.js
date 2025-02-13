// mgmt/containers/cluster-health.js

import { connect } from 'react-redux';

import * as c from '../constant';
import { fetchCompHealth } from '../action';

import ClusterHealth from '../components/cluster-health';

const mapStateToProps = (state, ownProps) => {
  return {
    healthDb: state[c.NAME],
  };
};

export default connect(mapStateToProps, { fetchCompHealth })(ClusterHealth);