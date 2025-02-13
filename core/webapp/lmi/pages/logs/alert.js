// pages/logs/alert.js

import React, { Component } from 'react';
import Helmet from 'react-helmet';
import Page from '../../hocs/securedPage';
import logs from '../../app/logs';

const Alert = logs.containers.Alert;

export default Page(() => (
  <div>
    <Helmet>
      <title>Alerts</title>
    </Helmet>
    <div>
      <Alert />
    </div>
  </div>
));
