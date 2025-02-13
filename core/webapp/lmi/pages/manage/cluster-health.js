// pages/manage/cluster-health.js

import React, { Component } from 'react';
import Helmet from 'react-helmet';
import Page from '../../hocs/securedPage';
import mgmt from '../../app/mgmt';

const ClusterHealth = mgmt.containers.ClusterHealth;

export default Page(() => (
  <div>
    <Helmet>
      <title>Cluster Health</title>
    </Helmet>
    <div>
      <ClusterHealth />
    </div>
  </div>
));
