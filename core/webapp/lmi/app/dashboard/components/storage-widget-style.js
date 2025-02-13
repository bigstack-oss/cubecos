// dashboard/components/storage-widget-style.js

import styled from 'styled-components';
import { palette } from 'styled-theme';

const StorageTabDiv = styled.div`
  display: flex;
  flex-direction: row;
  flex-wrap: nowrap;
  justify-content: space-between;
  align-content: flex-start;
  align-items: stretch;

  .storageTab {
    padding: 20px 15px 35px 15px;
    flex: 0 1 auto;
    color: #fff;
    display: flex;
    flex-direction: column;
    flex-wrap: nowrap;
    justify-content: space-between;
    align-content: flex-start;
    align-items: stretch;
    min-width: 82   px;

    &.red {
      background: ${palette('error', 3)};
    }

    &.green {
      background: ${palette('success', 1)};
    }

    &.blue {
      background: ${palette('primary', 14)};
    }

    p {
        text-align: left;
        font-size: 12px;
        font-weight: 500;
        margin-top: 5px;
        span {
            padding-right: 5px;
            opacity: 0.6;
        }
    }
  }

  .storageWidget {
    padding: 20px 15px;
    background-color: #ffffff;
    border: 1px solid ${palette('border', 2)};
    flex: 1 1 auto;

    h2 {
      font-size: 12px;
      font-weight: 600;
      color: ${palette('text', 0)};
    }
  }

  .storageTrend {
    width: 100%;
    text-align: right;
    font-size: 11px;
    font-weight: 600;
  }

  .storageTabIcon {
    font-size: 32px;
    text-align: center;
    width: 100%;
    flex: 1 1 auto;
  }
`;

const StorageItemDiv = styled.div`
  display: flex;
  flex-direction: row;
  flex-wrap: nowrap;
  justify-content: space-between;
  align-content: flex-start;
  align-items: center;

  .storageItemTotal {
      text-align: right;
      padding: 10px 0;

      h2 {
        font-size: 22px;
        font-weight: 400;
        line-height: 1;
        padding-top: 3px;
      }

      p {
        font-size: 12px;
        color: ${palette('text', 5)};
      }

      h2 + p {
          font-size: 12px;
          font-weight: 500;
          color: ${palette('text', 1)};
      }
  }

  .storageItemChart {
    flex: 1 1 auto;
    padding-right: 10px;

    .chartElement {
      width: 100%;
      height: 50px;
      background-size: 400px;
      background-repeat: repeat-x;
    }
  }
`;

export { StorageTabDiv, StorageItemDiv };
