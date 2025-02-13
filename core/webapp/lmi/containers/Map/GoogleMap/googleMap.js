import React, { Component } from 'react';
import { Row, Col } from 'antd';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import PageHeader from '../../../components/utility/pageHeader';
import ContentHolder from '../../../components/utility/contentHolder';
import Box from '../../../components/utility/box';
import basicStyle from '../../../config/basicStyle';
import BasicMap from './maps/basic';
import BasicMarker from './maps/basicMarker';
import IntlMessages from '../../../components/utility/intlMessages';

export default class extends Component {
  render() {
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (
      <LayoutWrapper>
        <PageHeader>Google Map</PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="Map.leaflet.basicTitle" />}>
              <ContentHolder>
                <BasicMap />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="Map.leaflet.leafletCustomMarkerTitle" />}
            >
              <ContentHolder>
                <BasicMarker />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
