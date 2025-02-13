import React, { Component } from 'react';
import { Row, Col } from 'antd';
import {
  SimpleLineCharts,
  CustomizedDotLineChart,
  SimpleBarChart,
  MixBarChart,
  CustomShapeBarChart,
  BiaxialBarChart,
  SimpleAreaChart,
  StackedAreaChart,
  LineBarAreaComposedChart,
  CustomActiveShapePieChart,
  SpecifiedDomainRadarChart,
  SimpleRadialBarChart,
  LegendEffectOpacity,
} from './charts';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import basicStyle from '../../../config/basicStyle';
import * as configs from './config';

export default class ReCharts extends Component {
  render() {
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (
      <LayoutWrapper className="isoMapPage">
        <PageHeader>Re-Charts</PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.SimpleLineCharts.title}>
              <ContentHolder>
                <SimpleLineCharts {...configs.SimpleLineCharts} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.CustomizedDotLineChart.title}>
              <ContentHolder>
                <CustomizedDotLineChart {...configs.CustomizedDotLineChart} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.SimpleBarChart.title}>
              <ContentHolder>
                <SimpleBarChart {...configs.SimpleBarChart} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.MixBarChart.title}>
              <ContentHolder>
                <MixBarChart {...configs.MixBarChart} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.CustomShapeBarChart.title}>
              <ContentHolder>
                <CustomShapeBarChart {...configs.CustomShapeBarChart} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.BiaxialBarChart.title}>
              <ContentHolder>
                <BiaxialBarChart {...configs.BiaxialBarChart} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.SimpleAreaChart.title}>
              <ContentHolder>
                <SimpleAreaChart {...configs.SimpleAreaChart} />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.StackedAreaChart.title}>
              <ContentHolder>
                <StackedAreaChart {...configs.StackedAreaChart} />
              </ContentHolder>
            </Box>
          </Col>
        </Row>

        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.LineBarAreaComposedChart.title}>
              <ContentHolder>
                <LineBarAreaComposedChart
                  {...configs.LineBarAreaComposedChart}
                />
              </ContentHolder>
            </Box>
          </Col>

          <Col md={12} xs={24} style={colStyle}>
            <Box title={configs.CustomActiveShapePieChart.title}>
              <ContentHolder>
                <CustomActiveShapePieChart
                  {...configs.CustomActiveShapePieChart}
                />
              </ContentHolder>
            </Box>
          </Col>
        </Row>

        <Box title={configs.SpecifiedDomainRadarChart.title}>
          <ContentHolder>
            <SpecifiedDomainRadarChart {...configs.SpecifiedDomainRadarChart} />
          </ContentHolder>
        </Box>
        <Box title={configs.SimpleRadialBarChart.title}>
          <ContentHolder>
            <SimpleRadialBarChart {...configs.SimpleRadialBarChart} />
          </ContentHolder>
        </Box>
        <Box title={configs.LegendEffectOpacity.title}>
          <ContentHolder>
            <LegendEffectOpacity {...configs.LegendEffectOpacity} />
          </ContentHolder>
        </Box>
      </LayoutWrapper>
    );
  }
}
