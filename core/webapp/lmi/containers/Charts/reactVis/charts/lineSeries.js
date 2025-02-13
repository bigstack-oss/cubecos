import React, { Component } from 'react';
import {
  XYPlot,
  XAxis,
  YAxis,
  HorizontalGridLines,
  VerticalGridLines,
  LineSeries
} from 'react-vis';
import ChartWrapper from '../../chart.style';

export default class extends Component {
  render() {
    const { datas, width, height } = this.props;
    return (
      <ChartWrapper className="isoChartWrapper">
        <XYPlot width={width} height={height}>
          <HorizontalGridLines />
          <VerticalGridLines />
          <XAxis title="X Axis" />
          <YAxis title="Y Axis" />
          {datas.map((data, key) => {
            const config = {
              key,
              className: data.className,
              data: data.data,
              curve: data.curve,
              strokeDasharray: data.strokeDasharray
            };
            return <LineSeries {...config} />;
          })}
        </XYPlot>
      </ChartWrapper>
    );
  }
}
