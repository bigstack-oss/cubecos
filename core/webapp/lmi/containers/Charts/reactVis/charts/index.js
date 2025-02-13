import React from 'react';
import Async from '../../../../helpers/asyncComponent';

const LineSeries = (props) => <Async load={import(/* webpackChunkName: "react-vis-lineSeries" */ './lineSeries')} componentProps={props} />;
const LineMark = (props) => <Async load={import(/* webpackChunkName: "react-vis-lineMark" */ './lineMark')} componentProps={props} />;
const AreaChartElevated = (props) => <Async load={import(/* webpackChunkName: "react-vis-stackedHorizontalBarChart" */ './areaChartElevated')} componentProps={props} />;
const StackedHorizontalBarChart = (props) => <Async load={import(/* webpackChunkName: "react-vis-stackedHorizontalBarChart" */ './stackedHorizontalBarChart')} componentProps={props} />;
const ClusteredStackedBarChart = (props) => <Async load={import(/* webpackChunkName: "react-vis-clusteredStackedBarChart" */ './clusteredStackedBarChart')} componentProps={props} />;
const CustomScales = (props) => <Async load={import(/* webpackChunkName: "react-vis-customScales" */ './customScales')} componentProps={props} />;
const CircularGridLines = (props) => <Async load={import(/* webpackChunkName: "react-vis-circularGridLines" */ './circularGridLines')} componentProps={props} />;
const DynamicProgrammaticRightedgehints = (props) => <Async load={import(/* webpackChunkName: "react-vis-dynamicProgrammaticRightedgehints" */ './dynamicProgrammaticRightedgehints')} componentProps={props} />;
const DynamicCrosshairScatterplot = (props) => <Async load={import(/* webpackChunkName: "react-vis-dynamicCrosshairScatterplot" */ './dynamicCrosshairScatterplot')} componentProps={props} />;
const SimpleRadialChart = (props) => <Async load={import(/* webpackChunkName: "react-vis-simpleRadialChart" */ './simpleRadialChart')} componentProps={props} />;
const SimpleDonutChart = (props) => <Async load={import(/* webpackChunkName: "react-vis-simpleDonutChart" */ './simpleDonutChart')} componentProps={props} />;
const CustomRadius = (props) => <Async load={import(/* webpackChunkName: "react-vis-customRadius" */ './customRadius')} componentProps={props} />;
const SimpleTreeMap = (props) => <Async load={import(/* webpackChunkName: "react-vis-simpleTreeMap" */ './simpleTreeMap')} componentProps={props} />;
const DynamicTreeMap = (props) => <Async load={import(/* webpackChunkName: "react-vis-dynamicTreeMap" */ './dynamicTreeMap')} componentProps={props} />;
const BasicSunburst = (props) => <Async load={import(/* webpackChunkName: "react-vis-basicSunburst" */ './basicSunburst')} componentProps={props} />;
const AnimatedSunburst = (props) => <Async load={import(/* webpackChunkName: "react-vis-animatedSunburst" */ './animatedSunburst')} componentProps={props} />;
const CandleStick = (props) => <Async load={import(/* webpackChunkName: "react-vis-candleStick" */ './candleStick')} componentProps={props} />;
const ComplexChart = (props) => <Async load={import(/* webpackChunkName: "react-vis-complexChart" */ './complexChart')} componentProps={props} />;
const StreamGraph = (props) => <Async load={import(/* webpackChunkName: "react-vis-streamGraph" */ './streamGraph')} componentProps={props} />;

export {
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
}