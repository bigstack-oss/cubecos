// dashboard/components/system-widget.js

import styled from 'styled-components';
import { palette } from 'styled-theme';

const SystemPartitionDiv = styled.div`
  width: 100%;
  display: flex;
  flex-direction: row;
  flex-wrap: nowrap;
  justify-content: center;
  align-content: stretch;
  align-items: center;
  padding: 20px 15px;
  background-color: #ffffff;
  border: 1px solid ${palette('border', 2)};

  &:last-child {
      margin-top: -1px;
      margin-bottom: 15px;
  }

  .partitionImage {
    margin-right: 15px;
  }

  .partitionTitle {
    flex: 1 1 auto;

    h3 {
      font-size: 18px;
      color: ${palette('text', 0)};
      font-weight: 400;
      line-height: 1.2;
      margin: 0;
      flex: 1 1 auto;
    }

    p {
      font-size: 12px;
      font-weight: 600;
    }
  }

  .partitionDetails {
    flex: 1 1 auto;
    text-align: right;
    margin-right: 15px;

    span {
      color: ${palette('text', 5)};
      display: block;
      font-size: 12px;
      font-weight: 400;
    }

    span + span {
        color: ${palette('text', 1)};
        font-weight: 500;
    }
  }

  .partitionStateIcon {
    span {
      border: 1px solid ${palette('text', 5)};
      border-radius: 20px;
      width: 24px;
      height: 24px;
      display: block;
      text-align: center;
      line-height: 24px;
    }
  }
`;

const SystemWidgetDiv = styled.div`

  .inactive {
    .partitionImage {
      opacity: 0.5;
    }
  }

  .active {
    .partitionState {
      color: ${palette('primary', 0)};
    }

    .partitionStateIcon {
      span {
        background-color: ${palette('primary', 0)};
        border: 1px solid ${palette('primary', 0)};
        color: #fff;
      }
    }
  }

  .partitionState {
    text-transform: capitalize;
  }

  .partitionLabel {
    font-size: 21px;
    color: ${palette('text', 0)};
    font-weight: 400;
    line-height: 1.2;
    margin: 0 0 25px;
  }
`;

export { SystemPartitionDiv, SystemWidgetDiv };
