import React, { Component } from 'react';
import { Row, Col } from 'antd';
import {
  LineSeries,
  LineMark,
  AreaChartElevated,
  StackedHorizontalBarChart,
  ClusteredStackedBarChart,
  CustomScales,
  CircularGridLines,
  DynamicProgrammaticRightedgehints,
  DynamicCrosshairScatterplot,
  SimpleRadialChart,
  SimpleDonutChart,
  CustomRadius,
  SimpleTreeMap,
  DynamicTreeMap,
  BasicSunburst,
  AnimatedSunburst,
  CandleStick,
  ComplexChart,
  StreamGraph,
} from './charts';
import * as configs from './config';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import ReactVisCss from 'react-vis/dist/style.css';

export default class ReactVis extends Component {
  render() {
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (<div>
      <style>{ReactVisCss}</style>
      <LayoutWrapper className="isoMapPage">
        <PageHeader>React Vis</PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.LineSeries.title}>
              <ContentHolder>
                <LineSeries {...configs.LineSeries} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.LineMark.title}>
              <ContentHolder>
                <LineMark {...configs.LineMark} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.AreaChartElevated.title}>
              <ContentHolder>
                <AreaChartElevated {...configs.AreaChartElevated} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.StackedHorizontalBarChart.title}>
              <ContentHolder>
                <StackedHorizontalBarChart
                  {...configs.StackedHorizontalBarChart}
                />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.ClusteredStackedBarChart.title}>
              <ContentHolder>
                <ClusteredStackedBarChart
                  {...configs.ClusteredStackedBarChart}
                />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.CustomScales.title}>
              <ContentHolder>
                <CustomScales {...configs.CustomScales} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.CircularGridLines.title}>
              <ContentHolder>
                <CircularGridLines {...configs.CircularGridLines} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.DynamicProgrammaticRightedgehints.title}>
              <ContentHolder>
                <DynamicProgrammaticRightedgehints
                  {...configs.DynamicProgrammaticRightedgehints}
                />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.DynamicCrosshairScatterplot.title}>
              <ContentHolder>
                <DynamicCrosshairScatterplot
                  {...configs.DynamicCrosshairScatterplot}
                />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.SimpleRadialChart.title}>
              <ContentHolder>
                <SimpleRadialChart {...configs.SimpleRadialChart} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.SimpleDonutChart.title}>
              <ContentHolder>
                <SimpleDonutChart {...configs.SimpleDonutChart} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.CustomRadius.title}>
              <ContentHolder>
                <CustomRadius {...configs.CustomRadius} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.SimpleTreeMap.title}>
              <ContentHolder>
                <SimpleTreeMap {...configs.SimpleTreeMap} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.DynamicTreeMap.title}>
              <ContentHolder>
                <DynamicTreeMap {...configs.DynamicTreeMap} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.BasicSunburst.title}>
              <ContentHolder>
                <BasicSunburst {...configs.BasicSunburst} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.AnimatedSunburst.title}>
              <ContentHolder>
                <AnimatedSunburst {...configs.AnimatedSunburst} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.CandleStick.title}>
              <ContentHolder>
                <CandleStick {...configs.CandleStick} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.ComplexChart.title}>
              <ContentHolder>
                <ComplexChart {...configs.ComplexChart} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col span={24} style={colStyle}>
            <Box title={configs.StreamGraph.title}>
              <ContentHolder>
                <StreamGraph {...configs.StreamGraph} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    </div>);
  }
}
