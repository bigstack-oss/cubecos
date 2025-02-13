import styled from 'styled-components';
import { palette } from 'styled-theme';

const AntSwitch = ComponentName => styled(ComponentName)`
  &.ant-switch-checked {
    border-color: ${palette('primary', 0)};
    background-color: ${palette('primary', 0)};
  }
`;

export default AntSwitch;
