// dashboard/components/dashboard.js

import React from 'react';
import Helmet from 'react-helmet';
//import Widgets from '../../../containers/Widgets';
import Widgets from './widgets';

const Dashboard = () => {
  return (
    <div>
      <Helmet>
        <title>Dashboard</title>
      </Helmet>
      <Widgets />
      {/*<DynamicComponent />*/}
    </div>
  );
}

export default Dashboard;