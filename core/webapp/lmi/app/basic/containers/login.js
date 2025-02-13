// basic/containers/login.js

import { connect } from 'react-redux';

import * as c from '../constant';
import { login } from '../action';

import Login from '../components/login';

const mapStateToProps = (state, ownProps) => {
  return {
    userInfo: state[c.NAME].userInfo,
    authenticated: state[c.NAME].authenticated,
  };
};

export default connect(mapStateToProps, { login })(Login);