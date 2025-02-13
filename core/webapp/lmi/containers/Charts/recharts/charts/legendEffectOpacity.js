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

export default class extends Component {
  constructor(props) {
    super(props);
    this.state = {
      opacity: {
        uv: 1,
        pv: 1,
      },
    };
  }
  handleMouseEnter(o) {
    const { dataKey } = o;
    const { opacity } = this.state;

    this.setState({
      opacity: { ...opacity, [dataKey]: 0.5 },
    });
  }
  handleMouseLeave(o) {
    const { dataKey } = o;
    const { opacity } = this.state;

    this.setState({
      opacity: { ...opacity, [dataKey]: 1 },
    });
  }
  render() {
    const { opacity } = this.state;
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
          <Legend
            onMouseEnter={this.handleMouseEnter}
            onMouseLeave={this.handleMouseLeave}
          />
          <Line
            type="monotone"
            dataKey="pv"
            strokeOpacity={opacity.pv}
            stroke={colors[0]}
            activeDot={{ r: 8 }}
          />
          <Line
            type="monotone"
            dataKey="uv"
            strokeOpacity={opacity.uv}
            stroke={colors[1]}
          />
        </LineChart>
        <p className="notes">Tips: Hover the legend !</p>
      </ChartWrapper>
    );
  }
}
