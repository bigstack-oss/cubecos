import styled from 'styled-components';
import { palette } from 'styled-theme';
import WithDirection from '../../config/withDirection';

const WDContentHolderWrapper = styled.div`
  margin-top: 30px;
  -webkit-overflow-scrolling: touch;

  .demoBtn {
    margin-right: ${props => (props['data-rtl'] === 'rtl' ? '0' : '10px')};
    margin-left: ${props => (props['data-rtl'] === 'rtl' ? '10px' : '0')};
  }

  .demoBtnsWrapper {
    &:nth-child(1) {
      margin-left: ${props => (props['data-rtl'] === 'rtl' ? '0' : '70px')};
      margin-right: ${props => (props['data-rtl'] === 'rtl' ? '70px' : '0')};
      white-space: nowrap;
    }

    &:nth-child(2) {
      width: 70px;
      float: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
    }

    &:nth-child(3) {
      width: 70px;
      margin-left: ${props => (props['data-rtl'] === 'rtl' ? '0' : '295px')};
      margin-right: ${props => (props['data-rtl'] === 'rtl' ? '295px' : '0')};
    }

    &:nth-child(4) {
      margin-left: ${props => (props['data-rtl'] === 'rtl' ? '0' : '70px')};
      margin-right: ${props => (props['data-rtl'] === 'rtl' ? '70px' : '0')};
      clear: both;
      white-space: nowrap;
    }

    @media only screen and (max-width: 480px) {
      margin-left: ${props => (props['data-rtl'] === 'rtl' ? '8px' : '0 !important')};
      white-space: nowrap;
      margin-right: ${props => (props['data-rtl'] === 'rtl' ? '0 !important' : '8px')};
      float: none !important;
    }

    .demoPosBtn {
      width: 70px;
      margin-right: ${props => (props['data-rtl'] === 'rtl' ? '0' : '8px')};
      margin-left: ${props => (props['data-rtl'] === 'rtl' ? '8px' : '0')};
      margin-bottom: 8px;
      padding: 0;

      @media only screen and (max-width: 480px) {
        width: 65px;
      }
    }
  }

  .ant-btn {
    &:not(.demoPosBtn) {
      &:last-child {
        margin-right: 0;
      }
    }
  }

  .tooltipBtn {
    display: inline-block;
    line-height: 32px;
    height: 32px;
    width: 70px;
    font-size: 14px;
    text-align: center;
    background: ${palette('secondary', 1)};
    margin-right: ${props => (props['data-rtl'] === 'rtl' ? 'auto' : '6px')};
    margin-left: ${props => (props['data-rtl'] === 'rtl' ? '6px' : '0')};
    margin-bottom: 6px;
    border-radius: 6px;
  }

  .ant-progress {
    &.ant-progress-circle {
      margin-right: ${props => (props['data-rtl'] === 'rtl' ? '0' : '15px')};
      margin-left: ${props => (props['data-rtl'] === 'rtl' ? '15px' : '0')};

      &:last-child {
        margin-right: ${props => (props['data-rtl'] === 'rtl' ? '0' : '0')};
        margin-left: ${props => (props['data-rtl'] === 'rtl' ? '0' : '0')};
      }
    }
  }

  strong {
    font-weight: 700;
    font-size: 14px;
  }
`;

const ContentHolderWrapper = WithDirection(WDContentHolderWrapper);

export { ContentHolderWrapper };
