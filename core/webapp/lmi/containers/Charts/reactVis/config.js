import { curveCatmullRom } from 'd3-shape';
import TreeData from './largeData.json';

const width = 300;
const height = 300;

const buildCSData = total => {
  const result = Array(total)
    .fill(0)
    .map((x, i) => {
      const values = [
        Math.random(),
        Math.random(),
        Math.random(),
        Math.random(),
      ]
        .sort()
        .map(d => Math.floor(d * 100));
      const y = (values[2] + values[1]) / 2;
      return {
        x: i,
        y,
        yHigh: values[3],
        yOpen: values[2],
        yClose: values[1],
        yLow: values[0],
        color: y < 25 ? '#ff6384' : '#48A6F2',
        opacity: y > 75 ? 0.7 : 1,
      };
    });
  return result;
};
const LineSeries = {
  componentName: 'LineSeries',
  key: 'LineSeries',
  title: 'Line Series',
  width,
  height,
  datas: [
    {
      className: 'first-series',
      data: [{ x: 1, y: 3 }, { x: 2, y: 5 }, { x: 3, y: 15 }, { x: 4, y: 12 }],
    },
    {
      className: 'second-series',
      data: null,
    },
    {
      className: 'third-series',
      curve: 'curveMonotoneX',
      strokeDasharray: '7, 3',
      data: [{ x: 1, y: 10 }, { x: 2, y: 4 }, { x: 3, y: 2 }, { x: 4, y: 15 }],
    },
    {
      className: 'fourth-series',
      curve: curveCatmullRom.alpha(0.5),
      strokeDasharray: '7, 3',
      data: [{ x: 1, y: 7 }, { x: 2, y: 11 }, { x: 3, y: 9 }, { x: 4, y: 2 }],
    },
  ],
};
const LineMark = {
  componentName: 'LineMark',
  key: 'LineMark',
  title: 'Line Mark Series',
  width,
  height,
  datas: [
    {
      className: 'linemark-series-example',
      data: [{ x: 1, y: 10 }, { x: 2, y: 5 }, { x: 3, y: 15 }],
    },
    {
      className: 'linemark-series-example-2',
      curve: 'curveMonotoneX',
      data: [{ x: 1, y: 11 }, { x: 1.5, y: 29 }, { x: 3, y: 7 }],
    },
  ],
};
const AreaChartElevated = {
  componentName: 'AreaChartElevated',
  key: 'AreaChartElevated',
  title: 'Area Chart Elevated',
  width,
  height,
  datas: [
    {
      className: 'area-elevated-line-series',
      color: 'rgba(72,166,242,0.4)',
      data: [
        { x: 1, y: 10, y0: 1 },
        { x: 2, y: 25, y0: 5 },
        { x: 3, y: 15, y0: 3 },
      ],
    },
    {
      className: 'area-elevated-line-series-2',
      color: 'rgba(255,99,132,0.4)',
      data: [
        { x: 1, y: 5, y0: 6 },
        { x: 2, y: 20, y0: 11 },
        { x: 3, y: 10, y0: 9 },
      ],
    },
    {
      className: 'area-elevated-line-series-3',
      color: 'rgba(72,166,242,0.4)',
      data: [{ x: 1, y: 5.5 }, { x: 2, y: 15 }, { x: 3, y: 9 }],
    },
  ],
};
const StackedHorizontalBarChart = {
  componentName: 'StackedHorizontalBarChart',
  key: 'StackedHorizontalBarChart',
  title: 'Stacked Horizontal Bar Chart',
  width,
  height,
  datas: [
    {
      color: 'rgba(72,166,242,0.4)',
      data: [{ y: 2, x: 10 }, { y: 4, x: 5 }, { y: 5, x: 15 }],
    },
    {
      color: 'rgba(255,99,132,0.4)',
      data: [{ y: 2, x: 12 }, { y: 4, x: 2 }, { y: 5, x: 11 }],
    },
  ],
};
const ClusteredStackedBarChart = {
  componentName: 'ClusteredStackedBarChart',
  key: 'ClusteredStackedBarChart',
  title: 'Clustered Stacked Bar Chart',
  width,
  height: 300,
  orientationItems: [
    {
      title: 'Apples',
      color: 'rgba(255,99,132,0.4)',
    },
    {
      title: 'Oranges',
      color: 'rgba(72,166,242,0.4)',
    },
  ],
  datas: [
    {
      cluster: '2015',
      color: 'rgba(255,99,132,0.4)',
      data: [
        { x: 'Q1', y: 10 },
        { x: 'Q2', y: 5 },
        { x: 'Q3', y: 15 },
        { x: 'Q4', y: 20 },
      ],
    },
    {
      cluster: '2015',
      color: 'rgba(72,166,242,0.4)',
      data: [
        { x: 'Q1', y: 3 },
        { x: 'Q2', y: 7 },
        { x: 'Q3', y: 2 },
        { x: 'Q4', y: 1 },
      ],
    },
    {
      cluster: '2016',
      color: 'rgba(255,99,132,0.4)',
      data: [
        { x: 'Q1', y: 3 },
        { x: 'Q2', y: 8 },
        { x: 'Q3', y: 11 },
        { x: 'Q4', y: 19 },
      ],
    },
    {
      cluster: '2016',
      color: 'rgba(72,166,242,0.4)',
      data: [
        { x: 'Q1', y: 22 },
        { x: 'Q2', y: 2 },
        { x: 'Q3', y: 22 },
        { x: 'Q4', y: 18 },
      ],
    },
  ],
};
const CustomScales = {
  componentName: 'CustomScales',
  key: 'CustomScales',
  title: 'Custom Scales',
  width,
  height,
  datas: [
    {
      data: [{ x: 1, y: 3 }, { x: 2, y: 5 }, { x: 3, y: 15 }, { x: 4, y: 12 }],
    },
    {
      data: null,
    },
    {
      data: [{ x: 1, y: 10 }, { x: 2, y: 4 }, { x: 4, y: 2 }, { x: 5, y: 15 }],
    },
  ],
};
const CircularGridLines = {
  componentName: 'CircularGridLines',
  key: 'CircularGridLines',
  title: 'Circular Grid Lines',
  width,
  height,
  xDomain: [-3, 3],
  yDomain: [-3, 3],
  strokeWidth: 2,
  sizeRange: [5, 15],
  datas: [
    { r: 1, theta: Math.PI / 3, size: 30 },
    { r: 1.7, theta: 2 * Math.PI / 3, size: 10 },
    { r: 2, theta: Math.PI, size: 1 },
    { r: 3, theta: 3 * Math.PI / 2, size: 12 },
    { r: 2.5, theta: Math.PI / 4, size: 4 },
    { r: 0, theta: Math.PI / 4, size: 1 },
  ],
};
const DynamicProgrammaticRightedgehints = {
  componentName: 'DynamicProgrammaticRightedgehints',
  key: 'DynamicProgrammaticRightedgehints',
  title: 'Dynamic Programmatic Right Edge Hints',
  width,
  height,
  xMax: 4,
  datas: [{ x: 1, y: 5 }, { x: 2, y: 12 }, { x: 3, y: 8 }, { x: 4, y: 15 }],
};
const DynamicCrosshairScatterplot = {
  componentName: 'DynamicCrosshairScatterplot',
  key: 'DynamicCrosshairScatterplot',
  title: 'Dynamic Crosshair Scatterplot',
  width,
  height,
  xDomain: [1, 3],
  yDomain: [4, 14],
  xRange: [40, 290],
  yRange: [260, 10],
  extent: [[40, 10], [290, 260]],
  sizeRange: [5, 13],
  datas: [
    { x: 1, y: 4, size: 9 },
    { x: 1, y: 5, size: 18 },
    { x: 1, y: 10, size: 5 },
    { x: 1, y: 11, size: 29 },
    { x: 1, y: 13.9, size: 5 },
    { x: 1, y: 14, size: 8 },
    { x: 1.5, y: 11.8, size: 25 },
    { x: 1.7, y: 9, size: 30 },
    { x: 2, y: 5, size: 11 },
    { x: 2.1, y: 11.8, size: 28 },
    { x: 2.4, y: 7.9, size: 14 },
    { x: 2.4, y: 13.5, size: 20 },
    { x: 2.7, y: 13.7, size: 14 },
    { x: 2.9, y: 7.7, size: 26 },
    { x: 3, y: 5.4, size: 6 },
  ],
};
const SimpleRadialChart = {
  componentName: 'SimpleRadialChart',
  key: 'SimpleRadialChart',
  title: 'simple Radial Chart',
  width,
  height,
  colorRange: [0, 10],
  colorDomain: [0, 100],
  datas: [
    { angle: 1, color: '#89DAC1', label: 'green', opacity: 0.2 },
    { angle: 2, color: '#F6D18A', label: 'yellow' },
    { angle: 5, color: '#1E96BE', label: 'cyan' },
    { angle: 3, color: '#DA70BF', label: 'magenta' },
    { angle: 5, color: '#F6D18A', label: 'yellow again' },
  ],
};
const SimpleDonutChart = {
  componentName: 'SimpleDonutChart',
  key: 'SimpleDonutChart',
  title: 'Simple Donut Chart',
  width,
  height,
  innerRadius: 100,
  radius: 140,
  datas: [{ angle: 2 }, { angle: 6 }, { angle: 2 }, { angle: 3 }, { angle: 1 }],
};
const CustomRadius = {
  componentName: 'CustomRadius',
  key: 'CustomRadius',
  title: 'Custom Radius',
  width,
  height,
  radiusDomain: [0, 20],
  tickTotal: 20,
  rRange: [0, 150],
  datas: [
    { angle: 1, id: 1, radius: 10 },
    {
      angle: 2,
      label: 'Super Custom label',
      subLabel: 'With annotation',
      id: 2,
      radius: 20,
    },
    { angle: 5, id: 3, radius: 5, label: 'Alt Label' },
    { angle: 3, id: 4, radius: 14 },
    { angle: 5, id: 5, adius: 12, subLabel: 'Sub Label only' },
  ],
};
const SimpleTreeMap = {
  componentName: 'SimpleTreeMap',
  key: 'SimpleTreeMap',
  title: 'Simple Tree Map',
  width,
  height,
  datas: TreeData,
};
const DynamicTreeMap = {
  componentName: 'DynamicTreeMap',
  key: 'DynamicTreeMap',
  title: 'Dynamic Tree Map',
  width,
  height,
};
const BasicSunburst = {
  componentName: 'BasicSunburst',
  key: 'BasicSunburst',
  title: 'Basic Sunburst',
  width,
  height,
  datas: TreeData,
};
const AnimatedSunburst = {
  componentName: 'AnimatedSunburst',
  key: 'AnimatedSunburst',
  title: 'Animated Sunburst',
  width,
  height,
};
const CandleStick = {
  componentName: 'CandleStick',
  key: 'CandleStick',
  title: 'Candle Stick',
  height,
  datas: buildCSData(30),
};
const ComplexChart = {
  componentName: 'ComplexChart',
  key: 'ComplexChart',
  title: 'Complex Chart',
};
const StreamGraph = {
  componentName: 'StreamGraph',
  key: 'StreamGraph',
  title: 'Stream Graph',
};

export {
  LineSeries,
  LineMark,
  StackedHorizontalBarChart,
  AreaChartElevated,
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
};
