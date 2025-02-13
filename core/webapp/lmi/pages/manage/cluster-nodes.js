// pages/manage/cluster-nodes.js

import React, { Component } from 'react';
import Helmet from 'react-helmet';
import Page from '../../hocs/securedPage';
import mgmt from '../../app/mgmt';
import ClusterNodes from '../../app/mgmt/components/cluster-nodes'

//const ClusterNodes = mgmt.containers.ClusterNodes;

export default Page(() => (
  <div>
    <Helmet>
      <title>Cluster Nodes</title>
    </Helmet>
    <div>
      <ClusterNodes />
    </div>
  </div>
));
