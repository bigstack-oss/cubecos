import React, { Component } from 'react';
import { Row, Col } from 'antd';
import Radio, { RadioGroup } from '../../../components/uielements/radio';
import Input from '../../../components/uielements/input';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import IntlMessages from '../../../components/utility/intlMessages';
import { rtl } from '../../../config/withDirection';

const plainOptions = ['Apple', 'Pear', 'Orange'];
const options = [
  { label: 'Apple', value: 'Apple' },
  { label: 'Pear', value: 'Pear' },
  { label: 'Orange', value: 'Orange' }
];
const optionsWithDisabled = [
  { label: 'Apple', value: 'Apple' },
  { label: 'Pear', value: 'Pear' },
  { label: 'Orange', value: 'Orange', disabled: false }
];

export default class extends Component {
  state = {
    value: 1,
    value1: 'Apple',
    value2: 'Apple',
    value3: 'Apple',
    value4: 11
  };
  onChange = e => {
    this.setState({
      value: e.target.value
    });
  };
  onChange1 = e => {
    this.setState({
      value1: e.target.value
    });
  };
  onChange2 = e => {
    this.setState({
      value2: e.target.value
    });
  };
  onChange3 = e => {
    this.setState({
      value3: e.target.value
    });
  };
  onChange4 = e => {
    this.setState({
      value4: e.target.value
    });
  };
  render() {
    const radioStyle = {
      display: 'block',
      height: '30px',
      lineHeight: '30px'
    };
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (
      <LayoutWrapper>
        <PageHeader>{<IntlMessages id="forms.radio.header" />}</PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.radio.simpleTitle" />}
              subtitle={<IntlMessages id="forms.radio.simpleSubTitle" />}
            >
              <ContentHolder>
                <Radio>Radio</Radio>
                <br />
                <Radio defaultChecked={false} disabled>
                  Disabled
                </Radio>
                <br />
                <Radio defaultChecked disabled>
                  Disabled
                </Radio>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.radio.groupTitle" />}
              subtitle={<IntlMessages id="forms.radio.groupSubTitle" />}
            >
              <ContentHolder>
                <RadioGroup onChange={this.onChange} value={this.state.value}>
                  <Radio style={radioStyle} value={1}>
                    Option A
                  </Radio>
                  <Radio style={radioStyle} value={2}>
                    Option B
                  </Radio>
                  <Radio style={radioStyle} value={3}>
                    Option C
                  </Radio>
                  <Radio style={radioStyle} value={4}>
                    More...
                    {this.state.value === 4 ? (
                      <Input
                        style={{
                          width: 100,
                          marginLeft: rtl === 'rtl' ? 0 : 10,
                          marginRight: rtl === 'rtl' ? 10 : 0
                        }}
                      />
                    ) : null}
                  </Radio>
                </RadioGroup>
              </ContentHolder>
            </Box>
          </Col>
        </Row>

        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.radio.groupSecondTitle" />}
              subtitle={<IntlMessages id="forms.radio.groupSecondSubTitle" />}
            >
              <ContentHolder>
                <RadioGroup onChange={this.onChange4} value={this.state.value4}>
                  <Radio value={11}>A</Radio>
                  <Radio value={22}>B</Radio>
                  <Radio value={32}>C</Radio>
                  <Radio value={43}>D</Radio>
                </RadioGroup>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.radio.groupThirdTitle" />}
              subtitle={<IntlMessages id="forms.radio.groupThirdSubTitle" />}
            >
              <ContentHolder>
                <RadioGroup
                  options={plainOptions}
                  onChange={this.onChange1}
                  value={this.state.value1}
                  style={{ marginBottom: '10px' }}
                />
                <RadioGroup
                  options={options}
                  onChange={this.onChange2}
                  value={this.state.value2}
                  style={{ marginBottom: '10px' }}
                />
                <RadioGroup
                  options={optionsWithDisabled}
                  onChange={this.onChange3}
                  value={this.state.value3}
                />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
