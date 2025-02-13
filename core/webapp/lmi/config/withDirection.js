import React from 'react';
import { langDir } from './index';

const rtl = langDir; 
const withDirection = Component => props => {
  return <Component {...props} data-rtl={rtl} />;
};

export default withDirection;
export { rtl };
