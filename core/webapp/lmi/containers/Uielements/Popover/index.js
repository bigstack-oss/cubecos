import React, { Component } from 'react';
import { Row, Col } from 'antd';
import Popover from '../../../components/uielements/popover';
import Button from '../../../components/uielements/button';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import IntlMessages from '../../../components/utility/intlMessages';
import PopoverWrapper from './popover.style';

// const Popover = props => (
//   <PopoverWrapper>
//     <Popovers {...props} />
//   </PopoverWrapper>
// );

const content = (
  <PopoverWrapper>
    <p>
      The most basic example. <br />
      The size of the floating layer depends
      <br /> on the contents region.
    </p>
    <p>Content</p>
  </PopoverWrapper>
);

export default class extends Component {
  state = {
    visible: false,
  };
  hide = () => {
    this.setState({
      visible: false,
    });
  };
  handleVisibleChange = visible => {
    this.setState({ visible });
  };
  render() {
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (
      <LayoutWrapper>
        <PageHeader>
          {<IntlMessages id="uiElements.popover.popover" />}
        </PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.popover.basicExample" />}
              subtitle={
                <IntlMessages id="uiElements.popover.basicExampleSubTitle" />
              }
            >
              <ContentHolder>
                <Popover
                  content={content}
                  title={<IntlMessages id="uiElements.popover.title" />}
                >
                  <Button type="primary">
                    {<IntlMessages id="uiElements.popover.hoverMe" />}
                  </Button>
                </Popover>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.popover.titleTrigger" />}
              subtitle={
                <IntlMessages id="uiElements.popover.titleTriggerSubTitle" />
              }
            >
              <ContentHolder>
                <Popover
                  content={content}
                  title={<IntlMessages id="uiElements.popover.title" />}
                  trigger="hover"
                >
                  <Button className="demoBtn">
                    {<IntlMessages id="uiElements.popover.hoverMe" />}
                  </Button>
                </Popover>
                <Popover
                  content={content}
                  title={<IntlMessages id="uiElements.popover.title" />}
                  trigger="focus"
                >
                  <Button className="demoBtn">
                    {<IntlMessages id="uiElements.popover.focusMe" />}
                  </Button>
                </Popover>
                <Popover
                  content={content}
                  title={<IntlMessages id="uiElements.popover.title" />}
                  trigger="click"
                >
                  <Button className="demoBtn">
                    {<IntlMessages id="uiElements.popover.clickMe" />}
                  </Button>
                </Popover>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col span={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.popover.placement" />}
              subtitle={
                <IntlMessages id="uiElements.popover.placementSubTitle" />
              }
            >
              <ContentHolder>
                <div className="demoBtnsWrapper">
                  <Popover
                    placement="topLeft"
                    title={<IntlMessages id="uiElements.popover.topLeft" />}
                    content={content}
                    trigger="click"
                  >
                    <Button className="demoPosBtn">
                      {<IntlMessages id="uiElements.popover.TL" />}
                    </Button>
                  </Popover>
                  <Popover
                    placement="top"
                    title={<IntlMessages id="uiElements.popover.top" />}
                    content={content}
                    trigger="click"
                  >
                    <Button className="demoPosBtn">
                      {<IntlMessages id="uiElements.popover.top" />}
                    </Button>
                  </Popover>
                  <Popover
                    placement="topRight"
                    title={<IntlMessages id="uiElements.popover.topRight" />}
                    content={content}
                    trigger="click"
                  >
                    <Button className="demoPosBtn">
                      {<IntlMessages id="uiElements.popover.TR" />}
                    </Button>
                  </Popover>
                </div>
                <div className="demoBtnsWrapper">
                  <Popover
                    placement="leftTop"
                    title={<IntlMessages id="uiElements.popover.leftTop" />}
                    content={content}
                    trigger="click"
                  >
                    <Button className="demoPosBtn">
                      {<IntlMessages id="uiElements.popover.LT" />}
                    </Button>
                  </Popover>
                  <Popover
                    placement="left"
                    title={<IntlMessages id="uiElements.popover.left" />}
                    content={content}
                    trigger="click"
                  >
                    <Button className="demoPosBtn">
                      {<IntlMessages id="uiElements.popover.left" />}
                    </Button>
                  </Popover>
                  <Popover
                    placement="leftBottom"
                    title={<IntlMessages id="uiElements.popover.leftBottom" />}
                    content={content}
                    trigger="click"
                  >
                    <Button className="demoPosBtn">
                      {<IntlMessages id="uiElements.popover.LB" />}
                    </Button>
                  </Popover>
                </div>
                <div className="demoBtnsWrapper">
                  <Popover
                    placement="rightTop"
                    title={<IntlMessages id="uiElements.popover.rightTop" />}
                    content={content}
                    trigger="click"
                  >
                    <Button className="demoPosBtn">
                      {<IntlMessages id="uiElements.popover.RT" />}
                    </Button>
                  </Popover>
                  <Popover
                    placement="right"
                    title={<IntlMessages id="uiElements.popover.right" />}
                    content={content}
                    trigger="click"
                  >
                    <Button className="demoPosBtn">
                      {<IntlMessages id="uiElements.popover.right" />}
                    </Button>
                  </Popover>
                  <Popover
                    placement="rightBottom"
                    title="Right Bottom"
                    content={content}
                    trigger="click"
                  >
                    <Button className="demoPosBtn">
                      {<IntlMessages id="uiElements.popover.RB" />}
                    </Button>
                  </Popover>
                </div>
                <div className="demoBtnsWrapper">
                  <Popover
                    placement="bottomLeft"
                    title={<IntlMessages id="uiElements.popover.bottomLeft" />}
                    content={content}
                    trigger="click"
                  >
                    <Button className="demoPosBtn">
                      {<IntlMessages id="uiElements.popover.BL" />}
                    </Button>
                  </Popover>
                  <Popover
                    placement="bottom"
                    title={<IntlMessages id="uiElements.popover.bottom" />}
                    content={content}
                    trigger="click"
                  >
                    <Button className="demoPosBtn">
                      {<IntlMessages id="uiElements.popover.bottom" />}
                    </Button>
                  </Popover>
                  <Popover
                    placement="bottomRight"
                    title={<IntlMessages id="uiElements.popover.bottomRight" />}
                    content={content}
                    trigger="click"
                  >
                    <Button className="demoPosBtn">
                      {<IntlMessages id="uiElements.popover.BR" />}
                    </Button>
                  </Popover>
                </div>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.popover.boxTitle" />}
              subtitle={<IntlMessages id="uiElements.popover.boxSubTitle" />}
            >
              <ContentHolder>
                <Popover
                  content={
                    <a onClick={this.hide}>
                      {<IntlMessages id="uiElements.popover.close" />}
                    </a>
                  }
                  title={<IntlMessages id="uiElements.popover.title" />}
                  trigger="click"
                  visible={this.state.visible}
                  onVisibleChange={this.handleVisibleChange}
                >
                  <Button type="primary">
                    {<IntlMessages id="uiElements.popover.clickMe" />}
                  </Button>
                </Popover>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
