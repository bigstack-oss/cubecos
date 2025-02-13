// dashboard/containers/app.js

import { connect } from 'react-redux';

import Application from '../components/application';

const mapStateToProps = (state, ownProps) => {
  return {
    groups: state['basic'].userInfo.groups,
  };
};

export default connect(mapStateToProps)(Application);