import React, { Component } from 'react';
import { Row, Col, Icon } from 'antd';
import notifications from '../../../components/feedback/notification';
import Button from '../../../components/uielements/button';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import IntlMessages from '../../../components/utility/intlMessages';
import NotificationContent from './notification.style';

const openNotification = () => {
  const args = {
    message: 'Notification Title',
    description: (
      <NotificationContent>
        I will close after 2 seconds automatically. I will be close
        automatically. I will never close automatically.
      </NotificationContent>
    )
  };
  notifications.open(args);
};

const customDurationNotification = () => {
  const args = {
    message: 'Notification Title',
    description:
      'I will never close automatically. Click the close button. I will be close automatically. I will never close automatically.',
    duration: 0
  };
  notifications.open(args);
};

const openNotificationWithIcon = type => {
  notifications[type]({
    message: 'Notification Title',
    description:
      'This is the content of the notification. This is the content of the notification. This is the content of the notification.'
  });
};

const openNotificationCustomIcon = () => {
  notifications.open({
    message: 'Notification Title',
    description:
      'This is the content of the notification. This is the content of the notification. This is the content of the notification.',
    icon: <Icon type="smile-circle" style={{ color: '#4482FF' }} />
  });
};

const close = () => {};

const openNotificationWithConfirm = () => {
  const key = `open${Date.now()}`;
  const btnClick = function() {
    notifications.close(key);
  };
  const btn = (
    <Button type="primary" size="small" onClick={btnClick}>
      Confirm
    </Button>
  );
  notifications.open({
    message: 'Notification Title',
    description:
      'A function will be be called after the notification is closed (automatically after the "duration" time of manually).',
    btn,
    key,
    onClose: close
  });
};

export default class extends Component {
  render() {
    const { rowStyle, colStyle, gutter } = basicStyle;
    const marginStyle = { marginRight: '5px' };

    return (
      <LayoutWrapper>
        <PageHeader>
          {<IntlMessages id="feedback.alert.notification" />}
        </PageHeader>

        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={
                <IntlMessages id="feedback.alert.notificationBasicTitle" />
              }
              subtitle={
                <IntlMessages id="feedback.alert.notificationBasicSubTitle" />
              }
            >
              <ContentHolder>
                <Button type="primary" onClick={openNotification}>
                  {
                    <IntlMessages id="feedback.alert.notificationBasicDescription" />
                  }
                </Button>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={
                <IntlMessages id="feedback.alert.notificationDurationTitle" />
              }
              subtitle={
                <IntlMessages id="feedback.alert.notificationDurationSubTitle" />
              }
            >
              <ContentHolder>
                <Button type="primary" onClick={customDurationNotification}>
                  {
                    <IntlMessages id="feedback.alert.notificationBasicDescription" />
                  }
                </Button>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={
                <IntlMessages id="feedback.alert.notificationwithIconTitle" />
              }
              subtitle={
                <IntlMessages id="feedback.alert.notificationwithIconSubTitle" />
              }
            >
              <ContentHolder>
                <Button
                  onClick={() => openNotificationWithIcon('success')}
                  style={marginStyle}
                >
                  {<IntlMessages id="feedback.alert.successTitle" />}
                </Button>
                <Button
                  onClick={() => openNotificationWithIcon('info')}
                  style={marginStyle}
                >
                  {<IntlMessages id="feedback.alert.infoTitle" />}
                </Button>
                <Button
                  onClick={() => openNotificationWithIcon('warning')}
                  style={marginStyle}
                >
                  {<IntlMessages id="feedback.alert.warningTitle" />}
                </Button>
                <Button onClick={() => openNotificationWithIcon('error')}>
                  {<IntlMessages id="feedback.alert.errorTitle" />}
                </Button>
              </ContentHolder>
            </Box>
          </Col>

          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={
                <IntlMessages id="feedback.alert.notificationwithCustomIconTitle" />
              }
              subtitle={
                <IntlMessages id="feedback.alert.notificationwithCustomIconSubTitle" />
              }
            >
              <ContentHolder>
                <Button type="primary" onClick={openNotificationCustomIcon}>
                  {
                    <IntlMessages id="feedback.alert.notificationBasicDescription" />
                  }
                </Button>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={
                <IntlMessages id="feedback.alert.notificationwithCustomButtonTitle" />
              }
              subtitle={
                <IntlMessages id="feedback.alert.notificationwithCustomButtonSubTitle" />
              }
            >
              <ContentHolder>
                <Button type="primary" onClick={openNotificationWithConfirm}>
                  {
                    <IntlMessages id="feedback.alert.notificationBasicDescription" />
                  }
                </Button>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
