import styled from 'styled-components';
import { palette } from 'styled-theme';
import {
  transition,
  borderRadius,
  boxShadow,
} from '../../../config/style-util';

const AntTransfer = ComponentName => styled(ComponentName)`
  display: flex;

  @media only screen and (max-width: 560px) {
    flex-direction: column;
  }

  .ant-transfer-list {
    font-size: 13px;
    border: 1px solid ${palette('border', 0)};;
    background-color: #ffffff;
    display: inline-block;
    border-radius: 5px;
    vertical-align: middle;
    position: relative;
    width: 180px;
    height: 200px;
    padding-top: 33px;

    .ant-transfer-list-header {
      padding: 7px 15px;
      border-radius: 5px 5px 0 0;
      background: ${palette('secondary', 1)};
      color: ${palette('text', 1)};;
      border-bottom: 1px solid ${palette('border', 0)};
      overflow: hidden;
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;

      .ant-transfer-list-header-selected {
        color: ${palette('text', 1)};
        font-size: 12px;
      }
    }

    .ant-transfer-list-body {
      padding-top: 38px;
      .ant-transfer-list-body-search-wrapper {
        padding: 5px;

        .ant-input {
          &.ant-transfer-list-search {
            font-size: 13px;
            font-weight: 400;
            color: ${palette('text', 2)};
            line-height: inherit;
            padding: 4px 10px;
            height: 28px;
            border: 1px solid ${palette('border', 0)};
            outline: 0 !important;
            overflow: hidden;
            background-color: #ffffff;
            ${borderRadius('3px')};
            ${boxShadow()};
            ${transition()};

            &:focus,
            &:hover {
              border-color: ${palette('border', 0)};
              box-shadow: none;
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
        }
      }

      .ant-transfer-list-content-item {
        span {
          font-size: 12px;
          color: ${palette('secondary', 2)};
        }

        &:not(.ant-transfer-list-content-item-disabled) {
          &:hover {
            cursor: pointer;
            background-color: ${palette('secondary', 1)};
          }
        }
      }
    }

    .ant-checkbox-wrapper:not(:last-child) {
      margin: ${props =>
        props['data-rtl'] === 'rtl' ? '0 0 0 8px' : '0 8px 0 0'};
    }
  }

  .ant-transfer-operation {
    display: flex;
    flex-direction: column;
    justify-content: center;

    @media only screen and (max-width: 560px) {
      margin: 15px 0;
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      width: 180px;
    }
    .ant-btn-primary {
      color: #fff;
      background-color: ${palette('primary', 0)};
      border-color: ${palette('primary', 0)};
      padding: 0 8px;
    }

    .ant-btn-primary.disabled,
    .ant-btn-primary[disabled],
    .ant-btn-primary.disabled:hover,
    .ant-btn-primary[disabled]:hover,
    .ant-btn-primary.disabled:focus,
    .ant-btn-primary[disabled]:focus,
    .ant-btn-primary.disabled:active,
    .ant-btn-primary[disabled]:active,
    .ant-btn-primary.disabled.active,
    .ant-btn-primary[disabled].active {
      color: #d8d8d8;
      background-color: ${palette('grayscale', 4)};
      border-color: ${palette('border', 0)};
    }

    .ant-btn{
      .anticon-left,
      .anticon-right{
        transform: ${props =>
          props['data-rtl'] === 'rtl' ? 'rotate(180deg)' : 'rotate(0)'};
      }
    }
  }

  .ant-transfer-list-search-action {
    width: 28px;
    line-height: 28px;
    right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '4px')};
    left: ${props => (props['data-rtl'] === 'rtl' ? '4px' : 'inherit')};
  }
}

`;

export default AntTransfer;
