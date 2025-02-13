import React, { Component } from 'react';
import { RadialBarChart, RadialBar, Legend } from 'recharts';
import ChartWrapper from '../../chart.style';

const style = {
  top: 0,
  left: 350,
  lineHeight: '24px',
};
export default class extends Component {
  render() {
    const { datas, width, height } = this.props;
    return (
      <ChartWrapper className="isoChartWrapper">
        <RadialBarChart
          width={width}
          height={height}
          cx={150}
          cy={150}
          innerRadius={20}
          outerRadius={140}
          barSize={10}
          data={datas}
        >
          <RadialBar
            minAngle={15}
            label
            background
            clockWise={true}
            dataKey="uv"
          />
          <Legend
            iconSize={10}
            width={120}
            height={140}
            layout="vertical"
            verticalAlign="middle"
            wrapperStyle={style}
          />
        </RadialBarChart>
      </ChartWrapper>
    );
  }
}
