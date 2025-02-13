import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const MailPagination = styled.div`
  display: -webkit-flex;
  display: -ms-flex;
  display: flex;
  align-items: center;

  button {
    font-size: 16px;
    color: ${palette('secondary', 0)};
    width: 35px;
    height: 35px;
    display: flex;
    align-items: center;
    justify-content: center;
    background-color: #ffffff;
    outline: 0;
    border: 1px solid ${palette('border', 0)};
    cursor: pointer;
    ${transition()};

    i {
      font-size: 18px;
      width: 100%;
      height: 100%;
      color: ${palette('secondary', 0)};
      ${transition()};
    }

    &.nextPage {
      margin: ${props =>
        props['data-rtl'] === 'rtl' ? '0 -1px 0 0' : '0 0 0 -1px'};
    }

    &:hover {
      color: ${palette('primary', 0)};
      background-color: darken(#ffffff, 1%);

      i {
        color: ${palette('primary', 0)};
      }
    }
  }
`;

export default WithDirection(MailPagination);
