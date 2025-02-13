import React, { Component } from 'react';
import { Col, Row, Icon } from 'antd';
import Input, {
  InputSearch,
  InputGroup,
  Textarea
} from '../../../components/uielements/input';
import InputNumber from '../../../components/uielements/InputNumber';
import Select, { SelectOption } from '../../../components/uielements/select';
import DatePicker from '../../../components/uielements/datePicker';
import AutoComplete from '../../../components/uielements/autocomplete';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import IntlMessages from '../../../components/utility/intlMessages';

const Option = SelectOption;

const selectBefore = (
  <Select defaultValue="Http://" style={{ width: 80 }}>
    <Option value="Http://">Http://</Option>
    <Option value="Https://">Https://</Option>
  </Select>
);
const selectAfter = (
  <Select defaultValue=".com" style={{ width: 70 }}>
    <Option value=".com">.com</Option>
    <Option value=".jp">.jp</Option>
    <Option value=".cn">.cn</Option>
    <Option value=".org">.org</Option>
  </Select>
);

export default class extends Component {
  state = {
    dataSource: []
  };
  handleChange = value => {
    this.setState({
      dataSource:
        !value || value.indexOf('@') >= 0
          ? []
          : [`${value}@gmail.com`, `${value}@163.com`, `${value}@qq.com`]
    });
  };

  render() {
    const rowStyle = {
      width: '100%',
      display: 'flex',
      flexFlow: 'row wrap'
    };
    const colStyle = {
      marginBottom: '16px'
    };
    const gutter = 16;
    return (
      <LayoutWrapper>
        <PageHeader>
          <IntlMessages id="forms.input.header" />
        </PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.input.basicTitle" />}
              subtitle={<IntlMessages id="forms.input.basicSubTitle" />}
            >
              <ContentHolder>
                <Input placeholder="Basic usage" />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.input.variationsTitle" />}
              subtitle={<IntlMessages id="forms.input.variationsSubtitle" />}
            >
              <ContentHolder>
                <Input
                  size="large"
                  placeholder="large size"
                  style={{ marginBottom: '15px' }}
                />
                <Input
                  placeholder="default size"
                  style={{ marginBottom: '15px' }}
                />
                <Input size="small" placeholder="small size" />
              </ContentHolder>
            </Box>
          </Col>
        </Row>

        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={24} sm={24} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.input.groupTitle" />}
              subtitle={<IntlMessages id="forms.input.groupSubTitle" />}
            >
              <ContentHolder>
                <InputGroup size="large" style={{ marginBottom: '15px' }}>
                  <Col span="4">
                    <Input defaultValue="0571" />
                  </Col>
                  <Col span="8">
                    <Input defaultValue="26888888" />
                  </Col>
                </InputGroup>

                <InputGroup compact style={{ marginBottom: '15px' }}>
                  <Input style={{ width: '20%' }} defaultValue="0571" />
                  <Input style={{ width: '30%' }} defaultValue="26888888" />
                </InputGroup>

                <InputGroup compact style={{ marginBottom: '15px' }}>
                  <Select defaultValue="Zhejiang">
                    <Option value="Zhejiang">Zhejiang</Option>
                    <Option value="Jiangsu">Jiangsu</Option>
                  </Select>
                  <Input
                    style={{ width: '50%' }}
                    defaultValue="Xihu District, Hangzhou"
                  />
                </InputGroup>

                <InputGroup compact style={{ marginBottom: '15px' }}>
                  <Select defaultValue="Option1" style={{ width: '33%' }}>
                    <Option value="Option1">Option1</Option>
                    <Option value="Option2">Option2</Option>
                  </Select>
                  <Input
                    style={{ width: '33%' }}
                    defaultValue="input content"
                  />
                  <InputNumber style={{ width: '33%' }} />
                </InputGroup>

                <InputGroup compact style={{ marginBottom: '15px' }}>
                  <Input
                    style={{ width: '50%' }}
                    defaultValue="input content"
                  />
                  <DatePicker />
                </InputGroup>

                <InputGroup compact style={{ marginBottom: '15px' }}>
                  <Select defaultValue="Option1-1">
                    <Option value="Option1-1">Option1-1</Option>
                    <Option value="Option1-2">Option1-2</Option>
                  </Select>
                  <Select defaultValue="Option2-2">
                    <Option value="Option2-1">Option2-1</Option>
                    <Option value="Option2-2">Option2-2</Option>
                  </Select>
                </InputGroup>

                <InputGroup compact style={{ marginBottom: '15px' }}>
                  <Select defaultValue="1">
                    <Option value="1">Between</Option>
                    <Option value="2">Except</Option>
                  </Select>
                  <Input
                    style={{ width: 100, textAlign: 'center' }}
                    placeholder="Minimum"
                  />
                  <Input
                    style={{ width: 24, borderLeft: 0, pointerEvents: 'none' }}
                    placeholder="~"
                  />
                  <Input
                    style={{ width: 100, textAlign: 'center' }}
                    placeholder="Maximum"
                  />
                </InputGroup>

                <InputGroup compact style={{ marginBottom: '15px' }}>
                  <Select defaultValue="Sign Up">
                    <Option value="Sign Up">Sign Up</Option>
                    <Option value="Sign In">Sign In</Option>
                  </Select>
                  <AutoComplete
                    dataSource={this.state.dataSource}
                    style={{ width: 200 }}
                    onChange={this.handleChange}
                    placeholder="Email"
                  />
                </InputGroup>
              </ContentHolder>
            </Box>
          </Col>
        </Row>

        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.input.autoSizingTitle" />}
              subtitle={<IntlMessages id="forms.input.autoSizingSubTitle" />}
            >
              <ContentHolder>
                <Input
                  type="textarea"
                  placeholder="Autosize height based on content lines"
                  autosize
                  style={{ marginBottom: '15px' }}
                />
                <Input
                  type="textarea"
                  placeholder="Autosize height with minimum and maximum number of lines"
                  autosize={{ minRows: 2, maxRows: 6 }}
                />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.input.prePostTabTitle" />}
              subtitle={<IntlMessages id="forms.input.prePostTabSubTitle" />}
            >
              <ContentHolder>
                <InputGroup>
                  <Input
                    addonBefore="Http://"
                    addonAfter=".com"
                    defaultValue="mysite"
                  />
                </InputGroup>

                <InputGroup>
                  <Input
                    addonBefore={selectBefore}
                    addonAfter={selectAfter}
                    defaultValue="mysite"
                  />
                </InputGroup>

                <InputGroup>
                  <Input
                    addonAfter={<Icon type="setting" />}
                    defaultValue="mysite"
                  />
                </InputGroup>
              </ContentHolder>
            </Box>
          </Col>
        </Row>

        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.input.textAreaTitle" />}
              subtitle={<IntlMessages id="forms.input.textAreaSubTitle" />}
            >
              <ContentHolder>
                <Textarea rows={6} />
              </ContentHolder>
            </Box>
          </Col>

          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.input.searchTitle" />}
              subtitle={<IntlMessages id="forms.input.searchSubTitle" />}
            >
              <ContentHolder>
                <InputSearch placeholder="input search text" />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
