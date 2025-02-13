import React, { Component } from 'react';

import { RadialChart } from 'react-vis';
import ChartWrapper from '../../chart.style';

export default class extends Component {
  render() {
    const { datas, width, height, colorRange, colorDomain } = this.props;
    return (
      <ChartWrapper className="isoChartWrapper">
        <RadialChart
          colorType={'literal'}
          colorDomain={colorDomain}
          colorRange={colorRange}
          margin={{ top: 100 }}
          data={datas}
          showLabels
          width={width}
          height={height}
        />
      </ChartWrapper>
    );
  }
}
