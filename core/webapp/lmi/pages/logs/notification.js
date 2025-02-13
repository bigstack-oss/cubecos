// pages/logs/notification.js

import React, { Component } from 'react';
import Helmet from 'react-helmet';
import Page from '../../hocs/securedPage';
import logs from '../../app/logs';

const Notification = logs.containers.Notification;

export default Page(() => (
  <div>
    <Helmet>
      <title>Notifications</title>
    </Helmet>
    <div>
      <Notification />
    </div>
  </div>
));
