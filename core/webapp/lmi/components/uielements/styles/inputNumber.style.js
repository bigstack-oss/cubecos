import styled from 'styled-components';
import { palette } from 'styled-theme';

const AntInputNumber = ComponentName => styled(ComponentName)`
  &.ant-input-number {
    color: ${palette('texy', 1)};
    padding: 0;
    font-size: 13px;
    height: 35px !important;
    border: 1px solid ${palette('border', 0)};
    width: 100%;
    max-width: 80px;

    .ant-input-number-input {
      height: 33px;
      color: ${palette('text', 1)};
      padding: 0 10px;
      text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
    }

    &.ant-input-number-focused {
      border-color: ${palette('primary', 0)};
    }

    .ant-input-number-handler-wrap {
      left: ${props => (props['data-rtl'] === 'rtl' ? '0' : 'inherit')};
      right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
      border-radius: ${props =>
        props['data-rtl'] === 'rtl' ? '4px 0 0 4px' : '0 4px 4px 0'};
      border-left: ${props => (props['data-rtl'] === 'rtl' ? 0 : 1)}px solid
        ${palette('border', 1)};
      border-right: ${props => (props['data-rtl'] === 'rtl' ? 1 : 0)}px solid
        ${palette('border', 1)};
    }

    .ant-input-number-handler-up-inner,
    .ant-input-number-handler-down-inner {
      font-size: 23px;
      color: ${palette('text', 2)};

      &:before {
        display: block;
        font-family: 'ionicons' !important;
      }
    }

    .ant-input-number-handler-up-inner {
      &:before {
        content: '\f365';
      }
    }

    .ant-input-number-handler-down-inner {
      &:before {
        content: '\f35f';
      }
    }
  }
`;

export default AntInputNumber;
