import React, { Component } from 'react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend
} from 'recharts';
import ChartWrapper from '../../chart.style';

export default class extends Component {
  render() {
    const { datas, width, height, colors } = this.props;
    return (
      <ChartWrapper>
        <LineChart
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
          <Line
            type="monotone"
            dataKey="pv"
            stroke={colors[0]}
            activeDot={{ r: 8 }}
          />
          <Line type="monotone" dataKey="uv" stroke={colors[1]} />
        </LineChart>
      </ChartWrapper>
    );
  }
}
