// mgmt/components/cluster-nodes.js

import React from 'react';

import { Popconfirm, Spin } from 'antd';
import { notification } from '../../../components';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import Table from '../../../components/uielements/table';
import PageHeader from '../../../components/utility/pageHeader';

import AlertDiv from '../../logs/components/alert.style';

class ClusterNodes extends React.Component {
  state = {
    nodes: [],
    changing: false,
  };

  columns = [
    {
      title: 'Hostname',
      dataIndex: 'hostname',
      key: 'hostname',
    },
    {
      title: 'IP',
      dataIndex: 'ip.management',
      key: 'ip.management',
    },
    {
      title: 'Role',
      dataIndex: 'role',
      key: 'role',
    },
    {
      title: 'Action',
      key: 'action',
      render: (text, record) => (
        <span>
          {record.role === 'compute' || record.role === 'storage' ? (
            <Popconfirm title={"Sure to remove " + record.hostname + "?"} onConfirm={() => { this.removeNode(record.hostname); this.fetchNodes(); }}>
              <a>Remove</a>
            </Popconfirm>
          ) : (
            null
          )}
        </span>
      ),
    },
  ];

/*
  componentDidMount() {
    fetch(`${window.cluster[window.env.CLUSTER].API_URL}/v1/manage/node-list`)
    .then(res => res.json())
    .then((data) => {
      data.push({"hostname": "test", "ip":{"management":"1.1.1.1"}, "role": 'compute'})
      this.setState({ nodes: data })
    })
    .catch(console.log);
  }
*/

  componentDidMount() {
    this.fetchNodes();
  }

  fetchNodes() {
    this.setState({ changing: true });

    fetch(`${window.cluster[window.env.CLUSTER].API_URL}/v1/manage/node-list`)
    .then((res) => {
      this.setState({ changing: false });
      return res.json();
    })
    .then((data) => {
      this.setState({ nodes: data })
    })
    .catch(console.log);
  }

  removeNode = (host) => {
    this.setState({ changing: true });

    fetch(`${window.cluster[window.env.CLUSTER].API_URL}/v1/manage/nodes/` + host, {
      method: 'DELETE',
    })
    .then((res) => {
      this.setState({ changing: false });
      if (!res.ok) {
        throw new Error(res.statusText);
      }
      notification('success', 'Removed node successfully', '');
    })
    .catch((err) => {
      notification('error', 'Failed to remove node', err.message);
      console.log(err);
    });
  }

  render() {
    return (
      <LayoutWrapper>
        <PageHeader>Cluster Nodes</PageHeader>
        <AlertDiv className="isoLayoutContent">
          <Spin tip='Updateing...' spinning={this.state.changing}>
            <Table
              rowKey='hostname'
              size='small'
              pagination={{ pageSize: 50, position: 'bottom' }}
              columns={this.columns}
              dataSource={this.state.nodes}
              bordered
            />
          </Spin>
        </AlertDiv>
      </LayoutWrapper>
    );
  }
}

export default ClusterNodes