// dashboard/components/topten-widget-style.js

import styled from 'styled-components';
import { palette } from 'styled-theme';

const ToptenWidgetDiv = styled.div`
    margin-bottom: 20px;
    margin-top: -10px;

  .isoOpsSingle {
    padding: 20px 15px;
    background-color: #ffffff;
    border: 1px solid ${palette('border', 2)};
    display: flex;
    flex-direction: row;
    flex-wrap: nowrap;
    justify-content: center;
    align-content: stretch;
    align-items: center;
    overflow: visible;
  }
`;

const ToptenItemDiv = styled.div`
  background-color: #ffffff;
  border: 1px solid ${palette('border', 2)};
  width: 100%;
  z-index: 100;
  position: relative;
  top: 0;
  margin: -2px 0 0 0;
  box-shadow: 0px 0px 20px rgba(0,0,0,0);
  transition: all 0.3s ease-in-out;

  .ant-select-arrow {
    i {
      display: none;
    }
  }

  .toptenItemGroup {
    position: relative;
    transition: all 0.3s ease-in-out;
    overflow: hidden !important;
  }

  .toptenItemRow {
    display: flex;
    flex-direction: row;
    flex-wrap: nowrap;
    justify-content: flex-start;
    align-content: center;
    align-items: center;
    padding: 10px 15px;
    font-size: 12px;
    transition: all 0.3s ease-in-out;

    &:hover {
      transition: all 0.1s ease-in-out;
    }
  }

  .toptenItemName {
    flex: 0 0 auto;
    color: ${palette('text', 0)};
    font-weight: 600;
    padding-right: 20px;
    width: 30%;
    overflow: hidden;
      p {
        font-size: 13px;
        display: block;
      }
  }

  .toptenItemUsage {
    flex: 0 0 auto;
    font-weight: 400;
    font-size: 13px;
    color: ${palette('text', 5)};
    padding-right: 20px;
    width: 15%;

    .dot {
      width: 5px;
      height: 5px;
      border-radius: 5px;
      display: block;
      margin-top: 7px;
      margin-right: 5px;
      float: left;
    }

    &.critical {
      color: ${palette('error', 3)};
      .dot {
        background: ${palette('error', 3)};
      }
    }

    &.warning {
      color: ${palette('warning', 0)};
      .dot {
        background: ${palette('warning', 0)};
      }
    }

    &.success {
      color: ${palette('success', 1)};
      .dot {
        background: ${palette('success', 1)};
      }
    }
  }

  .toptenItemChart {
    flex: 1 1 auto;
    padding-right: 10px;
    .chartElement {
      width: 95%;
      height: 36px;
      background-size: 400px;
      background-repeat: repeat-x;
    }
  }

  .toptenItemAction i {
    font-size: 13px;
    color: ${palette('text', 5)};
    transform: rotate(0deg);
    transition: all 0.1s ease-in-out;
  }

  .add-info {
      display: flex;
      flex-direction: row;
      flex-wrap: nowrap;
      justify-content: flex-start;
      align-content: center;
      align-items: center;
      padding: 10px 15px;
      font-size: 12px;
      transition: all 0.3s ease-in-out;
  }

  &.active {
    margin: 0 -10px 0 -10px;
    padding: 10px 0;
    width: calc(100% + 20px);
    box-shadow: 0px 0px 5px rgba(0,0,0,0.1);
    overflow: visible;
    transition: all 0.3s ease-in-out;
    z-index: 1000;

    .toptenItemChart {
      color: ${palette('text', 1)};
      font-weight: 600;
    }

    .toptenItemAction i {
      transform: rotate(180deg);
      transition: all 0.1s ease-in-out;
    }

    .add-info {
      position: relative;
      transition: all 0.3s ease-in-out;
    }
  }

`;

export { ToptenWidgetDiv, ToptenItemDiv };
