// dashboard/components/widgets.js

// import global packages
import React from 'react';
import { Row, Col } from 'antd';
import styled from 'styled-components';

// import custom styles
import basicStyle from '../../../config/basicStyle';

// import custom components
import WidgetWrapper from './widget-wrapper';
import WidgetTitle from '../containers/widget-title';
import SystemWidget from '../containers/system-widget';
import ClusterWidget from '../containers/cluster-widget';
import StorageWidget from '../containers/storage-widget';
import OperationWidget from '../containers/operation-widget';
import InfraWidget from '../containers/infra-widget';
import ToptenWidget from '../containers/topten-widget';

const { rowStyle, colStyle } = basicStyle;

const WidgetsDiv = styled.div`
  padding: 30px 30px 15px 15px;
  overflow: hidden;

  p {
    margin-bottom: 0px;
  }
`;

const top10HostOptions = [
  [ 'cpu', 'widget.topten.option.cpu' ],
  [ 'mem', 'widget.topten.option.mem' ],
  [ 'disk', 'widget.topten.option.disk' ],
  [ 'netin', 'widget.topten.option.netin' ],
  [ 'netout', 'widget.topten.option.netout' ],
];

const top10VmOptions = [
  [ 'cpu', 'widget.topten.option.cpu' ],
  [ 'mem', 'widget.topten.option.mem' ],
  [ 'diskr', 'widget.topten.option.diskr' ],
  [ 'diskw', 'widget.topten.option.diskw' ],
  [ 'netin', 'widget.topten.option.netin' ],
  [ 'netout', 'widget.topten.option.netout' ],
];

const Widgets = () => {
  return (
    <WidgetsDiv>
      <Row style={rowStyle} gutter={0} justify='start'>
        <Col lg={12} md={12} sm={24} xs={24} style={colStyle}>
          <WidgetTitle icon='ti-link' label='widget.system.title' />
          <WidgetWrapper>
            <SystemWidget/>
          </WidgetWrapper>
        </Col>
        <Col lg={12} md={12} sm={24} xs={24} style={colStyle}>
          <WidgetTitle
            icon='ti-heart-broken'
            label='widget.cluster.title'
            onClickUrl={`/monitoring/host`}
          />
          <WidgetWrapper>
            <Col lg={12} md={12} sm={24} xs={24} style={colStyle}>
              <ClusterWidget cat='cpu' title='widget.cluster.usage.cpu' api='v1/stats/cluster-cpu' color='#ffd375' />
            </Col>
            <Col lg={12} md={12} sm={24} xs={24} style={colStyle}>
              <ClusterWidget cat='mem' title='widget.cluster.usage.mem' api='v1/stats/cluster-mem' color='#b49eff' />
            </Col>
          </WidgetWrapper>
        </Col>
      </Row>
      <Row style={rowStyle} gutter={0} justify='start'>
        <Col lg={24} md={24} sm={24} xs={24} style={colStyle}>
          <WidgetTitle
            icon='ti-server'
            label='widget.storage.title'
            onClickUrl={`/monitoring/storage`}
          />
          <Col lg={8} md={24} sm={24} xs={24} style={colStyle}>
            <WidgetWrapper>
              <StorageWidget
                cat='bandwidth'
                api='v1/stats/storage-bandwidth'
                icon='ti-dashboard'
                title='widget.storage.usage.bandwidth'
                unit='widget.storage.usage.bandwidth.unit'
                color='red'
                chartColor='red'
              />
            </WidgetWrapper>
          </Col>
          <Col lg={8} md={24} sm={24} xs={24} style={colStyle}>
            <WidgetWrapper>
              <StorageWidget
                cat='iops'
                api='v1/stats/storage-iops'
                icon='ti-exchange-vertical'
                title='widget.storage.usage.iops'
                unit='widget.storage.usage.iops.unit'
                color='green'
                chartColor='green'
              />
            </WidgetWrapper>
          </Col>
          <Col lg={8} md={24} sm={24} xs={24} style={colStyle}>
            <WidgetWrapper>
              <StorageWidget
                cat='latency'
                api='v1/stats/storage-latency'
                icon='ti-timer'
                title='widget.storage.usage.latency'
                unit='widget.storage.usage.latency.unit'
                color='blue'
                chartColor='blue'
              />
            </WidgetWrapper>
          </Col>
        </Col>
      </Row>
      <Row style={rowStyle} gutter={0} justify='start'>
        <Col lg={24} md={24} sm={24} xs={24} style={colStyle}>
          <WidgetTitle
            icon='ti-clipboard'
            label='widget.operation.title'
            onClickUrl={`/monitoring/top_instance`}
          />
          <Col lg={8} md={24} sm={24} xs={24} style={colStyle}>
            <WidgetWrapper>
              <InfraWidget />
            </WidgetWrapper>
          </Col>
          <Col lg={16} md={24} sm={24} xs={24} style={colStyle}>
            <WidgetWrapper>
              <OperationWidget />
            </WidgetWrapper>
          </Col>
        </Col>
      </Row>
      <Row style={rowStyle} gutter={0} justify='start'>
        <Col lg={12} md={12} sm={24} xs={24} style={colStyle}>
          <WidgetTitle
            icon='ti-list'
            label='widget.topten.host.title'
            selId='host'
            selDef={0}
            selOptions={top10HostOptions}
          />
          <WidgetWrapper>
            <ToptenWidget
              cat='host'
              api='v1/stats/topten-host'
            />
          </WidgetWrapper>
        </Col>
        <Col lg={12} md={12} sm={24} xs={24} style={colStyle}>
          <WidgetTitle
            icon='ti-list'
            label='widget.topten.vm.title'
            selId='vm'
            selDef={0}
            selOptions={top10VmOptions}
          />
          <WidgetWrapper>
            <ToptenWidget
              cat='vm'
              api='v1/stats/topten-vm'
            />
          </WidgetWrapper>
        </Col>
      </Row>
    </WidgetsDiv>
  );
}

export default Widgets
