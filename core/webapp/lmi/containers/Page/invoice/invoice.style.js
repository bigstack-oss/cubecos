import styled from 'styled-components';
import { palette } from 'styled-theme';
import WithDirection from '../../../config/withDirection';

// import bgImage from '../../image/sign.jpg';

const InvoicePageWrapper = styled.div`
  width: 100%;
  padding: 50px 35px;
  display: flex;
  flex-direction: column;

  @media only screen and (max-width: 767px) {
    padding: 30px 20px;
  }

  .isoLeftSideContent {
    display: flex;
    align-items: flex-start;
    flex-direction: column;
  }

  .isoRightSideContent {
    display: flex;
    align-items: flex-end;
    flex-direction: column;
    text-align: right;

    @media only screen and (max-width: 767px) {
      align-items: flex-start;
      margin-top: 15px;
    }
  }

  .isoTitle {
    font-size: 16px;
    font-weight: 500;
    color: ${palette('text', 0)};
    margin: 0 0 20px;
    line-height: 1;
  }

  .isoPageHeader {
    width: 100%;
    display: flex;
    flex-flow: row wrap;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 30px;

    .isoPageTitle {
      font-size: 24px;
      font-weight: 500;
      color: ${palette('secondary', 0)};
      margin: 0 20px 0 0;
      display: inline-flex;
      align-items: center;
    }
  }

  .isoPageContent {
    width: 100%;
    padding: 50px;
    background-color: #ffffff;
    border: 1px solid ${palette('border', 0)};

    @media only screen and (max-width: 767px) {
      padding: 30px 20px;
    }

    .isoOrderInfo {
      width: 100%;
      display: flex;
      flex-flow: row wrap;
      align-items: baseline;
      justify-content: space-between;
      padding-bottom: 30px;
      border-bottom: 1px dashed #ddd;

      .isoInvoiceNumber {
        font-size: 18px;
        font-weight: 400;
        color: ${palette('primary', 0)};
        margin: 0;
      }

      .isoRightSideContent {
        p {
          font-size: 14px;
          color: ${palette('text', 1)};
          margin: 0 0 5px;

          &:last-child {
            margin-bottom: 0;
          }
        }
      }
    }

    .isoBillingInformation {
      width: 100%;
      display: flex;
      flex-flow: row wrap;
      align-items: baseline;
      justify-content: space-between;
      margin-top: 50px;
      margin-bottom: 80px;

      .isoLeftSideContent,
      .isoRightSideContent {
        width: 50%;

        @media only screen and (max-width: 767px) {
          width: 100%;

          &.isoRightSideContent {
            margin-top: 30px;
            text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
          }
        }

        .isoTitle {
          margin-bottom: 25px;
        }

        .isoNameEmail {
          margin: 0 0 20px;

          .isoName {
            font-size: 15px;
            color: ${palette('text', 3)};
            font-weight: 400;
            display: block;
          }

          .isoEmail {
            font-size: 14px;
            color: ${palette('text', 3)};
            font-weight: 300;
          }
        }

        address {
          font-size: 14px;
          color: ${palette('text', 3)};
          font-weight: 300;
          font-style: normal;
        }
      }
    }

    .isoInvoiceTable {
      .isoSimpleTable .ant-table-thead > tr > th {
        color: ${palette('text', 0)};
        text-align: ${props => (props['data-rtl'] === 'rtl' ? 'left' : 'right')};

        &.itemName {
          text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
        }
      }

      .isoSimpleTable .ant-table-tbody > tr > td {
        font-size: 13px;
        color: ${palette('text', 2)};
        text-align: ${props => (props['data-rtl'] === 'rtl' ? 'left' : 'right')};

        &.itemName {
          text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
        }
      }

      .isoTotalBill {
        margin-top: 30px;
        display: flex;
        width: 100%;
        align-items: flex-end;
        text-align: right;
        flex-direction: column;
        padding-right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '15px')};
        padding-left: ${props => (props['data-rtl'] === 'rtl' ? '15px' : 'inherit')};

        p {
          font-size: 14px;
          color: ${palette('secondary', 2)};
          margin-bottom: 10px;
          width: 250px;
          display: flex;
          justify-content: flex-end;
          text-align: ${props => (props['data-rtl'] === 'rtl' ? 'left' : 'right')};

          span {
            width: 120px;
          }
        }

        h3 {
          font-size: 18px;
          color: ${palette('text', 0)};
          margin: 0;
          font-weight: 400;
          width: 250px;
          display: flex;
          justify-content: flex-end;
          text-align: ${props => (props['data-rtl'] === 'rtl' ? 'left' : 'right')};

          span {
            width: 120px;
          }
        }
      }
    }

    .isoButtonWrapper {
      width: 100%;
      display: flex;
      justify-content: flex-end;
      margin-top: 40px;

      button {
        margin-right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '5px')};
        margin-left: ${props => (props['data-rtl'] === 'rtl' ? '5px' : 'inherit')};

        &:last-child {
          margin-right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
          margin-left: ${props => (props['data-rtl'] === 'rtl' ? '0' : 'inherit')};
        }
      }
    }
  }
`;

export default WithDirection(InvoicePageWrapper);
