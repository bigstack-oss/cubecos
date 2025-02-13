import React, { Component } from 'react';
import { Row, Col } from 'antd';
import Button, { ButtonGroup } from '../../../components/uielements/button';
import Progress from '../../../components/uielements/progress';
import PageHeader from '../../../components/utility/pageHeader';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import Box from '../../../components/utility/box';
import basicStyle from '../../../config/basicStyle';
import IntlMessages from '../../../components/utility/intlMessages';
import { rtl } from '../../../config/withDirection';

export default class extends Component {
  state = {
    percent: 0
  };
  increase = () => {
    let percent = this.state.percent + 10;
    if (percent > 100) {
      percent = 100;
    }
    this.setState({ percent });
  };
  decline = () => {
    let percent = this.state.percent - 10;
    if (percent < 0) {
      percent = 0;
    }
    this.setState({ percent });
  };
  render() {
    const { rowStyle, colStyle, gutter } = basicStyle;
    const marginStyle = {
      margin: rtl === 'rtl' ? '0 0 10px 10px' : '0 10px 10px 0'
    };
    return (
      <LayoutWrapper>
        <PageHeader>
          {<IntlMessages id="forms.progressBar.header" />}
        </PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.progressBar.standardTitle" />}
              subtitle={
                <IntlMessages id="forms.progressBar.standardSubTitle" />
              }
            >
              <Progress percent={30} style={marginStyle} />
              <Progress percent={50} status="active" style={marginStyle} />
              <Progress percent={70} status="exception" style={marginStyle} />
              <Progress percent={100} style={marginStyle} />
              <Progress percent={50} showInfo={false} style={marginStyle} />
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.progressBar.circularTitle" />}
              subtitle={
                <IntlMessages id="forms.progressBar.circularSubTitle" />
              }
            >
              <Progress type="circle" percent={75} style={marginStyle} />
              <Progress
                type="circle"
                percent={70}
                status="exception"
                style={marginStyle}
              />
              <Progress type="circle" percent={100} style={marginStyle} />
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={8} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.progressBar.miniTitle" />}
              subtitle={<IntlMessages id="forms.progressBar.miniSubTitle" />}
            >
              <Progress percent={30} strokeWidth={5} style={marginStyle} />
              <Progress
                percent={50}
                strokeWidth={5}
                status="active"
                style={marginStyle}
              />
              <Progress
                percent={70}
                strokeWidth={5}
                status="exception"
                style={marginStyle}
              />
              <Progress percent={100} strokeWidth={5} style={marginStyle} />
            </Box>
          </Col>
          <Col md={8} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.progressBar.miniCircularTitle" />}
              subtitle={
                <IntlMessages id="forms.progressBar.miniCircularTitle" />
              }
            >
              <Progress
                type="circle"
                percent={30}
                width={80}
                style={marginStyle}
              />
              <Progress
                type="circle"
                percent={70}
                width={80}
                status="exception"
                style={marginStyle}
              />
              <Progress
                type="circle"
                percent={100}
                width={80}
                style={marginStyle}
              />
            </Box>
          </Col>
          <Col md={8} xs={24} style={colStyle}>
            <Box
              title={
                <IntlMessages id="forms.progressBar.dynamicCircularTitle" />
              }
              subtitle={
                <IntlMessages id="forms.progressBar.dynamicCircularSubTitle" />
              }
            >
              <Progress
                type="circle"
                percent={this.state.percent}
                style={marginStyle}
              />
              <ButtonGroup>
                <Button onClick={this.decline} icon="minus" />
                <Button onClick={this.increase} icon="plus" />
              </ButtonGroup>
            </Box>
          </Col>
        </Row>

        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.progressBar.customTextTitle" />}
              subtitle={
                <IntlMessages id="forms.progressBar.customTextSubTitle" />
              }
            >
              <Progress
                type="circle"
                percent={75}
                format={percent => `${percent} Days`}
                style={marginStyle}
              />
              <Progress
                type="circle"
                percent={100}
                format={() => 'Done'}
                style={marginStyle}
              />
            </Box>
          </Col>

          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.progressBar.dashboardTitle" />}
              subtitle={
                <IntlMessages id="forms.progressBar.dashboardSubTitle" />
              }
            >
              <Progress type="dashboard" percent={75} />
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
