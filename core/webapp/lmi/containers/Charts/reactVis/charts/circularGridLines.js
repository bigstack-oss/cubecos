import React, { Component } from 'react';
import { XYPlot, XAxis, YAxis, MarkSeries, CircularGridLines } from 'react-vis';
import ChartWrapper from '../../chart.style';

const margin = {
  top: 10,
  bottom: 10,
  left: 10,
  right: 10
};
export default class extends Component {
  render() {
    const {
      datas,
      width,
      height,
      xDomain,
      yDomain,
      strokeWidth,
      sizeRange
    } = this.props;
    return (
      <ChartWrapper className="isoChartWrapper">
        <XYPlot
          margin={margin}
          xDomain={xDomain}
          yDomain={yDomain}
          width={width}
          height={height}
        >
          <CircularGridLines />
          <XAxis top={(width - margin.top) / 2} />
          <YAxis left={(height - margin.left - margin.right) / 2} />
          <MarkSeries
            strokeWidth={strokeWidth}
            sizeRange={sizeRange}
            data={datas.map(row => ({
              ...row,
              x: Math.cos(row.theta) * row.r,
              y: Math.sin(row.theta) * row.r
            }))}
          />
        </XYPlot>
      </ChartWrapper>
    );
  }
}
