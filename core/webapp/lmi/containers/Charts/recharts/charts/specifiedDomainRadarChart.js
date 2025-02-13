import React, { Component } from 'react';
import {
  Radar,
  RadarChart,
  PolarGrid,
  Legend,
  PolarAngleAxis,
  PolarRadiusAxis,
} from 'recharts';
import ChartWrapper from '../../chart.style';

export default class extends Component {
  render() {
    const {
      datas,
      width,
      height,
      colors,
      angle,
      domain,
      cx,
      cy,
      outerRadius,
    } = this.props;
    return (
      <ChartWrapper className="isoChartWrapper">
        <RadarChart
          cx={cx}
          cy={cy}
          outerRadius={outerRadius}
          width={width}
          height={height}
          data={datas}
        >
          <Radar
            name="Mike"
            dataKey="A"
            stroke={colors[0]}
            fill={colors[0]}
            fillOpacity={0.6}
          />
          <Radar
            name="Lily"
            dataKey="B"
            stroke={colors[1]}
            fill={colors[1]}
            fillOpacity={0.6}
          />
          <PolarGrid />
          <Legend />
          <PolarAngleAxis dataKey="subject" />
          <PolarRadiusAxis angle={angle} domain={domain} />
        </RadarChart>
      </ChartWrapper>
    );
  }
}
