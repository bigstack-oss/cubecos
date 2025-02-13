import React, { Component } from 'react';
import { XYPlot, XAxis, YAxis, LineSeries, makeWidthFlexible } from 'react-vis';
import CandlestickScss from './candlestick.scss';
import Candlestick from './candlestick';

const FlexibleXYPlot = makeWidthFlexible(XYPlot);

export default class extends Component {
  state = {
    data: this.props.datas
  };

  render() {
    const { data } = this.state;
    return (
      <div>
        <style>{CandlestickScss}</style>
        <div className="candlestick-example">
          <div className="chart">
            <FlexibleXYPlot
              animation
              yDomain={[0, 100]}
              height={this.props.height}
            >
              <XAxis />
              <YAxis />
              <LineSeries color="#12939A" data={data} />
              <LineSeries
                color="#FF9833"
                className="dashed-example-line"
                data={[{ x: 0, y: 25 }, { x: 30, y: 25 }]}
              />
              <LineSeries
                color="#1A3177"
                className="dashed-example-line"
                opacity={0.3}
                data={[{ x: 0, y: 75 }, { x: 30, y: 75 }]}
              />
              <Candlestick
                colorType="literal"
                opacityType="literal"
                stroke="#79C7E3"
                data={data}
              />
            </FlexibleXYPlot>
          </div>
        </div>
      </div>
    );
  }
}
