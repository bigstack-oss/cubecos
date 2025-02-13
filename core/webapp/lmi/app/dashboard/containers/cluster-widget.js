// dashboard/containers/cluster-widget.js

import { connect } from 'react-redux';

import * as c from '../constant';
import { fetchClusterUsage } from '../action';

import ClusterWidget from '../components/cluster-widget';

const mapStateToProps = (state, ownProps) => {
  return {
    usage: state[c.NAME].clusterUsage,
  };
};

export default connect(mapStateToProps, { fetchClusterUsage })(ClusterWidget);