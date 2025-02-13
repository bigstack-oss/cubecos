import React, { Component } from 'react';
import Async from '../../../helpers/asyncComponent';
import { Row, Col } from 'antd';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import * as configs from './config';
import ChartWrapper from '../chart.style';

const GoogleChart = props => (
  <ChartWrapper>
    <Async
      load={import(/* webpackChunkName: "googleChart" */ 'react-google-charts')}
      componentProps={props}
      componentArguement={'googleChart'}
    />
  </ChartWrapper>
);

export default class extends Component {
  render() {
    const chartEvents = [
      {
        eventName: 'select',
        callback(Chart) {}
      }
    ];
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (
      <LayoutWrapper className="isoMapPage">
        <PageHeader>Google Charts</PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.BarChart.title}>
              <ContentHolder>
                <GoogleChart {...configs.BarChart} chartEvents={chartEvents} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.lineChart.title}>
              <ContentHolder>
                <GoogleChart {...configs.lineChart} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.BubbleChart.title}>
              <ContentHolder>
                <GoogleChart {...configs.BubbleChart} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.Histogram.title}>
              <ContentHolder>
                <GoogleChart {...configs.Histogram} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.ScatterChart.title}>
              <ContentHolder>
                <GoogleChart {...configs.ScatterChart} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.AreaChart.title}>
              <ContentHolder>
                <GoogleChart {...configs.AreaChart} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.CandlestickChart.title}>
              <ContentHolder>
                <GoogleChart {...configs.CandlestickChart} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.ComboChart.title}>
              <ContentHolder>
                <GoogleChart {...configs.ComboChart} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.DonutChart.title}>
              <ContentHolder>
                <GoogleChart {...configs.DonutChart} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.SteppedAreaChart.title}>
              <ContentHolder>
                <GoogleChart {...configs.SteppedAreaChart} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.Timeline.title}>
              <ContentHolder>
                <GoogleChart {...configs.Timeline} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.TreeMap.title}>
              <ContentHolder>
                <GoogleChart {...configs.TreeMap} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.TrendLines.title}>
              <ContentHolder>
                <GoogleChart {...configs.TrendLines} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.Waterfall.title}>
              <ContentHolder>
                <GoogleChart {...configs.Waterfall} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.Gantt.title}>
              <ContentHolder>
                <GoogleChart {...configs.Gantt} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.WordTree.title}>
              <ContentHolder>
                <GoogleChart {...configs.WordTree} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}
export { GoogleChart };
