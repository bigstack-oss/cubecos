import styled from 'styled-components';
import { palette } from 'styled-theme';
import { borderRadius } from '../../../config/style-util';

const PopoverWrapper = ComponentName => styled(ComponentName)`
  display: inline-block;

  .ant-popover {
    font-size: 13px;

    .ant-popover-inner {
      .ant-popover-title {
        background-color: ${palette('grayscale', 5)};
        font-size: 14px;
        font-weight: 500;
        color: ${palette('text', 0)};
        line-height: 35px;
        height: 35px;
        border-bottom: 1px solid ${palette('border', 0)};
        ${borderRadius('4px 4px 0 0')};
      }

      .ant-popover-inner-content {
        color: ${palette('text', 3)};

        a {
          color: ${palette('primary', 0)};
        }

        .ant-popover-message {
          padding: 8px 0 16px;
          font-size: 13px;
          color: ${palette('text', 1)};

          > .anticon {
            color: ${palette('warning', 0)};
            font-size: 14px;
            margin-top: 1px;
          }
        }
      }
    }

    &.ant-popover-placement-rightTop {
      > .ant-popover-content {
        > .ant-popover-arrow {
          background-color: transparent;
          &:after {
            border-right-color: ${palette('grayscale', 6)};
          }
        }
      }
    }

    &.ant-popover-placement-leftTop {
      > .ant-popover-content {
        > .ant-popover-arrow {
          background-color: transparent;
          &:after {
            border-left-color: ${palette('grayscale', 6)};
          }
        }
      }
    }

    &.ant-popover-placement-bottom,
    &.ant-popover-placement-bottomLeft,
    &.ant-popover-placement-bottomRight {
      > .ant-popover-content {
        > .ant-popover-arrow {
          background-color: transparent;
          &:after {
            border-bottom-color: ${palette('grayscale', 6)};
          }
        }
      }
    }
  }
`;

export default PopoverWrapper;
