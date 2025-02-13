import React, { Component } from 'react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid } from 'recharts';
import ChartWrapper from '../../chart.style';

const getPath = (x, y, width, height) => {
  return `M${x},${y + height}
    C${x + width / 3},${y + height} ${x + width / 2},${y + height / 3} ${x +
    width / 2}, ${y}
    C${x + width / 2},${y + height / 3} ${x + 2 * width / 3},${y + height} ${x +
    width}, ${y + height}
    Z`;
};
const TriangleBar = props => {
  const { fill, x, y, width, height } = props;
  return <path d={getPath(x, y, width, height)} stroke="none" fill={fill} />;
};

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
          <XAxis dataKey="name" fill={colors[3]} />
          <YAxis stroke={colors[3]} />
          <CartesianGrid strokeDasharray="3 3" />
          <Bar
            dataKey="female"
            fill={colors[0]}
            shape={<TriangleBar />}
            label
          />
        </BarChart>
      </ChartWrapper>
    );
  }
}
