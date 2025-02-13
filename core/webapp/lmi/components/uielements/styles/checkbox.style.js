import styled from 'styled-components';
import { palette } from 'styled-theme';

const AntCheckbox = ComponentName => styled(ComponentName)`
  &.ant-checkbox-wrapper {
    font-size: 13px;
    color: ${palette('text', 1)};

    .ant-checkbox-checked .ant-checkbox-inner,
    .ant-checkbox-indeterminate .ant-checkbox-inner {
      background-color: ${palette('primary', 0)};
      border-color: ${palette('primary', 0)};
    }

    .ant-checkbox:hover .ant-checkbox-inner,
    .ant-checkbox-input:focus + .ant-checkbox-inner {
      border-color: ${palette('primary', 0)};
    }

    &:hover {
      .ant-checkbox-inner {
        border-color: ${palette('primary', 0)};
      }
    }
  }
`;

export default AntCheckbox;
