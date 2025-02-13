// dashboard/components/export.js

import React from 'react';
import clone from 'clone';
import createReactClass from 'create-react-class';

import * as c from '../constant';

import PageHeader from '../../../components/utility/pageHeader';
import IntlMessages from '../../../components/utility/intlMessages';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import Tabs, { TabPane } from '../../../components/uielements/tabs';
import Tag from '../../../components/uielements/tag';
import Table from '../../../components/uielements/table';

import { Button, notification, Popconfirm } from 'antd';

import ExportsDiv from './exports-style';

const NET_TAGCOLORS = [ '#3FB8AF', '#7FC7AF', '#DAD8A7', '#FF9E9D', '#FF3D7F'];
const EXP_TAGCOLORS = [ 'blue', 'green'];

const ExportsTable = ({ columns, dataSource }) => {
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
};

const Exports = createReactClass({
  getInitialState: function() {
    return { refresh: true };
  },

  componentDidMount: function() {
    this.interval = setInterval(() => this.setState({ refresh: true }), c.MIN_REFRESH);
  },

  componentWillUnmount: function() {
    clearInterval(this.interval);
  },

  renderTable: function(info, dataList) {
    return <ExportsTable columns={info.columns} dataSource={dataList} />;
  },

  render: function() {
    const { instances, userInstances, exports, username, groups, role, fetchInstances, fetchUserInstances, fetchExports } = this.props;

    const onReqExport = obj => {
      fetch(`${window.cluster[window.env.CLUSTER].API_URL}/v1/manage/exports/${obj['ID']}?project=${obj['Project']}&name=${obj['Name']}`, {
        method: 'POST',
      })
      .then((res) => {
        if (!res.ok) {
          throw new Error(res.statusText);
        }
        const key = `open${Date.now()}`;
        const btn = (
          <Button type="primary" size="small" onClick={() => notification.close(key)}>
            Confirm
          </Button>
        );
        notification['success']({
          message: 'Exporting Instance',
          description: `Successfully request to export instance ${obj['Name']}. It will take a while for fully exported. You can come back later or wait for auto refresh.`,
          btn,
          key,
          duration: 0,
        });
      })
      .catch((err) => {
        notification['error']({
          message: 'Exporting Instance',
          description: `Failed to export instance ${obj['Name']}, reason: ${err.message}.`,
        });
      });
    };

    const columns = [
      {
        title: <IntlMessages id="instance.name" />,
        key: 'Name',
        width: '15%',
        render: object => (<span>{object['Name']}</span>)
      },
      {
        title: <IntlMessages id="instance.image" />,
        key: 'Image Name',
        width: '20%',
        render: object => (<span>{object['Image Name']}</span>)
      },
      {
        title: <IntlMessages id="instance.flavor" />,
        key: 'Flavor Name',
        width: '10%',
        render: object => (<span>{object['Flavor Name']}</span>)
      },
      {
        title: <IntlMessages id="instance.networks" />,
        key: 'Networks',
        width: '15%',
        render: object => (
          <span>
            {object['Networks'] && Object.keys(object['Networks']).map((net, idx) => {
              return (<Tag color={NET_TAGCOLORS[idx % NET_TAGCOLORS.length]} key={net} >{net + ": " + object['Networks'][net].toString()}</Tag>);
            })}
          </span>
        )
      },
      {
        title: <IntlMessages id="instance.status" />,
        key: 'Status',
        width: '8%',
        render: object => (<span>{object['Status']}</span>)
      },
      {
        title: <IntlMessages id="instance.download" />,
        key: 'Exports',
        width: '22%',
        render: object => (
          <span>
            {object['Exports'] && object['Exports'].map((exp, idx) => {
              return (<Tag color={EXP_TAGCOLORS[idx % EXP_TAGCOLORS.length]} key={exp['fname']}><a href={`/v1/manage/exports/${exp['fname']}`}>{exp['fname'] + ": " + exp['size']}</a></Tag>);
            })}
          </span>
        )
      },
      {
        title: <IntlMessages id="instance.action" />,
        key: 'ID',
        width: '10%',
        render: object => (
          <Popconfirm title={`Has qemu-guest-agent been properly running?`} okText="Yes" cancelText="No" onConfirm={() => { onReqExport(object); fetchExports(); }} >
            <a>Export</a>
          </Popconfirm>
        )
      },
    ];

    if (this.state.refresh) {
      fetchInstances();
      fetchExports();
      if (role != 'admin') {
        let uname = username;
        let uitems = username.split("@")
        if (uitems.length > 1)
          uname = uitems[0];
        fetchUserInstances(uname);
      }
      this.setState({ refresh: false });
    }

    let tableTabs = []
    if (role == 'admin') {
      for (var p in instances){
        if (instances[p].length > 0)
          tableTabs.push({title: p, value: p, role: 'admin', columns: columns})
      }
    }
    else {
      for (var i = 0 ; i < groups.length ; i++) {
        let gname = groups[i];
        let gitems = groups[i].split("-")
        let role = 'user';
        if (gitems.length > 1) {
          const r = gitems[gitems.length - 1]
          if (r == 'creator' || r == 'admin' || r == 'member') {
            gitems.pop();
            gname = gitems.join("-")
            if (r == 'creator' || r == 'admin')
              role = 'admin';
          }
        }
        if (instances && instances[gname] && instances[gname].length > 0)
          tableTabs.push({title: gname, value: gname, role: role, columns: columns})
      }
    }

    let tableData = JSON.parse(JSON.stringify(instances));
    for (var i = 0 ; i < tableTabs.length ; i++) {
      // p: project name
      const p = tableTabs[i].value;

      for (var j = 0 ; j < tableData[p].length ; j++) {
        tableData[p][j]['Project'] = p;
        const id = tableData[p][j]['ID'];
        const name = tableData[p][j]['Name'];
        if (tableTabs[i].role != 'admin') {
          let found = false;
          for (var u = 0 ; u < userInstances.length ; u++) {
            if (userInstances[u]['ems_ref'] == id) {
              found = true;
              break;
            }
          }
          if (!found) {
            tableData[p].splice(j, 1);
            j = j - 1;
            continue;
          }
        }

        let expList = [];
        for (var k = 0 ; k < exports.length ; k++) {
          if (exports[k].fname && exports[k].fname.indexOf(`-${name}-${id.substring(0, 8)}-`) > 0) {
            expList.push(clone(exports[k]))
          }
        }
        tableData[p][j]["Exports"] = JSON.parse(JSON.stringify(expList));
      }
    }

    return (
      <LayoutWrapper>
        {/*<PageHeader>{<IntlMessages id="page.export" />}</PageHeader>*/}
        <ExportsDiv className="isoLayoutContent">
          <Tabs className="isoTableDisplayTab">
            {tableTabs.length > 0 && tableTabs.map(info => (
              <TabPane tab={info.title} key={info.value}>
                {this.renderTable(info, tableData[info.value])}
              </TabPane>
            ))}
          </Tabs>
        </ExportsDiv>
      </LayoutWrapper>
    );
  }
});

export default Exports;