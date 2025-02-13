import React, { Component } from 'react';
import {
  XYPlot,
  XAxis,
  YAxis,
  VerticalGridLines,
  HorizontalGridLines,
  LineSeries,
  MarkSeries,
  Hint
} from 'react-vis';
import ChartWrapper from '../../chart.style';

const CHART_MARGINS = { left: 50, right: 10, top: 10, bottom: 25 };
function getAlignStyle(align, x, y) {
  return {
    right: 0,
    top: CHART_MARGINS.top + y
  };
}

export default class extends Component {
  constructor(props) {
    super(props);
    this.state = {
      value: null
    };
    this._rememberValue = this._rememberValue.bind(this);
  }

  _rememberValue(value) {
    this.setState({ value });
  }

  render() {
    const { value } = this.state;
    const { datas, width, height, xMax } = this.props;
    return (
      <ChartWrapper className="isoChartWrapper">
        <XYPlot width={width} height={height} margin={CHART_MARGINS}>
          <VerticalGridLines />
          <HorizontalGridLines />
          <XAxis />
          <YAxis />
          <MarkSeries onNearestX={this._rememberValue} data={datas} />
          {value ? (
            <LineSeries
              data={[{ x: value.x, y: value.y }, { x: xMax, y: value.y }]}
              stroke="black"
            />
          ) : null}
          {value ? (
            <Hint value={value} getAlignStyle={getAlignStyle}>
              <div className="rv-hint__content">
                {`(${value.x}, ${value.y})`}
              </div>
            </Hint>
          ) : null}
        </XYPlot>
      </ChartWrapper>
    );
  }
}
