import React, { Component } from 'react';
import { stack as d3Stack, stackOffsetWiggle } from 'd3-shape';
import { range, transpose } from 'd3-array';

import { XYPlot, makeWidthFlexible, AreaSeries } from 'react-vis';
import Button from '../../../../components/uielements/button';

const FlexibleXYPlot = makeWidthFlexible(XYPlot);

const NUMBER_OF_LAYERS = 20;
const SAMPLES_PER_LAYER = 200;
const BUMPS_PER_LAYER = 10;

const bump = (aggregatingData, samplesPerLayer) => {
  const x = 1 / (0.1 + Math.random());
  const y = 2 * Math.random() - 0.5;
  const z = 10 / (0.1 + Math.random());

  return aggregatingData.map((v, i) => {
    const w = (i / samplesPerLayer - y) * z;
    return v + x * Math.exp(-w * w);
  });
};

function bumps(samplesPerLayer, bumpsPerLayer) {
  const dataOutline = new Array(samplesPerLayer).fill(0);
  return range(bumpsPerLayer).reduce(
    res => bump(res, samplesPerLayer),
    dataOutline
  );
}

function generateData() {
  const stack = d3Stack()
    .keys(range(NUMBER_OF_LAYERS))
    .offset(stackOffsetWiggle);
  const transposed = transpose(
    range(NUMBER_OF_LAYERS).map(() => bumps(SAMPLES_PER_LAYER, BUMPS_PER_LAYER))
  );
  return stack(transposed).map(series =>
    series.map((row, x) => ({ x, y0: row[0], y: row[1] }))
  );
}

export default class extends Component {
  state = {
    data: generateData(),
    hoveredIndex: false
  };

  render() {
    const { forFrontPage } = this.props;
    const { data, hoveredIndex } = this.state;
    return (
      <div className="streamgraph-example">
        {!forFrontPage && (
          <Button
            className="showcase-button"
            onClick={() => this.setState({ data: generateData() })}
          >
            Click me!
          </Button>
        )}
        <div className="streamgraph">
          <FlexibleXYPlot
            animation
            onMouseLeave={() => this.setState({ hoveredIndex: false })}
            height={300}
          >
            {data.map((series, index) => (
              <AreaSeries
                key={index}
                curve="curveNatural"
                className={`${index === hoveredIndex
                  ? 'highlighted-stream'
                  : ''}`}
                onSeriesMouseOver={() => this.setState({ hoveredIndex: index })}
                data={series}
              />
            ))}
          </FlexibleXYPlot>
        </div>
      </div>
    );
  }
}
