import React, { Component } from 'react';
import { Sunburst } from 'react-vis';
import ChartWrapper from '../../chart.style';

const EXTENDED_DISCRETE_COLOR_RANGE = [
  '#19CDD7',
  '#DDB27C',
  '#88572C',
  '#FF991F',
  '#F15C17',
  '#223F9A',
  '#DA70BF',
  '#125C77',
  '#4DC19C',
  '#776E57',
  '#12939A',
  '#17B8BE',
  '#F6D18A',
  '#B7885E',
  '#FFCB99',
  '#F89570',
  '#829AE3',
  '#E79FD5',
  '#1E96BE',
  '#89DAC1',
  '#B3AD9E'
];

function getKeyPath(node) {
  if (!node.parent) {
    return ['root'];
  }

  return [node.data && (node.data.name || node.name)].concat(
    getKeyPath(node.parent)
  );
}

function updateData(data, keyPath) {
  if (data.children) {
    data.children.map(child => updateData(child, keyPath));
  }
  if (!data.color) {
    data.style = {
      fill: EXTENDED_DISCRETE_COLOR_RANGE[5]
    };
  }
  data.style = {
    ...data.style,
    fillOpacity: keyPath && !keyPath[data.name] ? 0.2 : 1
  };

  return data;
}

const decoratedData = datas => updateData(datas, false);

export default class extends Component {
  state = {
    pathValue: false,
    data: decoratedData(this.props.datas)
  };

  render() {
    const { data, pathValue } = this.state;
    return (
      <ChartWrapper className="isoChartWrapper">
        <Sunburst
          className="basic-sunburst-example"
          hideRootNode
          onValueMouseOver={node => {
            const path = getKeyPath(node).reverse();
            const pathAsMap = path.reduce((res, row) => {
              res[row] = true;
              return res;
            }, {});
            this.setState({
              pathValue: path.join(' > '),
              data: updateData(decoratedData(this.props.datas), pathAsMap)
            });
          }}
          onValueMouseOut={() =>
            this.setState({
              pathValue: false,
              data: updateData(decoratedData(this.props.datas), false)
            })}
          style={{
            stroke: '#ddd',
            strokeOpacity: 0.3,
            strokeWidth: '0.5'
          }}
          colorType="literal"
          data={data}
          height={this.props.height}
          width={this.props.width}
        />
        <div className="basic-sunburst-example-path-name">{pathValue}</div>
      </ChartWrapper>
    );
  }
}
