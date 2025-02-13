// dashboard/components/infra-widget-style.js

import styled from 'styled-components';
import { palette } from 'styled-theme';

const InfraWidgetDiv = styled.div`
  .infraSingle {
    padding: 20px 15px;
    background-color: #ffffff;
    border: 1px solid ${palette('border', 2)};

    display: flex;
    flex-direction: column;
    flex-wrap: nowrap;
    justify-content: space-between;
    align-content: flex-start;
    align-items: stretch;
  }
`;

const InfraItemWidgetDiv = styled.div`
  margin-bottom: 15px;

  .infraItemTitle {
    display: flex;
    flex-direction: row;
    flex-wrap: nowrap;
    justify-content: space-between;
    align-content: flex-start;
    align-items: flex-start;

    p {
      font-size: 12px;
      font-weight: 600;
      color: ${palette('text', 0)};
    }

    h5 {
        flex: 0 1 auto;
      font-size: 20px;
      line-height: 1;
      color: ${palette('text', 0)};
      font-weight: 400;
      line-height: 22px;
      text-align: right;

      span {
        font-size: 13px;
        display: block;
        color: ${palette('text', 5)};
      }
    }
  }

  .infraItemBar {
    margin: 5px 0;

    .chartElement {
      width: 100%;
      height: 48px;
      background-size: 400px;
      background-repeat: repeat-x;
    }
  }

  .infraItemDetails {
    display: flex;
    flex-direction: row;
    flex-wrap: nowrap;
    justify-content: space-between;
    align-content: flex-start;
    align-items: stretch;

    .label {
        color: ${palette('text', 5)};
        position: relative;
        top: -1px;
        font-size: 13px;
        display: inline-block;
    }

    .dot {
      width: 5px;
      height: 5px;
      border-radius: 5px;
      display: block;
      margin-top: 7px;
      margin-right: 5px;
      float: left;
    }

    .running {
      .dot {
        background: ${palette('vmchart', 0)};
      }
    }

    .stopped {
      .dot {
        background: ${palette('vmchart', 1)};
      }
    }

    .suspended {
      .dot {
        background: ${palette('vmchart', 2)};
      }
    }

    .paused {
      .dot {
        background: ${palette('vmchart', 3)};
      }
    }

    .error {
      .dot {
        background: ${palette('vmchart', 4)};
      }
    }

    .control {
      .dot {
        background: ${palette('rolechart', 0)};
      }
    }

    .network {
      .dot {
        background: ${palette('rolechart', 1)};
      }
    }

    .compute {
      .dot {
        background: ${palette('rolechart', 2)};
      }
    }

    .storage {
      .dot {
        background: ${palette('rolechart', 3)};
      }
    }

    .controlNetwork {
      .dot {
        background: ${palette('rolechart', 4)};
      }
    }

    .controlConverged {
      .dot {
        background: ${palette('rolechart', 5)};
      }
    }
  }

`;

export { InfraWidgetDiv, InfraItemWidgetDiv };