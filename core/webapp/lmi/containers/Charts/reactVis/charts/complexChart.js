import React, { Component } from 'react';
import {
  XYPlot,
  XAxis,
  YAxis,
  HorizontalGridLines,
  makeWidthFlexible,
  LineSeries,
  VerticalBarSeries,
  DiscreteColorLegend,
  Crosshair
} from 'react-vis';
import Button from '../../../../components/uielements/button';

const FlexibleXYPlot = makeWidthFlexible(XYPlot);

const totalValues = Math.random() * 50;

function getRandomSeriesData(total) {
  const result = [];
  let lastY = Math.random() * 40 - 20;
  let y;
  const firstY = lastY;
  for (let i = 0; i < total; i++) {
    y = Math.random() * firstY - firstY / 2 + lastY;
    result.push({
      x: i,
      y
    });
    lastY = y;
  }
  return result;
}

export default class extends Component {
  state = {
    crosshairValues: [],
    series: [
      {
        title: 'Apples',
        disabled: false,
        data: getRandomSeriesData(totalValues)
      },
      {
        title: 'Bananas',
        disabled: false,
        data: getRandomSeriesData(totalValues)
      }
    ]
  };

  _updateButtonClicked = () => {
    const { series } = this.state;
    series.forEach(s => {
      s.data = getRandomSeriesData(Math.random() * 50 + 5);
    });
    this.setState({ series });
  };

  _nearestXHandler = (value, { index }) => {
    const { series } = this.state;
    this.setState({
      crosshairValues: series.map(s => s.data[index])
    });
  };

  _mouseLeaveHandler = () => {
    this.setState({ crosshairValues: [] });
  };
  _formatCrosshairTitle = values => {
    return {
      title: 'X',
      value: values[0].x
    };
  };
  _formatCrosshairItems = values => {
    const { series } = this.state;
    return values.map((v, i) => {
      return {
        title: series[i].title,
        value: v.y
      };
    });
  };

  _legendClickHandler = (item, i) => {
    const { series } = this.state;
    series[i].disabled = !series[i].disabled;
    this.setState({ series });
  };

  render() {
    const { forFrontPage } = this.props;
    const { series, crosshairValues } = this.state;
    return (
      <div className={!forFrontPage ? 'example-with-click-me' : ''}>
        {!forFrontPage && (
          <div className="legend">
            <DiscreteColorLegend
              onItemClick={this._legendClickHandler}
              width={180}
              items={series}
            />
          </div>
        )}

        <div className="chart">
          <FlexibleXYPlot
            animation
            onMouseLeave={this._mouseLeaveHandler}
            height={300}
          >
            <HorizontalGridLines />
            <YAxis className="cool-custom-name" />
            <XAxis className="even-cooler-custom-name" />
            <VerticalBarSeries
              data={series[0].data}
              onNearestX={this._nearestXHandler}
              {...(series[0].disabled ? { opacity: 0.2 } : null)}
            />
            <LineSeries
              data={series[1].data}
              curve="curveMonotoneX"
              {...(series[1].disabled ? { opacity: 0.2 } : null)}
            />
            <Crosshair
              itemsFormat={this._formatCrosshairItems}
              titleFormat={this._formatCrosshairTitle}
              values={crosshairValues}
            />
          </FlexibleXYPlot>
        </div>

        {!forFrontPage && (
          <Button className="click-me" onClick={this._updateButtonClicked}>
            Click to update
          </Button>
        )}
      </div>
    );
  }
}
