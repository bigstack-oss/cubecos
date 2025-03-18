// mgmt/components/cluster-health.js

import React from 'react';
import createReactClass from 'create-react-class';
import Card from '../../../components/uielements/card';
import { Col, Row, Badge, Descriptions } from 'antd'

import * as c from '../constant';

import IntlMessages from '../../../components/utility/intlMessages';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import PageHeader from '../../../components/utility/pageHeader';

// import custom styles
import basicStyle from '../../../config/basicStyle';

const { rowStyle, colStyle } = basicStyle;

const CORE_COMPS = [
  'link',
  'clock',
  'dns',
  'etcd',
  'hacluster',
  'rabbitmq',
  'mysql',
  'vip',
  'haproxy_ha',
  'haproxy',
  'httpd',
  'nginx',
  'api',
  'lmi',
  'skyline',
  'memcache',
  'k3s',
  'keycloak',
  'ceph',
  'ceph_mon',
  'ceph_mgr',
  'ceph_mds',
  'ceph_osd',
  'ceph_rgw',
  'rbd_target',
  'nova',
  'cyborg',
  'neutron',
  'glance',
  'cinder',
  'manila',
  'swift',
  'heat',
  'octavia',
  'masakari',
  'zookeeper',
  'kafka',
  'monasca',
  'telegraf',
  'influxdb',
  'kapacitor',
  'grafana',
  'filebeat',
  'auditbeat',
  'logstash',
  'mongodb',
];

const CTRL_COMPS = [
  'ironic',
  'designate',
  'senlin',
  'watcher',
  'rancher',
  'opensearch',
  'opensearch-dashboards',
];

const EDGE_SERVICES = {
  'Cluster Link': [ 'link', 'clock', 'dns' ],
  'Cluster Settings': [ 'etcd', 'mongodb' ],
  'HA Cluster': [ 'hacluster' ],
  'Message Queue': [ 'rabbitmq' ],
  'IaaS Database': [ 'mysql' ],
  'Virtual IP': [ 'vip', 'haproxy_ha' ],
  'Storage': [ 'ceph', 'ceph_mon', 'ceph_mgr', 'ceph_mds', 'ceph_osd', 'ceph_rgw', 'rbd_target' ],
  'API Service': [ 'haproxy', 'httpd', 'nginx', 'api', 'lmi', 'skyline', 'memcache' ],
  'Single Sign On': [ 'k3s', 'keycloak' ],
  'Compute': [ 'nova', 'cyborg' ],
  'Network': [ 'neutron' ],
  'Image': [ 'glance' ],
  'Block Storage': [ 'cinder' ],
  'File Storage': [ 'manila' ],
  'Object Storage': [ 'swift' ],
  'Orchestration': [ 'heat' ],
  'LBaaS': [ 'octavia' ],
  'Instance Ha': [ 'masakari' ],
  'DataPipe': [ 'zookeeper', 'kafka' ],
  'Metrics': [ 'monasca', 'telegraf', 'grafana' ],
  'Log Analytics': [ 'filebeat', 'auditbeat', 'logstash' ],
  'Notifications': [ 'influxdb', 'kapacitor' ],
};

const CTRL_SERVICES = {
  'Cluster Link': [ 'link', 'clock', 'dns' ],
  'Cluster Settings': [ 'etcd', 'mongodb' ],
  'HA Cluster': [ 'hacluster' ],
  'Message Queue': [ 'rabbitmq' ],
  'IaaS Database': [ 'mysql' ],
  'Virtual IP': [ 'vip', 'haproxy_ha' ],
  'Storage': [ 'ceph', 'ceph_mon', 'ceph_mgr', 'ceph_mds', 'ceph_osd', 'ceph_rgw', 'rbd_target' ],
  'API Service': [ 'haproxy', 'httpd', 'nginx', 'api', 'lmi', 'skyline', 'memcache' ],
  'Single Sign On': [ 'k3s', 'keycloak' ],
  'Compute': [ 'nova', 'cyborg' ],
  'Baremetal': [ 'ironic' ],
  'Network': [ 'neutron' ],
  'Image': [ 'glance' ],
  'Block Storage': [ 'cinder' ],
  'File Storage': [ 'manila' ],
  'Object Storage': [ 'swift' ],
  'Orchestration': [ 'heat' ],
  'LBaaS': [ 'octavia' ],
  'DNSaaS': [ 'designate' ],
  'K8SaaS': [ 'rancher' ],
  'Instance Ha': [ 'masakari' ],
  'Business Logic': [ 'senlin', 'watcher' ],
  'DataPipe': [ 'zookeeper', 'kafka' ],
  'Metrics': [ 'monasca', 'telegraf', 'grafana' ],
  'Log Analytics': [ 'filebeat', 'auditbeat', 'logstash', 'opensearch', 'opensearch-dashboards' ],
  'Notifications': [ 'influxdb', 'kapacitor' ],
}

const STATUS = {
  ok: 'success',
  nook: 'warning',
}

const STATUS_TEXT = {
  ok: 'healthy',
  nook: 'warning',
}

const HTTP_STATUS = [ 'processing', 'error' ];
const HTTP_STATUS_TEXT = [ 'Available', 'Unavailable' ];

const cardStyle = { margin: '0px 8px' };

const BadgeText = d => {
  if (d.health == 'ok')
    return STATUS_TEXT[d.health];
  else
    return STATUS_TEXT[d.health] + ' (' + d.error + ')';
}

const ServiceCard = ({ name, data }) => {
  return (
    <Col lg={8} md={24} sm={24} xs={24} style={colStyle}>
      <Card style={cardStyle}>
        <Descriptions bordered title={name} size='small'>
          {window.env.EDGE_CORE ?
            EDGE_SERVICES[name].map(c => (
            <Descriptions.Item label={c} span={2}>
              {data[c] && <Badge status={STATUS[data[c].health]} text={BadgeText(data[c])} />}
            </Descriptions.Item>))
            :
            CTRL_SERVICES[name].map(c => (
            <Descriptions.Item label={c} span={2}>
              {data[c] && <Badge status={STATUS[data[c].health]} text={BadgeText(data[c])} />}
            </Descriptions.Item>))
        }
        </Descriptions>
      </Card>
    </Col>
  );
}

const ClusterHealth = createReactClass({
  getInitialState: function() {
    return { refresh: true };
  },

  componentDidMount: function() {
    this.interval = setInterval(() => this.setState({ refresh: true }), c.REFRESH * 5);
  },

  componentWillUnmount: function() {
    clearInterval(this.interval);
  },

  render: function() {
    const { healthDb, fetchCompHealth } = this.props;

    if (this.state.refresh) {
      CORE_COMPS.forEach(comp => fetchCompHealth(comp));
      if (!window.env.EDGE_CORE) {
        CTRL_COMPS.forEach(comp => fetchCompHealth(comp));
      }
      this.setState({ refresh: false });
    }

    return (
      <LayoutWrapper>
        <PageHeader>Core Services</PageHeader>
        <Row style={rowStyle} gutter={0} justify='start'>
          <ServiceCard name='Cluster Link' data={healthDb} />
          <ServiceCard name='Cluster Settings' data={healthDb} />
          <ServiceCard name='HA Cluster' data={healthDb} />
        </Row>
        <Row style={rowStyle} gutter={0} justify='start'>
          <ServiceCard name='Message Queue' data={healthDb} />
          <ServiceCard name='IaaS Database' data={healthDb} />
          <ServiceCard name='Virtual IP' data={healthDb} />
        </Row>
        <Row style={rowStyle} gutter={0} justify='start'>
          <ServiceCard name='Single Sign On' data={healthDb} />
          <ServiceCard name='API Service' data={healthDb} />
        </Row>
        <PageHeader>Storage</PageHeader>
        <Row style={rowStyle} gutter={0} justify='start'>
          <ServiceCard name='Storage' data={healthDb} />
        </Row>
        <PageHeader>Cloud Computing</PageHeader>
        <Row style={rowStyle} gutter={0} justify='start'>
          <ServiceCard name='Compute' data={healthDb} />
          <ServiceCard name='Network' data={healthDb} />
          <ServiceCard name='LBaaS' data={healthDb} />
        </Row>
        <Row style={rowStyle} gutter={0} justify='start'>
          <ServiceCard name='Block Storage' data={healthDb} />
          <ServiceCard name='File Storage' data={healthDb} />
          <ServiceCard name='Object Storage' data={healthDb} />
        </Row>
        {!window.env.EDGE_CORE &&
          <Row style={rowStyle} gutter={0} justify='start'>
            <ServiceCard name='Baremetal' data={healthDb} />
            <ServiceCard name='DNSaaS' data={healthDb} />
            <ServiceCard name='K8SaaS' data={healthDb} />
          </Row>
        }
        <Row style={rowStyle} gutter={0} justify='start'>
          <ServiceCard name='Orchestration' data={healthDb} />
          <ServiceCard name='Instance Ha' data={healthDb} />
          <ServiceCard name='Image' data={healthDb} />
        </Row>
        {!window.env.EDGE_CORE &&
          <Row style={rowStyle} gutter={0} justify='start'>
            <ServiceCard name='Business Logic' data={healthDb} />
          </Row>
        }
        <PageHeader>Infrascope</PageHeader>
        <Row style={rowStyle} gutter={0} justify='start'>
          <ServiceCard name='DataPipe' data={healthDb} />
          <ServiceCard name='Notifications' data={healthDb} />
          <ServiceCard name='Metrics' data={healthDb} />
        </Row>
        {!window.env.EDGE_CORE &&
          <Row style={rowStyle} gutter={0} justify='start'>
            <ServiceCard name='Log Analytics' data={healthDb} />
          </Row>
        }
      </LayoutWrapper>
    );
  }
});

export default ClusterHealth;
