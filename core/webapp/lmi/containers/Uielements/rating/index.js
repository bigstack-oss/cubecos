import React, { Component } from 'react';
import { Row, Col, Icon } from 'antd';
import Rate from '../../../components/uielements/rate';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import IntlMessages from '../../../components/utility/intlMessages';
// import RatingWrapper from './rating.style';

// const Rate = props => (
//   <RatingWrapper>
//     <Rates {...props} />
//   </RatingWrapper>
// );
export default class extends Component {
  state = {
    value: 3,
    count: null,
  };
  handleChange = value => {
    this.setState({ value });
  };
  render() {
    const { value } = this.state;
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (
      <LayoutWrapper>
        <PageHeader>
          {<IntlMessages id="uiElements.rating.rating" />}
        </PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.rating.basicExample" />}
              subtitle={
                <IntlMessages id="uiElements.rating.basicExampleSubTitle" />
              }
            >
              <ContentHolder>
                <Rate />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.rating.halfStar" />}
              subtitle={
                <IntlMessages id="uiElements.rating.halfStarSubTitle" />
              }
            >
              <ContentHolder>
                <Rate allowHalf defaultValue={2.5} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.rating.showCopywriting" />}
              subtitle={
                <IntlMessages id="uiElements.rating.showCopywritingSubTitle" />
              }
            >
              <ContentHolder>
                <span>
                  <Rate onChange={this.handleChange} value={value} />
                  {value && (
                    <span className="ant-rate-text">{value} stars</span>
                  )}
                </span>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.rating.readOnly" />}
              subtitle={
                <IntlMessages id="uiElements.rating.readOnlySubTitle" />
              }
            >
              <ContentHolder>
                <Rate disabled defaultValue={2} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.rating.otherCharacter" />}
              subtitle={
                <IntlMessages id="uiElements.rating.otherCharacterSubTitle" />
              }
            >
              <ContentHolder>
                <Rate character={<Icon type="heart" />} allowHalf />
                <br />
                <Rate character="A" allowHalf style={{ fontSize: 36 }} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
