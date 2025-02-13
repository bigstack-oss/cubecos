import styled from 'styled-components';
import { palette } from 'styled-theme';
import {
  transition,
  borderRadius,
  boxShadow,
} from '../../../config/style-util';

const InputWrapper = ComponentName => styled(ComponentName)`
  &.ant-input {
    padding: 4px 10px;
    width: 100%;
    height: 35px;
    cursor: text;
    text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
    font-size: 13px;
    line-height: 1.5;
    color: ${palette('text', 1)};
    background-color: #fff;
    background-image: none;
    border: 1px solid ${palette('border', 0)};
    ${borderRadius('4px')};
    ${transition()};

    &:focus {
      border-color: ${palette('primary', 0)};
    }

    &.ant-input-lg {
      height: 42px;
      padding: 6px 10px;
    }

    &.ant-input-sm {
      padding: 1px 10px;
      height: 30px;
    }

    &::-webkit-input-placeholder {
      text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
      color: ${palette('grayscale', 0)};
    }

    &:-moz-placeholder {
      text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
      color: ${palette('grayscale', 0)};
    }

    &::-moz-placeholder {
      text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
      color: ${palette('grayscale', 0)};
    }
    &:-ms-input-placeholder {
      text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
      color: ${palette('grayscale', 0)};
    }
  }
  .ant-form-item-children-icon {
    display: none;
  }
`;
const InputGroupWrapper = ComponentName => styled(ComponentName)`
  &.ant-input-group {
    margin-bottom: 10px;

    .ant-select-auto-complete {
      margin-right: ${props => (props['data-rtl'] === 'rtl' ? '-1px' : '0')};
    }

    .ant-input {
      &:first-child {
        border-radius: ${props =>
          props['data-rtl'] === 'rtl' ? '0 4px 4px 0' : '4px 0 0 4px'};
      }
    }

    .ant-input-group-addon:not(:first-child):not(:last-child),
    .ant-input-group-wrap:not(:first-child):not(:last-child),
    > .ant-input:not(:first-child):not(:last-child) {
      padding: 0 7px;
      border-left-width: ${props =>
        props['data-rtl'] === 'rtl' ? '0' : '1px'};
      margin-right: ${props => (props['data-rtl'] === 'rtl' ? '-1px' : '0')};
    }

    .ant-input-group-addon {
      padding: 4px 7px;
      font-size: 12px;
      color: ${palette('text', 1)};
      text-align: center;
      background-color: ${palette('grayscale', 4)};
      border: 1px solid ${palette('border', 0)};
      ${transition()};

      &:first-child {
        border-right-width: ${props =>
          props['data-rtl'] === 'rtl' ? '1px' : '0'};
        border-left-width: ${props =>
          props['data-rtl'] === 'rtl' ? '0' : '1px'};
        border-radius: ${props =>
          props['data-rtl'] === 'rtl' ? '0 4px 4px 0' : '4px 0 0 4px'};
      }

      &:last-child {
        border-right-width: ${props =>
          props['data-rtl'] === 'rtl' ? '0' : '1px'};
        border-left-width: ${props =>
          props['data-rtl'] === 'rtl' ? '1px' : '0'};
        border-radius: ${props =>
          props['data-rtl'] === 'rtl' ? '4px 0 0 4px' : '0 4px 4px 0'};
      }

      .ant-select {
        .ant-select-selection {
          background-color: inherit;
          margin: -1px;
          border: 1px solid transparent;
          ${boxShadow()};
        }
      }
    }

    .ant-input-group-addon:not(:first-child):not(:last-child),
    .ant-input-group-wrap:not(:first-child):not(:last-child) {
      border-left: 0;
      border-right: 0;
    }

    & > .ant-input:not(:first-child):not(:last-child) {
      ${'' /* border-left: 0; */};
    }

    .ant-input:first-child:last-child {
      border-radius: 4px;
    }

    &.ant-input-group-compact > * {
      border-right-width: ${props =>
        props['data-rtl'] === 'rtl' ? '1px ' : '0'};
    }

    &.ant-input-group-compact > .ant-select > .ant-select-selection,
    &.ant-input-group-compact > .ant-calendar-picker .ant-input,
    &.ant-input-group-compact > .ant-select-auto-complete .ant-input,
    &.ant-input-group-compact > .ant-cascader-picker .ant-input,
    &.ant-input-group-compact > .ant-mention-wrapper .ant-mention-editor,
    &.ant-input-group-compact > .ant-time-picker .ant-time-picker-input {
      border-right-width: ${props =>
        props['data-rtl'] === 'rtl' ? '1px ' : '0'};
    }

    &.ant-input-group-compact > *:first-child,
    &.ant-input-group-compact > .ant-select:first-child > .ant-select-selection,
    &.ant-input-group-compact > .ant-calendar-picker:first-child .ant-input,
    &.ant-input-group-compact
      > .ant-select-auto-complete:first-child
      .ant-input,
    &.ant-input-group-compact > .ant-cascader-picker:first-child .ant-input,
    &.ant-input-group-compact
      > .ant-mention-wrapper:first-child
      .ant-mention-editor,
    &.ant-input-group-compact
      > .ant-time-picker:first-child
      .ant-time-picker-input {
      border-radius: ${props =>
        props['data-rtl'] === 'rtl' ? '0 4px 4px 0' : '4px 0 0 4px'};
      border-left-width: 1px
        ${'' /* border-right-width: ${props =>
        props['data-rtl'] === 'rtl' ? '1px' : '0'}; */};
    }

    &.ant-input-group-compact > *:last-child,
    &.ant-input-group-compact > .ant-select:last-child > .ant-select-selection,
    &.ant-input-group-compact > .ant-calendar-picker:last-child .ant-input,
    &.ant-input-group-compact > .ant-select-auto-complete:last-child .ant-input,
    &.ant-input-group-compact > .ant-cascader-picker:last-child .ant-input,
    &.ant-input-group-compact
      > .ant-mention-wrapper:last-child
      .ant-mention-editor,
    &.ant-input-group-compact
      > .ant-time-picker:last-child
      .ant-time-picker-input {
      border-radius: ${props =>
        props['data-rtl'] === 'rtl' ? '4px 0 0 4px' : '0 4px 4px 0'};
      border-right-width: ${props =>
        props['data-rtl'] === 'rtl' ? '0 ' : '1px'};
    }

    .ant-calendar-picker-clear,
    .ant-calendar-picker-icon {
      right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '8px')};
      left: ${props => (props['data-rtl'] === 'rtl' ? '8px' : 'inherit')};
    }
  }

  &.ant-input-group-lg {
    .ant-input,
    > .ant-input-group-addon {
      padding: 6px 10px;
      height: 35px;
    }
  }
`;

const TextAreaWrapper = ComponentName => styled(ComponentName)`
  &.ant-input {
    padding: 4px 10px;
    width: 100%;
    height: auto;
    cursor: text;
    font-size: 13px;
    line-height: 1.5;
    color: ${palette('text', 1)};
    background-color: #fff;
    background-image: none;
    border: 1px solid ${palette('border', 0)};
    ${borderRadius('4px')};
    ${transition()};

    &:focus {
      border-color: ${palette('primary', 0)};
    }

    &::-webkit-input-placeholder {
      color: ${palette('grayscale', 0)};
    }

    &:-moz-placeholder {
      color: ${palette('grayscale', 0)};
    }

    &::-moz-placeholder {
      color: ${palette('grayscale', 0)};
    }
    &:-ms-input-placeholder {
      color: ${palette('grayscale', 0)};
    }
  }
`;

const InputSearchWrapper = ComponentName => styled(ComponentName)`
  &.ant-input-affix-wrapper {
    .ant-input {
      padding: 4px 10px;
      width: 100%;
      height: 35px;
      cursor: text;
      font-size: 13px;
      line-height: 1.5;
      color: ${palette('text', 1)};
      background-color: #fff;
      background-image: none;
      border: 1px solid ${palette('border', 0)};
      ${borderRadius('4px')};
      ${transition()};

      &:focus {
        border-color: ${palette('primary', 0)};
      }

      &.ant-input-lg {
        height: 42px;
        padding: 6px 10px;
      }

      &.ant-input-sm {
        padding: 1px 10px;
        height: 30px;
      }

      &::-webkit-input-placeholder {
        color: ${palette('grayscale', 0)};
      }

      &:-moz-placeholder {
        color: ${palette('grayscale', 0)};
      }

      &::-moz-placeholder {
        color: ${palette('grayscale', 0)};
      }
      &:-ms-input-placeholder {
        color: ${palette('grayscale', 0)};
      }
    }

    .ant-input-suffix {
      right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '7px')};
      left: ${props => (props['data-rtl'] === 'rtl' ? '7px' : 'inherit')};
    }

    .ant-input-ant-input-prefix {
      right: ${props => (props['data-rtl'] === 'rtl' ? '7px' : 'inherit')};
      left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '7px')};
    }

    .ant-input-search-icon {
      color: ${palette('grayscale', 0)};

      &:hover {
        color: ${palette('primary', 0)};
      }
    }
  }
`;

export { InputWrapper, InputGroupWrapper, InputSearchWrapper, TextAreaWrapper };
