import React, { Component } from 'react';
import Async from '../../../helpers/asyncComponent';
import {
  data,
  autoDraw,
  autoDrawDuration,
  autoDrawEasing,
  smooth,
  gradient,
  radius,
  strokeWidth,
  strokeLinecap
} from './config';
import PageHeader from '../../../components/utility/pageHeader';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import Box from '../../../components/utility/box';

const Trend = props => (
  <Async
    load={import(/* webpackChunkName: "react-trend" */ 'react-trend')}
    componentProps={props}
  />
);

export default class extends Component {
  render() {
    return (
      <LayoutWrapper className="isoMapPage">
        <PageHeader>React Trend</PageHeader>

        <Box>
          <Trend
            smooth={smooth}
            autoDraw={autoDraw}
            autoDrawDuration={parseInt(autoDrawDuration, 10)}
            autoDrawEasing={autoDrawEasing}
            height={100}
            width={600}
            data={data}
            gradient={gradient}
            radius={parseInt(radius, 10)}
            strokeWidth={strokeWidth}
            strokeLinecap={strokeLinecap}
          />
        </Box>
      </LayoutWrapper>
    );
  }
}
