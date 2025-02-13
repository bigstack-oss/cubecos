import React, { Component } from 'react';
import {
  XYPlot,
  XAxis,
  YAxis,
  VerticalGridLines,
  HorizontalGridLines,
  HorizontalBarSeries
} from 'react-vis';
import ChartWrapper from '../../chart.style';

export default class extends Component {
  render() {
    const { datas, width, height } = this.props;
    return (
      <ChartWrapper className="isoChartWrapper">
        <XYPlot width={width} height={height} stackBy="x">
          <VerticalGridLines />
          <HorizontalGridLines />
          <XAxis />
          <YAxis />
          {datas.map((data, key) => {
            const config = {
              key,
              data: data.data
            };
            return <HorizontalBarSeries {...config} />;
          })}
        </XYPlot>
      </ChartWrapper>
    );
  }
}
