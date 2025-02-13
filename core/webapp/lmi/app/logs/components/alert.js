// logs/components/alert.js

import React from 'react';
import createReactClass from 'create-react-class';

import * as c from '../constant';

import IntlMessages from '../../../components/utility/intlMessages';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import PageHeader from '../../../components/utility/pageHeader';
import Tabs, { TabPane } from '../../../components/uielements/tabs';
import Table from '../../../components/uielements/table';

import AlertDiv from './alert.style';
import { tableTabs } from './alert.config';

const AlertTable = ({ columns, dataSource }) => {
  return (
    <Table
      rowKey='mid'
      size='small'
      pagination={{ pageSize: 50, position: 'bottom' }}
      columns={columns}
      dataSource={dataSource}
      bordered
    />
  );
}

const Alert = createReactClass({
  getInitialState: function() {
    return { refresh: true };
  },

  componentDidMount: function() {
    this.interval = setInterval(() => this.setState({ refresh: true }), c.REFRESH);
  },

  componentWillUnmount: function() {
    clearInterval(this.interval);
  },

  renderTable: function(info, dataList) {
    switch (info.value) {
      case 'system':
      case 'host':
      case 'instance':
        return <AlertTable columns={info.columns} dataSource={dataList} />;
    }
  },

  render: function() {
    const { role, tenantId, systemAlerts, hostAlerts, instanceAlerts,
            fetchSystemAlert, fetchHostAlert, fetchInstanceAlert } = this.props;

    if (this.state.refresh) {
      if (role == 'admin') {
        fetchSystemAlert();
        fetchHostAlert();
        fetchInstanceAlert();
      }
      else if (tenantId && tenantId.length > 0)
        fetchInstanceAlert(tenantId);
      this.setState({ refresh: false });
    }

    const alerts = {
      system: systemAlerts,
      host: hostAlerts,
      instance: instanceAlerts
    };

    return (
      <LayoutWrapper>
        {/*<PageHeader>{<IntlMessages id="page.logs.alert" />}</PageHeader>*/}
        <AlertDiv className="isoLayoutContent">
          <Tabs className="isoTableDisplayTab">
            {tableTabs[role] && tableTabs[role].map(info => (
              <TabPane tab={info.title} key={info.value}>
                {this.renderTable(info, alerts[info.value])}
              </TabPane>
            ))}
          </Tabs>
        </AlertDiv>
      </LayoutWrapper>
    );
  }
});

export default Alert;