import styled from 'styled-components';
import { palette } from 'styled-theme';

const AntTree = ComponentName => styled(ComponentName)`
  &.ant-tree {
    li ul {
      margin: 0;
      padding: ${props =>
        props['data-rtl'] === 'rtl' ? '0 18px 0 0' : '0 0 0 18px'};
    }

    li .ant-tree-node-content-wrapper.ant-tree-node-selected {
      background-color: ${palette('primary', 3)};
    }
  }
`;

export default AntTree;
