import styled from 'styled-components';
import { palette } from 'styled-theme';
import WithDirection from '../../../config/withDirection';

const PopoverWrapper = styled.div`
  font-size: 13px;
  color: ${palette('text', 1)};
  text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
`;

export default WithDirection(PopoverWrapper);
