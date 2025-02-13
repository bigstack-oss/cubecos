import React, { Component } from 'react';
import { Row, Col } from 'antd';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import IntlMessages from '../../../components/utility/intlMessages';
import Alert from '../../../components/feedback/alert';

export default class extends Component {
  onClose = function(e) {};

  render() {
    const { rowStyle, colStyle, gutter } = basicStyle;
    const marginBot = {
      marginBottom: '10px'
    };
    return (
      <LayoutWrapper>
        <PageHeader>Alert</PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="feedback.alert.basicTitle" />}>
              <ContentHolder>
                <Alert
                  message={<IntlMessages id="feedback.alert.successText" />}
                  type="success"
                  style={marginBot}
                />
                <Alert
                  message={<IntlMessages id="feedback.alert.infoText" />}
                  type="info"
                  style={marginBot}
                />
                <Alert
                  message={<IntlMessages id="feedback.alert.warningText" />}
                  type="warning"
                  style={marginBot}
                />
                <Alert
                  message={<IntlMessages id="feedback.alert.errorText" />}
                  type="error"
                />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="feedback.alert.closableAlertType" />}>
              <ContentHolder>
                <Alert
                  message={
                    <IntlMessages id="feedback.alert.warningDescription" />
                  }
                  type="warning"
                  closable
                  onClose={this.onClose}
                  style={marginBot}
                />
                <Alert
                  message={<IntlMessages id="feedback.alert.errorText" />}
                  description={
                    <IntlMessages id="feedback.alert.errorDescription" />
                  }
                  type="error"
                  closable
                  onClose={this.onClose}
                />
              </ContentHolder>
            </Box>
          </Col>
        </Row>

        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="feedback.alert.iconAlertType" />}>
              <ContentHolder>
                <Alert
                  message={<IntlMessages id="feedback.alert.successText" />}
                  type="success"
                  style={marginBot}
                />
                <Alert
                  message={<IntlMessages id="feedback.alert.infoText" />}
                  type="info"
                  style={marginBot}
                />
                <Alert
                  message={<IntlMessages id="feedback.alert.warningText" />}
                  type="warning"
                  style={marginBot}
                />
                <Alert
                  message={<IntlMessages id="feedback.alert.errorText" />}
                  type="error"
                />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title={<IntlMessages id="feedback.alert.iconInfoAlertType" />}>
              <ContentHolder>
                <Alert
                  message={<IntlMessages id="feedback.alert.successTips" />}
                  description={
                    <IntlMessages id="feedback.alert.successTipsDescription" />
                  }
                  type="success"
                  showIcon
                  style={marginBot}
                />
                <Alert
                  message={<IntlMessages id="feedback.alert.informationTips" />}
                  description={
                    <IntlMessages id="feedback.alert.informationDescription" />
                  }
                  type="info"
                  showIcon
                  style={marginBot}
                />
                <Alert
                  message={<IntlMessages id="feedback.alert.warningTips" />}
                  description={
                    <IntlMessages id="feedback.alert.warningDescription" />
                  }
                  type="warning"
                  showIcon
                  style={marginBot}
                />
                <Alert
                  message={<IntlMessages id="feedback.alert.errorTips" />}
                  description={
                    <IntlMessages id="feedback.alert.errorDescription" />
                  }
                  type="error"
                  showIcon
                />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
