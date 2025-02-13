import styled from 'styled-components';
import { palette } from 'styled-theme';
import WithDirection from '../../config/withDirection';

const ChartWrapper = styled.div`
  display: flex;
  flex-direction: column;
  align-items: center;

  .isoChartControl {
    display: flex;
    align-items: center;
    margin-left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : 'auto')};
    margin-right: ${props =>
      props['data-rtl'] === 'rtl' ? 'auto' : 'inherit'};
    margin-bottom: 20px;

    span {
      font-size: 13px;
      color: ${palette('text', 1)};
      font-weight: 400;
      margin-right: ${props =>
        props['data-rtl'] === 'rtl' ? 'inherit' : '15px'};
      margin-left: ${props =>
        props['data-rtl'] === 'rtl' ? '15px' : 'inherit'};
    }

    button {
      border: 1px solid ${palette('border', 0)};
      padding: 0 10px;
      border-radius: 0;
      position: relative;

      span {
        margin: 0;
      }

      &:last-child {
        margin-left: ${props =>
          props['data-rtl'] === 'rtl' ? 'inherit' : '-1px'};
        margin-right: ${props =>
          props['data-rtl'] === 'rtl' ? '-1px' : 'inherit'};
      }

      &:hover {
        color: ${palette('primary', 0)};
        border-color: ${palette('primary', 0)};
        z-index: 1;

        span {
          color: ${palette('primary', 0)};
        }
      }
    }
  }
`;

export default WithDirection(ChartWrapper);
