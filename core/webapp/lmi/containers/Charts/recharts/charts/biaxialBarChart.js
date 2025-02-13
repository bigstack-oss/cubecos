import React, { Component } from 'react';
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
} from 'recharts';
import ChartWrapper from '../../chart.style';

export default class extends Component {
  render() {
    const { datas, width, height, colors } = this.props;
    return (
      <ChartWrapper className="isoChartWrapper">
        <BarChart
          width={width}
          height={height}
          data={datas}
          margin={{ top: 5, right: 30, left: 20, bottom: 5 }}
        >
          <XAxis dataKey="name" stroke={colors[3]} />
          <YAxis yAxisId="left" orientation="left" stroke={colors[3]} />
          <YAxis yAxisId="right" orientation="right" stroke={colors[3]} />
          <CartesianGrid strokeDasharray="3 3" />
          <Tooltip />
          <Legend />
          <Bar yAxisId="left" dataKey="pv" fill={colors[0]} />
          <Bar yAxisId="right" dataKey="uv" fill={colors[1]} />
        </BarChart>
      </ChartWrapper>
    );
  }
}
