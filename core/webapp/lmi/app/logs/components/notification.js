// logs/components/notification.js

import React from 'react';
import createReactClass from 'create-react-class';
import { injectIntl } from 'react-intl';

import * as c from '../constant';

import { Col, Row, Icon, Spin } from 'antd';
import Form from '../../../components/uielements/form';
import Input, { InputGroup } from '../../../components/uielements/input';
import Radio, { RadioGroup } from '../../../components/uielements/radio';
import Button from '../../../components/uielements/button';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import IntlMessages from '../../../components/utility/intlMessages';

const FormItem = Form.Item;

const rowStyle = {
  width: '100%',
  display: 'flex',
  flexFlow: 'row wrap'
};
const colStyle = {
  marginBottom: '16px'
};
const gutter = 16;

const Response = ({ intl, form, prefix, titleId, subId, rec, onSubmitAct, setType, tenantId, role }) => {
  const { getFieldDecorator, getFieldValue, validateFieldsAndScroll } = form;

  const ids = {
    enabled: prefix + 'Enabled',
    type: prefix + 'Type',
    url: prefix + 'Url',
    channel: prefix + 'Channel',
    host: prefix + 'Host',
    port: prefix + 'Port',
    username: prefix + 'Username',
    password: prefix + 'Password',
    from: prefix + 'From',
    to: prefix + 'To',
  }

  const onSubmit = e => {
    e.preventDefault();

    const fields = {
      slack: [ ids.url, ids.channel ],
      email: [ ids.host, ids.port, ids.username, ids.password, ids.from, ids.to ],
    };

    validateFieldsAndScroll(fields[getFieldValue(ids.type)], (err, values) => {
      if (!err) {
        onSubmitAct(rec, {
          enabled: getFieldValue(ids.enabled),
          type: getFieldValue(ids.type),
          ...values
        }, tenantId, role);
      }
    });
  }

  const onTypeChange = e => {
    e.preventDefault();
    setType(e.target.value);
  }

  return (
    <Row style={rowStyle} gutter={gutter} justify='start'>
      <Col md={24} sm={24} xs={24} style={colStyle}>
        <Spin tip='applying policies...' spinning={rec.loading || false }>
          <Box title={<IntlMessages id={titleId} />} subtitle={<IntlMessages id={subId} />} >
            <ContentHolder>
              <Form onSubmit={onSubmit}>
                <FormItem>
                  {getFieldDecorator(ids.enabled, {
                    initialValue: rec.enabled,
                  })(
                    <RadioGroup>
                      <Radio value={false}>Disabled</Radio>
                      <Radio value={true}>Enabled</Radio>
                    </RadioGroup>
                  )}
                </FormItem>
                <FormItem>
                  {getFieldDecorator(ids.type, {
                    initialValue: rec.type,
                  })(
                    <RadioGroup onChange={onTypeChange}>
                      <Radio value='email'>E-mail</Radio>
                      <Radio value='slack'>Slack</Radio>
                    </RadioGroup>
                  )}
                </FormItem>
                { rec.type == 'slack' &&
                  <div>
                    <FormItem hasFeedback>
                      {getFieldDecorator(ids.url, {
                        initialValue: rec.url,
                        rules: [
                          { required: true, type: 'url', message: intl.formatMessage({id: 'logs.notify.slack.url.error'}) },
                        ]
                      })(<span><Input name={ids.url} id={ids.url} placeholder='URL' defaultValue={rec.url} /></span>)}
                    </FormItem>
                    <FormItem hasFeedback>
                      {getFieldDecorator(ids.channel, {
                        initialValue: rec.channel == 'null' ? '' : rec.channel,
                        rules: [
                          { required: false, message: intl.formatMessage({id: 'logs.notify.slack.channel.error'}) },
                        ]
                      })(<span><Input name={ids.channel} id={ids.channel} placeholder='Channel' defaultValue={rec.channel} /></span>)}
                    </FormItem>
                  </div>
                }
                { rec.type == 'email' &&
                  <div>
                    <FormItem hasFeedback>
                      {getFieldDecorator(ids.host, {
                        initialValue: rec.host,
                        rules: [
                          { required: true, message: intl.formatMessage({id: 'logs.notify.email.host.error'}) },
                        ]
                      })(<span><Input name={ids.host} id={ids.host} placeholder='Host' defaultValue={rec.host} /></span>)}
                    </FormItem>
                    <FormItem hasFeedback>
                      {getFieldDecorator(ids.port, {
                        initialValue: rec.port,
                        rules: [
                          { required: true,
                            type: 'number',
                            min: 0,
                            max: 65535,
                            initialValue: rec.port,
                            message: intl.formatMessage({id: 'logs.notify.email.port.error'}),
                            transform: v => parseInt(v),
                          },
                        ]
                      })(<span><Input name={ids.port} id={ids.port} placeholder='Port (0~65535)' defaultValue={rec.port} /></span>)}
                    </FormItem>
                    <FormItem hasFeedback>
                      {getFieldDecorator(ids.username, {
                        initialValue: rec.username,
                        rules: [
                          { required: true, message: intl.formatMessage({id: 'logs.notify.email.username.error'}) },
                        ]
                      })(<span><Input name={ids.username} id={ids.username} placeholder='Username' defaultValue={rec.username} /></span>)}
                    </FormItem>
                    <FormItem hasFeedback>
                      {getFieldDecorator(ids.password, {
                        rules: [
                          { required: true, message: intl.formatMessage({id: 'logs.notify.email.password.error'}) },
                        ]
                      })(<span><Input name={ids.password} id={ids.password} type='password' placeholder='Password' /></span>)}
                    </FormItem>
                    <FormItem hasFeedback>
                      {getFieldDecorator(ids.from, {
                        initialValue: rec.from,
                        rules: [
                          { required: true, message: intl.formatMessage({id: 'logs.notify.email.from.error'}) },
                        ]
                      })(<span><Input name={ids.from} id={ids.from} placeholder='From address (e.g. abc@abc.com)' defaultValue={rec.from} /></span>)}
                    </FormItem>
                    <FormItem hasFeedback>
                      {getFieldDecorator(ids.to, {
                        initialValue: rec.to,
                        rules: [
                          { required: true, message: intl.formatMessage({id: 'logs.notify.email.to.error'}) },
                        ]
                      })(<span><Input name={ids.to} id={ids.to} placeholder='To address list (e.g. abc@abc.com,...)' defaultValue={rec.to} /></span>)}
                    </FormItem>
                  </div>
                }
                <Button type='primary' htmlType='submit'>
                  <IntlMessages id='logs.notify.apply' />
                </Button>
              </Form>
            </ContentHolder>
          </Box>
        </Spin>
      </Col>
    </Row>

  )
}

const Notification = createReactClass({
  getInitialState: function() {
    return { initial: true };
  },

  componentDidMount: function() {
    this.setState({ initial: true })
  },

  componentWillUnmount: function() {
    this.setState({ initial: true })
  },

  render: function() {
    const { intl, form, role, tenantId,
          adminResp, instanceResp,
          fetchAdminResp, fetchInstanceResp,
          setAdminRespType, setInstanceRespType,
          updateAdminResp, updateInstanceResp } = this.props;

    if (this.state.initial) {
      if (role == 'admin') {
        fetchAdminResp();
      }
      else if (role == '_member_') {
        fetchInstanceResp(tenantId);
      }
      this.setState({ initial: false });
    }

    return (
      <LayoutWrapper>
        <PageHeader>
          <IntlMessages id='logs.notify.header' />
        </PageHeader>
        {role == 'admin' &&
          <Response
            prefix='admin'
            intl={intl}
            form={form}
            titleId='logs.notifiy.admin.title'
            subId='logs.notifiy.admin.subtitle'
            rec={adminResp}
            onSubmitAct={updateAdminResp}
            setType={setAdminRespType}
            role={role}
          />
        }
        <Response
          prefix='instance'
          intl={intl}
          form={form}
          titleId='logs.notifiy.instance.title'
          subId='logs.notifiy.instance.subtitle'
          rec={instanceResp}
          onSubmitAct={updateInstanceResp}
          setType={setInstanceRespType}
          tenantId={tenantId}
          role={role}
        />
      </LayoutWrapper>
    );
  }
});

export default Form.create()(injectIntl(Notification));