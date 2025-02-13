import styled from 'styled-components';
import { palette } from 'styled-theme';

const AntTimeline = ComponentName => styled(ComponentName)`
  &.ant-timeline {
    .ant-timeline-item-content {
      font-size: 13px;
      color: ${palette('text', 3)};
      padding: ${props =>
        props['data-rtl'] === 'rtl' ? '0 24px 10px 0' : '0 0 10px 24px'};
    }
    .ant-timeline-item-tail {
      left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '5px')};
      right: ${props => (props['data-rtl'] === 'rtl' ? '5px' : 'inherit')};
    }
    .ant-timeline-item-head-custom {
      left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '-14px')};
      right: ${props => (props['data-rtl'] === 'rtl' ? '-14px' : 'inherit')};
    }
  }
`;

export default AntTimeline;
