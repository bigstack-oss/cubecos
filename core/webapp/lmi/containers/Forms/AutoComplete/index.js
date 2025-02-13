import React, { Component } from 'react';
import { Row, Col } from 'antd';
import AutoComplete, {
  AutoCompleteOption
} from '../../../components/uielements/autocomplete';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import IntlMessages from '../../../components/utility/intlMessages';

const Option = AutoCompleteOption;

export default class extends Component {
  state = {
    result: [],
    dataSource: []
  };

  handleCustomizedChange = value => {
    let result;
    if (!value || value.indexOf('@') >= 0) {
      result = [];
    } else {
      result = ['gmail.com', '163.com', 'qq.com'].map(
        domain => `${value}@${domain}`
      );
    }
    this.setState({ result });
  };

  handleChange = value => {
    this.setState({
      dataSource: !value ? [] : [value, value + value, value + value + value]
    });
  };

  render() {
    const { dataSource, result } = this.state;
    const children = result.map(email => {
      return <Option key={email}>{email}</Option>;
    });
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (
      <LayoutWrapper>
        <PageHeader>
          {<IntlMessages id="forms.autocomplete.header" />}
        </PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.autocomplete.simpleTitle" />}
              subtitle={<IntlMessages id="forms.autocomplete.simpleSubTitle" />}
            >
              <ContentHolder>
                <AutoComplete
                  onChange={this.handleCustomizedChange}
                  placeholder="input here"
                >
                  {children}
                </AutoComplete>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="forms.autocomplete.customizeTitle" />}
              subtitle={
                <IntlMessages id="forms.autocomplete.customizeSubTitle" />
              }
            >
              <ContentHolder>
                <AutoComplete
                  dataSource={dataSource}
                  style={{ height: 200 }}
                  onChange={this.handleChange}
                  placeholder="input here"
                >
                  <textarea style={{ height: 200 }} />
                </AutoComplete>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
