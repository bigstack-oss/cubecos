// dashboard/components/operation-widget-style.js

import styled from 'styled-components';
import { palette } from 'styled-theme';

const OperationsWidgetDiv = styled.div`
  .opsItem {
    padding: 20px 15px;
    background-color: #ffffff;
    border: 1px solid ${palette('border', 2)};

    /* display: flex;
    flex-direction: row;
    flex-wrap: nowrap;
    justify-content: center;
    align-content: stretch;
    align-items: center; */
  }
`;

const OperationsItemDiv = styled.div`
  display: flex;
  flex-direction: column;
  flex-wrap: nowrap;
  justify-content: center;
  align-content: stretch;
  align-items: stretch;

  .opsItemTitle {
    text-align: left;
    width: 100%;
    padding: 0 0px;

    h2 {
      font-size: 12px;
      font-weight: 600;
      color: ${palette('text', 0)};
    }
  }

  .opsItemPie {
    position: center;
    text-align: center;
    padding: 15px 0;
    overflow: hidden;

    .piePercent {
      font-size: 22px;
      line-height: 1;
    }

    .pieTotal {
      color: ${palette('text', 5)};
    }
  }

  .opsItemDetails {
    display: flex;
    flex-direction: row;
    flex-wrap: nowrap;
    justify-content: space-between;
    align-content: flex-start;
    align-items: center;
    padding: 0;
    margin: 0 auto;
    width: 100%;
    max-width: 150px;

    h4 {
      flex: 0 1 auto;
      font-weight: 500;

      &:nth-child(even) {
          text-align: right;
      }
    }

    span {
      display: block;
      font-weight: 400;
      color: ${palette('text', 5)};
    }
  }

    .recharts-wrapper {
        margin: 0 auto;
        position: absolute;
        top: 0;
        left: 50%;
        transform: translateX(-50%);
    }

`;

export { OperationsWidgetDiv, OperationsItemDiv };