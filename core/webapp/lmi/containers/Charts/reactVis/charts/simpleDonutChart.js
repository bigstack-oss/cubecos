import React, { Component } from 'react';

import { RadialChart, Hint } from 'react-vis';
import ChartWrapper from '../../chart.style';

export default class extends Component {
  state = { value: false };
  render() {
    const { value } = this.state;
    const { datas, width, height, innerRadius, radius } = this.props;
    return (
      <ChartWrapper className="isoChartWrapper">
        <RadialChart
          className={'donut-chart-example'}
          innerRadius={innerRadius}
          radius={radius}
          data={datas}
          onValueMouseOver={v => this.setState({ value: v })}
          onSeriesMouseOut={v => this.setState({ value: false })}
          width={width}
          height={height}
        >
          {value && <Hint value={value} />}
        </RadialChart>
      </ChartWrapper>
    );
  }
}
