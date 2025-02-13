import React, { Component } from 'react';
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
} from 'recharts';
import ChartWrapper from '../../chart.style';

export default class extends Component {
  render() {
    const { datas, width, height, colors } = this.props;
    return (
      <ChartWrapper className="isoChartWrapper">
        <AreaChart
          width={width}
          height={height}
          data={datas}
          margin={{ top: 10, right: 30, left: 0, bottom: 0 }}
        >
          <XAxis dataKey="name" stroke={colors[3]} />
          <YAxis stroke={colors[3]} />
          <CartesianGrid strokeDasharray="3 3" />
          <Tooltip />
          <Area
            type="monotone"
            dataKey="uv"
            stroke={colors[0]}
            fill={colors[0]}
          />
        </AreaChart>
      </ChartWrapper>
    );
  }
}
