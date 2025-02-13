import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const MailBucket = styled.ul`
  padding: 35px 0 0;

  .isoSingleBucket {
    width: 100%;
    display: flex;
    padding: 0 30px;
    margin-bottom: 15px;
    align-items: center;
    cursor: pointer;
    justify-content: space-between;

    span {
      font-size: 14px;
      font-weight: 400;
      color: ${palette('secondary', 2)};
      cursor: pointer;
      text-transform: capitalize;
      line-height: 1.1;
      ${transition()};
    }

    .isoMailBadge {
      font-size: 12px;
      font-weight: 500;
      color: ${palette('secondary', 2)};
      line-height: normal;
      margin: ${props =>
        props['data-rtl'] === 'rtl' ? '0 auto 0 0' : '0 0 0 auto'};
      display: -webkit-inline-flex;
      display: -ms-inline-flex;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      text-align: center;
    }

    &.active {
      span:not(.isoMailBadge) {
        font-weight: 500;
        color: ${palette('primary', 0)};
      }
    }

    span:not(.isoMailBadge) {
      &:hover {
        color: ${palette('primary', 0)};
      }
    }
  }
`;

export default WithDirection(MailBucket);
