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
          <YAxis stroke={colors[3]} />
          <CartesianGrid strokeDasharray="3 3" />
          <Tooltip />
          <Legend />
          <Bar dataKey="female" stackId="a" fill={colors[0]} />
          <Bar dataKey="male" stackId="a" fill={colors[1]} />
          <Bar dataKey="uv" fill={colors[2]} />
        </BarChart>
      </ChartWrapper>
    );
  }
}
