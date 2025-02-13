import React, { Component } from 'react';
import { Row, Col } from 'antd';
import Collapses from '../../../components/uielements/collapse';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import IntlMessages from '../../../components/utility/intlMessages';
import CollapseWrapper from './collapse.style';

const text = <IntlMessages id="uiElements.collapse.text" />;
const Panel = Collapses.Panel;
const Collapse = props => (
  <CollapseWrapper>
    <Collapses {...props}>{props.children}</Collapses>
  </CollapseWrapper>
);

export default class extends Component {
  callback = key => {};
  render() {
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (
      <LayoutWrapper>
        <PageHeader>
          {<IntlMessages id="uiElements.collapse.collapse" />}
        </PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.collapse.collapse" />}
              subtitle={
                <IntlMessages id="uiElements.collapse.collapseSubTitle" />
              }
            >
              <ContentHolder>
                <Collapse accordion>
                  <Panel
                    header={<IntlMessages id="uiElements.collapse.headerOne" />}
                    key="1"
                  >
                    <p>{text}</p>
                  </Panel>
                  <Panel
                    header={<IntlMessages id="uiElements.collapse.headerTwo" />}
                    key="2"
                  >
                    <p>{text}</p>
                  </Panel>
                  <Panel
                    header={
                      <IntlMessages id="uiElements.collapse.headerThree" />
                    }
                    key="3"
                  >
                    <p>{text}</p>
                  </Panel>
                </Collapse>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.collapse.nestedExample" />}
              subtitle={
                <IntlMessages id="uiElements.collapse.nestedExampleSubTitle" />
              }
            >
              <ContentHolder>
                <Collapse onChange={this.callback}>
                  <Panel
                    header={<IntlMessages id="uiElements.collapse.headerOne" />}
                    key="1"
                  >
                    <Collapse defaultActiveKey="1">
                      <Panel
                        header={
                          <IntlMessages id="uiElements.collapse.headerNested" />
                        }
                        key="1"
                      >
                        <p>{text}</p>
                      </Panel>
                    </Collapse>
                  </Panel>
                  <Panel
                    header={<IntlMessages id="uiElements.collapse.headerTwo" />}
                    key="2"
                  >
                    <p>{text}</p>
                  </Panel>
                  <Panel
                    header={
                      <IntlMessages id="uiElements.collapse.headerThree" />
                    }
                    key="3"
                  >
                    <p>{text}</p>
                  </Panel>
                </Collapse>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={
                <IntlMessages id="uiElements.collapse.borderlessExample" />
              }
              subtitle={
                <IntlMessages id="uiElements.collapse.borderlessExampleSubTitle" />
              }
            >
              <ContentHolder>
                <Collapse bordered={false} defaultActiveKey={['1']}>
                  <Panel
                    header={<IntlMessages id="uiElements.collapse.headerOne" />}
                    key="1"
                  >
                    <p>{text}</p>
                  </Panel>
                  <Panel
                    header={<IntlMessages id="uiElements.collapse.headerTwo" />}
                    key="2"
                  >
                    <p>{text}</p>
                  </Panel>
                  <Panel
                    header={
                      <IntlMessages id="uiElements.collapse.headerThree" />
                    }
                    key="3"
                  >
                    <p>{text}</p>
                  </Panel>
                </Collapse>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.collapse.accordion" />}
              subtitle={
                <IntlMessages id="uiElements.collapse.accordionSubTitle" />
              }
            >
              <ContentHolder>
                <Collapse accordion>
                  <Panel
                    header={<IntlMessages id="uiElements.collapse.headerOne" />}
                    key="1"
                  >
                    <p>{text}</p>
                  </Panel>
                  <Panel
                    header={<IntlMessages id="uiElements.collapse.headerTwo" />}
                    key="2"
                  >
                    <p>{text}</p>
                  </Panel>
                  <Panel
                    header={
                      <IntlMessages id="uiElements.collapse.headerThree" />
                    }
                    key="3"
                  >
                    <p>{text}</p>
                  </Panel>
                </Collapse>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
