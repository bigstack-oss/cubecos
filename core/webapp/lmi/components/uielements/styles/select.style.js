import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition } from '../../../config/style-util';

const AntSelect = ComponentName => styled(ComponentName)`
  &.ant-select {
    box-sizing: border-box;
    display: inline-block;
    position: relative;
    color: ${palette('text', 1)};
    font-size: 13px;

    .ant-select-selection {
      background-color: #fff;
      border-radius: 4px;
      border: 1px solid ${palette('border', 0)};
      ${transition()};

      &.ant-select-selection--single {
        height: 35px;
        position: relative;
        cursor: pointer;
      }

      .ant-select-selection__rendered {
        margin-left: 10px;
        margin-right: 10px;
        line-height: 33px;

        .ant-select-selection-selected-value {
          float: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
          padding: ${props =>
            props['data-rtl'] === 'rtl' ? '0 0 0 14px' : '0 14px 0 0'};
        }
      }

      .ant-select-arrow {
        right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '8px')};
        left: ${props => (props['data-rtl'] === 'rtl' ? '8px' : 'inherit')};
      }

      &:hover {
        border-color: ${palette('primary', 0)};
      }
    }

    &.ant-select-focused {
      .ant-select-selection {
        &:focus,
        &:active {
          border-color: ${palette('primary', 0)};
          outline: 0;
          box-shadow: 0 0 0 2px ${palette('primary', 3)};
        }
      }
    }

    &.ant-select-open {
      .ant-select-selection {
        border-color: ${palette('primary', 0)};
        outline: 0;
        box-shadow: 0 0 0 2px ${palette('primary', 3)};
      }
    }

    .ant-select-selection--multiple > ul > li,
    .ant-select-selection--multiple .ant-select-selection__rendered > ul > li {
      margin-top: 4px;
      height: 26px;
      line-height: 26px;
    }

    .ant-select-selection--multiple .ant-select-selection__choice {
      background-color: ${palette('grayscale', 4)};
      color: ${palette('text', 1)};
    }

    .ant-select-tree li a {
      font-size: 13px;
      color: ${palette('text', 1)};
    }
  }
`;

const AntSelectOption = ComponentName => styled(ComponentName)`
  color: #000000;
  .ant-select-dropdown-menu-item {
    color: ${palette('text', 1)};
  }
`;

export { AntSelect, AntSelectOption };
