import React from 'react';
import Async from '../../../../helpers/asyncComponent';

const SimpleLineCharts = (props) => <Async load={import(/* webpackChunkName: "rechartx-simpleLineCharts" */ './simpleLineCharts')} componentProps={props} />;
const CustomizedDotLineChart = (props) => <Async load={import(/* webpackChunkName: "rechartx-customizedDotLineChart" */ './customizedDotLineChart')} componentProps={props} />;
const SimpleBarChart = (props) => <Async load={import(/* webpackChunkName: "rechartx-simpleBarChart" */ './simpleBarChart')} componentProps={props} />;
const MixBarChart = (props) => <Async load={import(/* webpackChunkName: "rechartx-mixBarChart" */ './mixBarChart')} componentProps={props} />;
const CustomShapeBarChart = (props) => <Async load={import(/* webpackChunkName: "rechartx-customShapeBarChart" */ './customShapeBarChart')} componentProps={props} />;
const BiaxialBarChart = (props) => <Async load={import(/* webpackChunkName: "rechartx-biaxialBarChart" */ './biaxialBarChart')} componentProps={props} />;
const SimpleAreaChart = (props) => <Async load={import(/* webpackChunkName: "rechartx-simpleAreaChart" */ './simpleAreaChart')} componentProps={props} />;
const StackedAreaChart = (props) => <Async load={import(/* webpackChunkName: "rechartx-stackedAreaChart" */ './stackedAreaChart')} componentProps={props} />;
const LineBarAreaComposedChart = (props) => <Async load={import(/* webpackChunkName: "rechartx-lineBarAreaComposedChart" */ './lineBarAreaComposedChart')} componentProps={props} />;
const CustomActiveShapePieChart = (props) => <Async load={import(/* webpackChunkName: "rechartx-customActiveShapePieChart" */ './customActiveShapePieChart')} componentProps={props} />;
const SpecifiedDomainRadarChart = (props) => <Async load={import(/* webpackChunkName: "rechartx-specifiedDomainRadarChart" */ './specifiedDomainRadarChart')} componentProps={props} />;
const SimpleRadialBarChart = (props) => <Async load={import(/* webpackChunkName: "rechartx-simpleRadialBarChart" */ './simpleRadialBarChart')} componentProps={props} />;
const LegendEffectOpacity = (props) => <Async load={import(/* webpackChunkName: "rechartx-legendEffectOpacity" */ './legendEffectOpacity')} componentProps={props} />;

export {
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
};