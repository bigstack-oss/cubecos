import React, { Component } from 'react';
import { Row, Col } from 'antd';
import Tooltip from '../../../components/uielements/tooltip';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import IntlMessages from '../../../components/utility/intlMessages';

const text = (
  <span>{<IntlMessages id="uiElements.tooltip.contentSpan" />}</span>
);

export default class extends Component {
  render() {
    const { rowStyle, colStyle, gutter } = basicStyle;

    return (
      <LayoutWrapper>
        <PageHeader>
          {<IntlMessages id="uiElements.tooltip.tooltip" />}
        </PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.tooltip.basicExample" />}
              subtitle={
                <IntlMessages id="uiElements.tooltip.basicExampleSubTitle" />
              }
            >
              <ContentHolder>
                <Tooltip
                  title={
                    <IntlMessages id="uiElements.tooltip.tooltipContent" />
                  }
                >
                  <span>
                    {
                      <IntlMessages id="uiElements.tooltip.tooltipContentSpan" />
                    }
                  </span>
                </Tooltip>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.tooltip.placementTitle" />}
              subtitle={
                <IntlMessages id="uiElements.tooltip.placementSubTitle" />
              }
            >
              <ContentHolder>
                <div className="demoBtnsWrapper">
                  <Tooltip placement="topLeft" title={text}>
                    <a className="tooltipBtn">
                      {<IntlMessages id="uiElements.tooltip.TL" />}
                    </a>
                  </Tooltip>
                  <Tooltip placement="top" title={text}>
                    <a className="tooltipBtn">
                      {<IntlMessages id="uiElements.tooltip.top" />}
                    </a>
                  </Tooltip>
                  <Tooltip placement="topRight" title={text}>
                    <a className="tooltipBtn">
                      {<IntlMessages id="uiElements.tooltip.TR" />}
                    </a>
                  </Tooltip>
                </div>
                <div className="demoBtnsWrapper">
                  <Tooltip placement="leftTop" title={text}>
                    <a className="tooltipBtn">
                      {<IntlMessages id="uiElements.tooltip.LT" />}
                    </a>
                  </Tooltip>
                  <Tooltip placement="left" title={text}>
                    <a className="tooltipBtn">
                      {<IntlMessages id="uiElements.tooltip.left" />}
                    </a>
                  </Tooltip>
                  <Tooltip placement="leftBottom" title={text}>
                    <a className="tooltipBtn">
                      {<IntlMessages id="uiElements.tooltip.LB" />}
                    </a>
                  </Tooltip>
                </div>
                <div className="demoBtnsWrapper">
                  <Tooltip placement="rightTop" title={text}>
                    <a className="tooltipBtn">
                      {<IntlMessages id="uiElements.tooltip.RT" />}
                    </a>
                  </Tooltip>
                  <Tooltip placement="right" title={text}>
                    <a className="tooltipBtn">
                      {<IntlMessages id="uiElements.tooltip.right" />}
                    </a>
                  </Tooltip>
                  <Tooltip placement="rightBottom" title={text}>
                    <a className="tooltipBtn">
                      {<IntlMessages id="uiElements.tooltip.RB" />}
                    </a>
                  </Tooltip>
                </div>
                <div className="demoBtnsWrapper">
                  <Tooltip placement="bottomLeft" title={text}>
                    <a className="tooltipBtn">
                      {<IntlMessages id="uiElements.tooltip.BL" />}
                    </a>
                  </Tooltip>
                  <Tooltip placement="bottom" title={text}>
                    <a className="tooltipBtn">
                      {<IntlMessages id="uiElements.tooltip.bottom" />}
                    </a>
                  </Tooltip>
                  <Tooltip placement="bottomRight" title={text}>
                    <a className="tooltipBtn">
                      {<IntlMessages id="uiElements.tooltip.BR" />}
                    </a>
                  </Tooltip>
                </div>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
