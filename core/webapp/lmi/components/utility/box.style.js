import styled from 'styled-components';
import { palette } from 'styled-theme';

const BoxWrapper = styled.div`
  width: 100%;
  height: 100%;
  padding: 20px;
  background-color: #ffffff;
  border: 1px solid ${palette('border', 0)};
  margin: 0 17px 30px;

  &:last-child {
    margin-bottom: 0;
  }

  @media only screen and (max-width: 767px) {
    padding: 20px;
    margin: 0 10px 30px;
  }

  &.half {
    width: calc(50% - 34px);
    @media (max-width: 767px) {
      width: 100%;
    }
  }
`;

export { BoxWrapper };
