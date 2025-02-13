// dashboard/containers/infra-widget.js

import { connect } from 'react-redux';

import * as c from '../constant';
import { fetchInfraSummary } from '../action';

import InfraWidget from '../components/infra-widget';

const mapStateToProps = (state, ownProps) => {
  return {
    summary: state[c.NAME].infraSummary,
  };
};

export default connect(mapStateToProps, { fetchInfraSummary })(InfraWidget);