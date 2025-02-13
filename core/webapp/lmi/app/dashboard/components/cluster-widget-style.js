// dashboard/components/cluster-widget.js

import styled from 'styled-components';
import { palette } from 'styled-theme';

const ClusterWidgetDiv = styled.div`
  display: flex;
  flex-direction: row;
  flex-wrap: nowrap;
  justify-content: space-between;
  align-content: flex-start;
  align-items: stretch;

  &.up {
    .clusterSubText {
      span {
        color: ${palette('error', 3)};
      }
    }
  }

  &.down {
    .clusterSubText {
      span {
        color: ${palette('success', 1)};
      }
    }
  }

  .clusterWidget {
    padding: 15px 15px;
    background-color: #ffffff;
    border: 1px solid ${palette('border', 2)};
    flex: 1 1 auto;
    margin-left: -1px;
  }

  .clusterBlock {
    display: flex;
    flex-direction: row;
    flex-wrap: nowrap;
    justify-content: space-between;
    align-content: flex-start;
    align-items: flex-end;
  }

  .clusterTitle {
    display: flex;
    flex-direction: row;
    flex-wrap: nowrap;
    justify-content: space-between;
    align-content: flex-start;
    align-items: center;
    width: 100%;

    h2 {
      font-size: 12px;
      font-weight: 600;
      color: ${palette('text', 0)};
    }

    p {
      font-size: 26px;
      font-weight: 400;
      color: ${palette('text', 0)};
    }
  }

  .clusterChart {
    flex: 1 1 auto;
    padding-right: 10px;
    .chartElement {
      width: 100%;
      height: 92px;
      background-size: 400px;
      background-repeat: repeat-x;
    }
  }

  .clusterSubtitle {
    text-align: right;
    font-weight: 600;

    h5 {
      font-size: 12px;
      font-weight: 400;
      color: ${palette('text', 5)};
    }

    p {
      font-size: 12px;
      font-weight: 500;
      margin-bottom: 5px;
      color: ${palette('text', 1)};
      span {
        padding: 0 5px;
      }
    }
  }
`;

export { ClusterWidgetDiv };