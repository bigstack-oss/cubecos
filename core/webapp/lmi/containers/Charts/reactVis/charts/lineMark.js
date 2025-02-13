import React, { Component } from 'react';

import {
  XYPlot,
  XAxis,
  YAxis,
  VerticalGridLines,
  HorizontalGridLines,
  LineMarkSeries
} from 'react-vis';
import ChartWrapper from '../../chart.style';

export default class extends Component {
  render() {
    const { datas, width, height } = this.props;
    return (
      <ChartWrapper className="isoChartWrapper">
        <XYPlot width={width} height={height}>
          <VerticalGridLines />
          <HorizontalGridLines />
          <XAxis />
          <YAxis />
          {datas.map((data, key) => {
            const config = {
              key,
              className: data.className,
              data: data.data,
              curve: data.curve
            };
            return <LineMarkSeries {...config} />;
          })}
        </XYPlot>
      </ChartWrapper>
    );
  }
}
