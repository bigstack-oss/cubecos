// dashboard/components/widget-wrapper.js

import React from 'react';
import styled from 'styled-components';

import { media } from '../../../config/style-util';

const WidgetWrapperDiv = styled.div`
  margin: 0 10px;

  @media only screen and (max-width: 767) {
    margin-right: 0 !important;
  }
`;

const WidgetWrapper = ({ width, gutterTop, gutterRight, gutterBottom, gutterLeft, padding, bgColor, children }) => {
  const wrapperStyle = {
    width: width,
    marginTop: gutterTop,
    marginRight: gutterRight,
    marginBottom: gutterBottom,
    marginLeft: gutterLeft,
    padding: padding,
    backgroundColor: bgColor,
  };
  return (
    <WidgetWrapperDiv style={wrapperStyle}>
      {children}
    </WidgetWrapperDiv>
  );
}

export default WidgetWrapper;