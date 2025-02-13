import React from 'react';
import { ContentHolderWrapper } from './contentHolder.style';

export default props => (
  <ContentHolderWrapper className="isoExampleWrapper">
    {props.children}
  </ContentHolderWrapper>
);
