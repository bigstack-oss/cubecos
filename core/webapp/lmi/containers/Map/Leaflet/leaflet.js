import React, { Component } from 'react';
import { Row, Col } from 'antd';
import Async from '../../../helpers/asyncComponent';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import PageHeader from '../../../components/utility/pageHeader';
import ContentHolder from '../../../components/utility/contentHolder';
import IntlMessages from '../../../components/utility/intlMessages';
import Box from '../../../components/utility/box';
import basicStyle from '../../../config/basicStyle';
import { mapboxConfig } from '../../../config';

const BasicLeafletMap = props => (
  <Async
    load={import(/* webpackChunkName: "basicLeafletMap" */ './maps/basic')}
    componentProps={props}
    componentArguement={'leafletMap'}
  />
);
const BasicLeafletMapWithMarker = props => (
  <Async
    load={import(/* webpackChunkName: "basicLeafletMapWithMarker" */ './maps/mapWithDefaultMarker.js')}
    componentProps={props}
    componentArguement={'leafletMap'}
  />
);
const LeafletMapWithCustomIconMarker = props => (
  <Async
    load={import(/* webpackChunkName: "LeafletMapWithCustomMarker" */ './maps/mapWithCustomIconMarker.js')}
    componentProps={props}
    componentArguement={'leafletMap'}
  />
);
const LeafletMapWithCustomHtmlMarker = props => (
  <Async
    load={import(/* webpackChunkName: "LeafletMapWithCustomHtmlMarker" */ './maps/mapWithCustomHtmlMarker.js')}
    componentProps={props}
    componentArguement={'leafletMap'}
  />
);
const LeafletMapWithMarkerCluster = props => (
  <Async
    load={import(/* webpackChunkName: "LeafletMapWithMarkerCluster" */ './maps/mapWithMarkerCluster.js')}
    componentProps={props}
    componentArguement={'leafletMap'}
  />
);
const LeafletMapWithRouting = props => (
  <Async
    load={import(/* webpackChunkName: "LeafletMapWithCustomMarker" */ './maps/mapWithRouting.js')}
    componentProps={props}
    componentArguement={'leafletMap'}
  />
);

export default class extends Component {
  render() {
    const { rowStyle, colStyle, gutter } = basicStyle;
    if (!mapboxConfig.tileLayer || !mapboxConfig.tileLayer) {
      return <h1>123</h1>;
    }
    return (
      <LayoutWrapper>
        <PageHeader>Leaflet Map</PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="Map.leaflet.basicTitle" />}>
              <ContentHolder>
                <BasicLeafletMap />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="Map.leaflet.basicMarkerTitle" />}>
              <ContentHolder>
                <BasicLeafletMapWithMarker />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="Map.leaflet.leafletCustomMarkerTitle" />}
            >
              <ContentHolder>
                <LeafletMapWithCustomIconMarker />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={
                <IntlMessages id="Map.leaflet.leafletCustomHtmlMarkerTitle" />
              }
            >
              <ContentHolder>
                <LeafletMapWithCustomHtmlMarker />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={
                <IntlMessages id="Map.leaflet.leafletMarkerClusterTitle" />
              }
            >
              <ContentHolder>
                <LeafletMapWithMarkerCluster />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="Map.leaflet.leafletRoutingTitle" />}>
              <ContentHolder>
                <LeafletMapWithRouting />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
