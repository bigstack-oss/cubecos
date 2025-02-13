import React, { Component } from 'react';
import { Treemap } from 'react-vis';
import Button from '../button';
import ChartWrapper from '../../chart.style';

function _getRandomData() {
  const totalLeaves = Math.random() * 20;
  const leaves = [];
  let title;
  for (let i = 0; i < totalLeaves; i++) {
    title = Math.random();
    if (Math.random() > 0.5) {
      title = <b>{title}</b>;
    }
    leaves.push({
      title,
      size: Math.random() * 1000,
      color: Math.random()
    });
  }
  return {
    title: '',
    color: 1,
    children: leaves
  };
}

export default class extends Component {
  state = {
    hoveredNode: false,
    treemapData: _getRandomData(),
    useCirclePacking: false
  };

  render() {
    const { hoveredNode, useCirclePacking } = this.state;
    const { width, height } = this.props;
    const treeProps = {
      animation: {
        damping: 9,
        stiffness: 300
      },
      data: this.state.treemapData,
      onLeafMouseOver: x => this.setState({ hoveredNode: x }),
      onLeafMouseOut: () => this.setState({ hoveredNode: false }),
      onLeafClick: () => this.setState({ treemapData: _getRandomData() }),
      height: height,
      mode: this.state.useCirclePacking ? 'circlePack' : 'squarify',
      width: width
    };
    return (
      <ChartWrapper className="isoChartWrapper">
        <div className="isoChartControl">
          <Button
            onClick={() =>
              this.setState({ useCirclePacking: !useCirclePacking })}
            buttonContent={'TOGGLE CIRCLE PACK'}
          />
        </div>
        <Treemap {...treeProps} />
        click above to the update data
        {hoveredNode && hoveredNode.value}
      </ChartWrapper>
    );
  }
}
