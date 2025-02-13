import React, { Component } from 'react';
import { Row, Col, Icon } from 'antd';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import IntlMessages from '../../../components/utility/intlMessages';
import Timeline, {
  TimelineItem,
} from '../../../components/uielements/timeline';

export default class extends Component {
  render() {
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (
      <LayoutWrapper>
        <PageHeader>
          {<IntlMessages id="uiElements.timeline.timeline" />}
        </PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.timeline.basicExample" />}
              subtitle={<IntlMessages id="uiElements.timeline.basicTimeline" />}
            >
              <ContentHolder>
                <Timeline>
                  <TimelineItem>
                    {
                      <IntlMessages id="uiElements.timeline.createServiceSite" />
                    }
                  </TimelineItem>
                  <TimelineItem>
                    {
                      <IntlMessages id="uiElements.timeline.solveInitialNetwork" />
                    }
                  </TimelineItem>
                  <TimelineItem>
                    {<IntlMessages id="uiElements.timeline.technicalTesting" />}
                  </TimelineItem>
                  <TimelineItem>
                    {
                      <IntlMessages id="uiElements.timeline.networkProblemSolved" />
                    }
                  </TimelineItem>
                </Timeline>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.timeline.colorExample" />}
              subtitle={
                <IntlMessages id="uiElements.timeline.colorExampleContent" />
              }
            >
              <ContentHolder>
                <Timeline>
                  <TimelineItem color="green">
                    Create a services site 2015-09-01
                  </TimelineItem>
                  <TimelineItem color="green">
                    Create a services site 2015-09-01
                  </TimelineItem>
                  <TimelineItem color="red">
                    <p>Solve initial network problems 1</p>
                    <p>Solve initial network problems 2</p>
                    <p>Solve initial network problems 3 2015-09-01</p>
                  </TimelineItem>
                  <TimelineItem>
                    <p>Technical testing 1</p>
                    <p>Technical testing 2</p>
                    <p>Technical testing 3 2015-09-01</p>
                  </TimelineItem>
                </Timeline>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.timeline.custom" />}
              subtitle={<IntlMessages id="uiElements.timeline.customContent" />}
            >
              <ContentHolder>
                <Timeline>
                  <TimelineItem>Create a services site 2015-09-01</TimelineItem>
                  <TimelineItem>
                    Solve initial network problems 2015-09-01
                  </TimelineItem>
                  <TimelineItem
                    dot={
                      <Icon
                        type="clock-circle-o"
                        style={{ fontSize: '16px' }}
                      />
                    }
                    color="red"
                  >
                    Technical testing 2015-09-01
                  </TimelineItem>
                  <TimelineItem>
                    Network problems being solved 2015-09-01
                  </TimelineItem>
                </Timeline>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.timeline.lastNode" />}
              subtitle={
                <IntlMessages id="uiElements.timeline.lastNodeContent" />
              }
            >
              <ContentHolder>
                <Timeline
                  pending={
                    <a>{<IntlMessages id="uiElements.timeline.seeMore" />}</a>
                  }
                >
                  <TimelineItem>Create a services site 2015-09-01</TimelineItem>
                  <TimelineItem>
                    Solve initial network problems 2015-09-01
                  </TimelineItem>
                  <TimelineItem>Technical testing 2015-09-01</TimelineItem>
                </Timeline>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
