import React, { Component } from 'react';
import { scaleLinear } from 'd3-scale';

import {
  Crosshair,
  HorizontalGridLines,
  MarkSeries,
  VerticalGridLines,
  XAxis,
  XYPlot,
  YAxis,
  Voronoi
} from 'react-vis';
import ChartWrapper from '../../chart.style';

export default class extends Component {
  state = {
    data: this.props.datas,
    selectedPointId: null,
    showVoronoi: false,
    x: scaleLinear()
      .domain(this.props.xDomain)
      .range(this.props.xRange),
    y: scaleLinear()
      .domain(this.props.yDomain)
      .range(this.props.yRange)
  };

  _onNearestXY = (value, { index }) => {
    this.setState({ selectedPointId: index });
  };

  _onMouseLeave = () => {
    this.setState({ selectedPointId: null });
  };

  render() {
    const { data, selectedPointId, showVoronoi, x, y } = this.state;
    const { width, height, extent, sizeRange } = this.props;
    return (
      <ChartWrapper className="isoChartWrapper">
        <div className="isoChartControl">
          <label style={{ display: 'block' }}>
            <input
              type="checkbox"
              checked={showVoronoi}
              onChange={e => this.setState({ showVoronoi: !showVoronoi })}
              style={{ marginRight: '5px' }}
            />
            Show Voronoi
          </label>
        </div>

        <XYPlot onMouseLeave={this._onMouseLeave} width={width} height={height}>
          <VerticalGridLines />
          <HorizontalGridLines />
          <XAxis />
          <YAxis />
          <MarkSeries
            className="mark-series-example"
            colorType="literal"
            data={data.map((point, index) => ({
              ...point,
              color: selectedPointId === index ? '#FF9833' : '#12939A'
            }))}
            onNearestXY={this._onNearestXY}
            sizeRange={sizeRange}
          />
          <Crosshair values={this.state.crosshairValues} />
          <Voronoi
            extent={extent}
            nodes={data}
            polygonStyle={{ stroke: showVoronoi ? 'rgba(0, 0, 0, .2)' : null }}
            x={d => x(d.x)}
            y={d => y(d.y)}
          />
        </XYPlot>
      </ChartWrapper>
    );
  }
}
