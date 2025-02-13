import React from 'react';
import { AbstractSeries } from 'react-vis';

const predefinedClassName =
  'rv-xy-plot__series rv-xy-plot__series--candlestick';

export default class extends AbstractSeries {
  render() {
    const { className, data, marginLeft, marginTop } = this.props;
    if (!data) {
      return null;
    }
    const xFunctor = this._getAttributeFunctor('x');
    const yFunctor = this._getAttributeFunctor('y');
    const strokeFunctor =
      this._getAttributeFunctor('stroke') || this._getAttributeFunctor('color');
    const fillFunctor =
      this._getAttributeFunctor('fill') || this._getAttributeFunctor('color');
    const opacityFunctor = this._getAttributeFunctor('opacity');

    const distance = Math.abs(xFunctor(data[1]) - xFunctor(data[0])) * 0.2;

    return (
      <g
        className={`${predefinedClassName} ${className}`}
        ref="container"
        transform={`translate(${marginLeft},${marginTop})`}
      >
        {data.map((d, i) => {
          const xTrans = xFunctor(d);
          const yHigh = yFunctor({ ...d, y: d.yHigh });
          const yOpen = yFunctor({ ...d, y: d.yOpen });
          const yClose = yFunctor({ ...d, y: d.yClose });
          const yLow = yFunctor({ ...d, y: d.yLow });

          const lineAttrs = {
            stroke: strokeFunctor && strokeFunctor(d)
          };

          const xWidth = distance * 2;
          return (
            <g
              transform={`translate(${xTrans})`}
              opacity={opacityFunctor ? opacityFunctor(d) : 1}
              key={i}
              onClick={e => this._valueClickHandler(d, e)}
              onMouseOver={e => this._valueMouseOverHandler(d, e)}
              onMouseOut={e => this._valueMouseOutHandler(d, e)}
            >
              <line
                x1={-xWidth}
                x2={xWidth}
                y1={yHigh}
                y2={yHigh}
                {...lineAttrs}
              />
              <line x1={0} x2={0} y1={yHigh} y2={yLow} {...lineAttrs} />
              <line
                x1={-xWidth}
                x2={xWidth}
                y1={yLow}
                y2={yLow}
                {...lineAttrs}
              />
              <rect
                x={-xWidth}
                width={Math.max(xWidth * 2, 0)}
                y={yOpen}
                height={Math.abs(yOpen - yClose)}
                fill={fillFunctor && fillFunctor(d)}
              />
            </g>
          );
        })}
      </g>
    );
  }
}
