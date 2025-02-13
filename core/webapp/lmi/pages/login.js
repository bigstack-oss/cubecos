// pages/login.js

import React from 'react';
import Helmet from 'react-helmet';

import Page from '../hocs/defaultPage';
import basic from '../app/basic';

const Login = basic.containers.Login;

export default Page((props) => (
  <div>
    <Helmet>
      <title>Login</title>
    </Helmet>
    <Login {...props} />
  </div>
));
