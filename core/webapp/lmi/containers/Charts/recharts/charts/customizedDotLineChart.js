import React, { Component } from 'react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
} from 'recharts';
import ChartWrapper from '../../chart.style';

const CustomizedDot = props => {
  const { cx, cy, payload } = props;
  return (
    <svg
      x={cx - 10}
      y={cy - 10}
      width={20}
      height={20}
      fill={payload.fillColor}
      viewBox="0 0 1024 1024"
    >
      <path d={payload.svg} />
    </svg>
  );
};
export default class extends Component {
  render() {
    const { datas, width, height, colors } = this.props;
    return (
      <ChartWrapper className="isoChartWrapper">
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
            dot={<CustomizedDot />}
          />
          <Line type="monotone" dataKey="uv" stroke={colors[1]} />
        </LineChart>
      </ChartWrapper>
    );
  }
}
