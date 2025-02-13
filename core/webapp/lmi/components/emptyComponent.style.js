import styled from 'styled-components';
import { palette } from 'styled-theme';

const EmptyComponent = styled.div`
  min-height: 74vh;
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: center;

  span {
    font-size: 36px;
    font-weight: 300;
    color: ${palette('grayscale', 1)};
    line-height: 1.5;
  }
`;

export { EmptyComponent };
