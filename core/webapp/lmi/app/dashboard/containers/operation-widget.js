// dashboard/containers/operation-widget.js

import { connect } from 'react-redux';

import * as c from '../constant';
import { fetchOpSummary } from '../action';

import OperationWidget from '../components/operation-widget';

const mapStateToProps = (state, ownProps) => {
  return {
    summary: state[c.NAME].opSummary,
  };
};

export default connect(mapStateToProps, { fetchOpSummary })(OperationWidget);