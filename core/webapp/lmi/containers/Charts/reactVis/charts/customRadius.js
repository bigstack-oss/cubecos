import React, { Component } from 'react';

import { CircularGridLines, RadialChart } from 'react-vis';
import ChartWrapper from '../../chart.style';

function mapData(hoveredSection, datas) {
  return datas.map((row, index) => {
    return {
      ...row,
      innerRadius: hoveredSection === index + 1 ? row.radius - 1 : null,
      opacity: !hoveredSection || hoveredSection === index + 1 ? 1 : 0.6
    };
  });
}

export default class extends Component {
  state = {
    hoveredSection: false
  };

  render() {
    const { hoveredSection } = this.state;
    const {
      datas,
      width,
      height,
      radiusDomain,
      tickTotal,
      rRange
    } = this.props;
    return (
      <ChartWrapper className="isoChartWrapper">
        <RadialChart
          animation
          showLabels
          radiusDomain={radiusDomain}
          data={mapData(hoveredSection, datas)}
          labelsAboveChildren
          onValueMouseOver={row => this.setState({ hoveredSection: row.id })}
          onMouseLeave={() => this.setState({ hoveredSection: false })}
          width={width}
          height={height}
        >
          <CircularGridLines tickTotal={tickTotal} rRange={rRange} />
        </RadialChart>
      </ChartWrapper>
    );
  }
}
