// dashboard/containers/system-widget.js

import { connect } from 'react-redux';

import * as c from '../constant';
import { fetchPartition } from '../action';

import SystemWidget from '../components/system-widget';

const mapStateToProps = (state, ownProps) => {
  return {
    p: state[c.NAME].partition,
  };
};

export default connect(mapStateToProps, { fetchPartition })(SystemWidget);