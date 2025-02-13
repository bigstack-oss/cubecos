import React, { Component } from 'react';
import { Col, Row } from 'antd';
import Select, { SelectOption } from '../../../components/uielements/select';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
const Option = SelectOption;

const children = [];
for (let i = 10; i < 36; i++) {
  children.push(<Option key={i.toString(36) + i}>{i.toString(36) + i}</Option>);
}
export default class extends Component {
  handleChange = value => {};

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
        <PageHeader>Select</PageHeader>

        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={24} sm={24} xs={24} style={colStyle}>
            <Box
              title="Multiple selection"
              subtitle="Multiple selection, selecting from existing items (scroll the menu)"
            >
              <ContentHolder>
                <Select
                  mode="multiple"
                  style={{ width: '100%' }}
                  placeholder="Please select"
                  defaultValue={['a10', 'c12']}
                  onChange={this.handleChange}
                >
                  {children}
                </Select>
              </ContentHolder>
            </Box>
          </Col>
        </Row>

        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title="Basic usage" subtitle="Basic usage">
              <ContentHolder>
                <Select
                  defaultValue="lucy"
                  onChange={this.handleChange}
                  style={{ width: '120px' }}
                >
                  <Option value="jack">Jack</Option>
                  <Option value="lucy">Lucy</Option>
                  <Option value="disabled" disabled>
                    Disabled
                  </Option>
                  <Option value="Yiminghe">yiminghe</Option>
                </Select>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box title="Disabled" subtitle="Select Disabled">
              <ContentHolder>
                <Select
                  defaultValue="lucy"
                  style={{ width: '120px' }}
                  allowClear
                  disabled
                >
                  <Option value="lucy">Lucy</Option>
                </Select>
              </ContentHolder>
            </Box>
          </Col>
        </Row>

        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={24} sm={24} xs={24} style={colStyle}>
            <Box
              title="Tags"
              subtitle="Select with tags, transform input to tag (scroll the menu)"
            >
              <ContentHolder>
                <Select
                  mode="tags"
                  style={{ width: '100%' }}
                  placeholder="Tags Mode"
                  onChange={this.handleChange}
                >
                  {children}
                </Select>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
