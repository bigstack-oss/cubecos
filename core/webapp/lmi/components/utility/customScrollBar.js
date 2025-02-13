import React from 'react';
import SmoothScrollbar from 'smooth-scrollbar';
import Scrollbar from 'react-smooth-scrollbar';


export default ({ style, children, className }) => (
  <Scrollbar className={className} style={style}>
    {children}
  </Scrollbar>
);
