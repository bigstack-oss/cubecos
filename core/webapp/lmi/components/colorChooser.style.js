import styled from 'styled-components';
import { borderRadius } from '../config/style-util';
import WithDirection from '../config/withDirection';

const ColorChooserDropdown = styled.div`
  display: flex;
  flex-flow: row wrap;
  max-width: 160px;

  .ant-btn {
    width: 20px;
    height: 20px;
    border: 0;
    outline: 0;
    padding: 0;
    margin: ${props =>
      props['data-rtl'] === 'rtl' ? '0 0 0 15px' : '0 15px 0 0'};
    ${borderRadius('3px')};

    &:last-child {
      margin: 0;
    }

    &:nth-child(n + 6) {
      margin-top: 15px;
    }

    &:nth-child(5n) {
      margin-right: 0;
      margin-left: 0;
    }
  }
`;

export default WithDirection(ColorChooserDropdown);
