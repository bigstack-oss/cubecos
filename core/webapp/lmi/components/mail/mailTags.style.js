import styled from 'styled-components';
import { palette } from 'styled-theme';
import { borderRadius, transition } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const MailTagsList = styled.ul`
  padding: 30px 0;
  text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};

  .isoSectionLabel {
    font-size: 16px;
    font-weight: 500;
    color: ${palette('secondary', 2)};
    line-height: 1.1;
    margin-bottom: 20px;
    padding: 15px 30px;
    background-color: ${palette('grayscale', 6)};
  }

  .isoMailTag {
    width: 100%;
    display: flex;
    margin-bottom: 15px;
    padding: 0 30px;
    align-items: center;
    cursor: pointer;

    .isoLabelIndicatorColor {
      width: 10px;
      height: 10px;
      display: flex;
      margin: ${props => (props['data-rtl'] === 'rtl' ? '0 5px 0 0' : '0 0 0 5px')};
      ${borderRadius('50%')};
    }

    span {
      font-size: 14px;
      font-weight: 400;
      color: ${palette('secondary', 2)};
      cursor: pointer;
      line-height: 1.1;
      margin: ${props => (props['data-rtl'] === 'rtl' ? '0 20px 0 0' : '0 0 0 20px')};
      ${transition()};
    }

    &.active {
      span {
        font-weight: 500;
        color: ${palette('primary', 0)};
      }
    }

    &:hover {
      span {
        color: ${palette('primary', 0)};
      }
    }
  }
`;

export default WithDirection(MailTagsList);
