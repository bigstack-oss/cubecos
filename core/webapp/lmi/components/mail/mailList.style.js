import styled from 'styled-components';
import { palette } from 'styled-theme';
import { borderRadius, transition } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const MailListWrapper = styled.div`
  width: 100%;
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow-y: auto;

  .isoMailList {
    width: 100%;
    padding: 30px;
    display: flex;
    flex-shrink: 0;
    border-bottom: 1px solid ${palette('border', 0)};
    overflow: hidden;
    position: relative;
    text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
    cursor: pointer;
    ${transition()};

    .isoLabelIndicator {
      width: 0;
      height: 0;
      border-style: solid;
      border-width: ${props =>
        props['data-rtl'] === 'rtl' ? '0 15px 15px 0;' : '15px 15px 0 0'};
      border-color: transparent transparent transparent transparent;
      position: absolute;
      top: 0;
      left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
      right: ${props => (props['data-rtl'] === 'rtl' ? '0' : 'inherit')};
    }

    &:last-child {
      border-bottom: 0;
    }

    .isoRecipentsImg {
      width: 48px;
      height: 48px;
      display: -webkit-inline-flex;
      display: -ms-inline-flex;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      overflow: hidden;
      flex-shrink: 0;
      ${borderRadius('50%')};

      img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }

      span {
        width: 100%;
        height: 100%;
        display: flex;
        align-items: center;
        justify-content: center;
        background-color: ${palette('color', 4)};
        font-size: 16px;
        font-weight: 300;
        color: #fff;
        letter-spacing: 1px;
      }
    }

    .isoMailInfo {
      width: 100%;
      padding: ${props => (props['data-rtl'] === 'rtl' ? '0 20px 0 0' : '0 0 0 20px')};

      .infoHead {
        width: 100%;
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        margin-bottom: 3px;

        .isoRecipents {
          font-size: 13px;
          font-weight: 400;
          color: ${palette('secondary', 2)};
        }

        .isoReceiveDate {
          font-size: 11px;
          font-weight: 400;
          color: ${palette('secondary', 2)};
          flex-shrink: 0;
        }
      }

      .isoSubject {
        font-size: 14px;
        font-weight: 500;
        color: ${palette('secondary', 0)};
        margin: 0;
      }
    }

    &.unreadMail {
      background-color: ${palette('secondary', 8)};
    }

    &:hover {
      background-color: ${palette('secondary', 8)};
    }

    &.activeMail {
      background-color: ${palette('secondary', 9)};
    }
  }

  .isoDescription {
    white-space: nowrap;
    text-overflow: ellipsis;
    padding: 0 30px;
    width: 100%;
    overflow: hidden;
  }
`;

export default WithDirection(MailListWrapper);
