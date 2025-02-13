import React, { Component } from 'react';
import { Row, Col } from 'antd';
import Carousels from '../../../components/uielements/carousel';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import IntlMessages from '../../../components/utility/intlMessages';
import CarouselWrapper from './carousel.style';

const Carousel = props => (
  <CarouselWrapper>
    <Carousels {...props} />
  </CarouselWrapper>
);
export default class extends Component {
  onChange = (a, b, c) => {};
  render() {
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (
      <LayoutWrapper>
        <PageHeader>
          {<IntlMessages id="uiElements.carousel.carousel" />}
        </PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.carousel.basicCarousel" />}
              subtitle={
                <IntlMessages id="uiElements.carousel.basicCarouselSubTitle" />
              }
            >
              <ContentHolder>
                <Carousel afterChange={this.onChange}>
                  <div>
                    <h3>1</h3>
                  </div>
                  <div>
                    <h3>2</h3>
                  </div>
                  <div>
                    <h3>3</h3>
                  </div>
                  <div>
                    <h3>4</h3>
                  </div>
                </Carousel>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.carousel.verticalCarousel" />}
              subtitle={
                <IntlMessages id="uiElements.carousel.verticalCarouselSubTitle" />
              }
            >
              <ContentHolder>
                <Carousel afterChange={this.onChange} vertical>
                  <div>
                    <h3>1</h3>
                  </div>
                  <div>
                    <h3>2</h3>
                  </div>
                  <div>
                    <h3>3</h3>
                  </div>
                  <div>
                    <h3>4</h3>
                  </div>
                </Carousel>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={<IntlMessages id="uiElements.carousel.fadeInTransition" />}
              subtitle={
                <IntlMessages id="uiElements.carousel.fadeInTransitionSubTitle" />
              }
            >
              <ContentHolder>
                <Carousel effect="fade">
                  <div>
                    <h3>1</h3>
                  </div>
                  <div>
                    <h3>2</h3>
                  </div>
                  <div>
                    <h3>3</h3>
                  </div>
                  <div>
                    <h3>4</h3>
                  </div>
                </Carousel>
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} sm={12} xs={24} style={colStyle}>
            <Box
              title={
                <IntlMessages id="uiElements.carousel.scrollAutomatically" />
              }
              subtitle={
                <IntlMessages id="uiElements.carousel.scrollAutomaticallySubTitle" />
              }
            >
              <ContentHolder>
                <Carousel autoplay rtl>
                  <div>
                    <h3>1</h3>
                  </div>
                  <div>
                    <h3>2</h3>
                  </div>
                  <div>
                    <h3>3</h3>
                  </div>
                  <div>
                    <h3>4</h3>
                  </div>
                </Carousel>
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
