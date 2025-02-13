import React, { Component } from 'react';
import { Row, Col } from 'antd';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import BasicTree from './basicTree';
import BasicControlledTree from './basicControlledTree';
import DraggableTree from './draggableTree';
import AsyncTree from './asyncTree';
import SearchableTree from './searchableTree';
import LineTree from './lineTree';
import IntlMessages from '../../../components/utility/intlMessages';

export default class extends Component {
  render() {
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (
      <LayoutWrapper>
        <PageHeader>{<IntlMessages id="uiElements.tree.tree" />}</PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.tree.basicExample" />}
              subtitle={<IntlMessages id="uiElements.tree.basicExampleSubTitle" />}
            >
              <ContentHolder>
                <BasicTree />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.tree.basicControlledExample" />}
              subtitle={<IntlMessages id="uiElements.tree.tree" />}
            >
              <ContentHolder>
                <BasicControlledTree />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.tree.draggableExample" />}
              subtitle={<IntlMessages id="uiElements.tree.draggableExampleSubTitle" />}
            >
              <ContentHolder>
                <DraggableTree />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.tree.loadAsync" />}
              subtitle={<IntlMessages id="uiElements.tree.loadAsyncSubTitle" />}
            >
              <ContentHolder>
                <AsyncTree />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.tree.searchableExample" />}
              subtitle={<IntlMessages id="uiElements.tree.searchableExampleSubTitle" />}
            >
              <ContentHolder>
                <SearchableTree />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.tree.treeWithLine" />}
              subtitle={<IntlMessages id="uiElements.tree.treeWithLine" />}
            >
              <ContentHolder>
                <LineTree />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
