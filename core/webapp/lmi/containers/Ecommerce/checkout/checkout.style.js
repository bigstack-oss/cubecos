import styled from 'styled-components';
import { palette } from 'styled-theme';
import { borderRadius } from '../../../config/style-util';
import WithDirection from '../../../config/withDirection';

const WDCheckoutContents = styled.div`
  .isoCheckoutPage {
    padding: 50px 18px;

    .isoSectionTitle {
      font-size: 16px;
      font-weight: 500;
      color: ${palette('text', 0)};
      line-height: 1.2;
      padding: ${props =>
        props['data-rtl'] === 'rtl' ? '0 30px 0 0' : '0 0 0 30px'};
      margin: 20px 0 35px;
    }

    .isoLoginSection {
      width: 100%;
    }

    .isoSectionSeperator {
      margin: 40px 0;
      width: 100%;
      display: flex;
      align-items: center;
      position: relative;

      &:before,
      &:after {
        content: '';
        width: 100%;
        height: 1px;
        display: flex;
        background-color: ${palette('grayscale', 4)};
      }

      span {
        font-size: 14px;
        font-weight: 500;
        color: ${palette('text', 0)};
        line-height: 1.2;
        padding: 0 15px;
      }
    }

    .isoBillingAddressWrapper {
      width: 100%;

      .isoBillingSection {
        display: flex;

        @media only screen and (max-width: 767px) {
          flex-direction: column;
        }
      }
    }
  }
`;

const WDBillingFormWrapper = styled.div`
  width: 60%;
  padding: ${props =>
    props['data-rtl'] === 'rtl' ? '0 30px 0 20px' : '0 20px 0 30px'};
  display: flex;
  flex-direction: column;

  @media only screen and (max-width: 767px) {
    width: 100%;
    padding: 0;
    margin-bottom: 50px;
  }

  .isoInputFieldset {
    width: 100%;
    display: flex;
    margin-bottom: 35px;

    &.vertical {
      flex-direction: column;
    }

    .isoInputBox {
      width: 100%;
      display: flex;
      flex-direction: column;
      margin: ${props =>
        props['data-rtl'] === 'rtl' ? '0 0 0 35px' : '0 35px 0 0'};

      &:last-child {
        margin: 0;
      }

      .ant-select {
        .ant-select-selection {
          &.ant-select-selection--single {
            height: 42px;
            ${borderRadius()};
          }

          .ant-select-selection__rendered {
            line-height: 42px;
            font-size: 13px;
          }
        }
      }
    }

    input {
      ${borderRadius()};
    }
  }

  .ant-checkbox-wrapper {
    span {
      font-size: 13px;
      font-weight: 500;
      color: ${palette('text', 0)};
      line-height: 1.2;
    }
  }
`;

const WDInputBoxWrapper = styled.div`
  &.isoInputBox {
    width: 100%;
    display: flex;
    flex-direction: column;
    margin-right: 35px;

    &:last-child {
      margin-right: 0;
    }

    label {
      font-size: 14px;
      font-weight: 500;
      color: ${palette('text', 0)};
      line-height: 1.2;
      margin-bottom: 17px;
      display: flex;
      position: relative;

      .asterisk {
        font-size: 15px;
        font-weight: 400;
        color: ${palette('color', 0)};
        line-height: 1.2;
        margin: ${props =>
          props['data-rtl'] === 'rtl' ? '0 3px 0 0' : '0 0 0 3px'};
      }
    }

    input {
      ${borderRadius()};
    }
  }
`;

const WDOrderTable = styled.div`
  width: 40%;
  padding: ${props =>
    props['data-rtl'] === 'rtl' ? '0 20px 0 30px' : '0 30px 0 20px'};

  @media only screen and (max-width: 767px) {
    width: 100%;
    padding: 0;
  }

  .isoOrderTable {
    width: 100%;
    display: flex;
    flex-direction: column;

    .isoOrderTableHead {
      width: 100%;
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 20px;

      .tableHead {
        font-size: 15px;
        font-weight: 500;
        color: ${palette('text', 0)};
        line-height: 1.2;
      }
    }

    .isoOrderTableBody {
      width: 100%;
      display: flex;
      flex-direction: column;
      margin-bottom: 10px;

      .isoSingleOrderInfo {
        width: 100%;
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 10px 0;
        border-bottom: 1px solid ${palette('border', 0)};

        &:last-child {
          border-bottom: 0;
        }

        p {
          padding-right: ${props =>
            props['data-rtl'] === 'rtl' ? '0 0 0 35px' : '0 35px 0 0'};
          span {
            font-size: 13px;
            font-weight: 400;
            color: ${palette('text', 2)};
            line-height: 1.5;
            padding: 0 3px;
            display: inline-block;

            &.isoQuantity {
              font-size: 13px;
              font-weight: 400;
              color: ${palette('text', 1)};
              line-height: 1.5;
              display: inline-block;
            }
          }
        }

        .totalPrice {
          font-size: 13px;
          font-weight: 500;
          color: ${palette('text', 2)};
          line-height: 1.5;
        }
      }
    }

    .isoOrderTableFooter {
      width: 100%;
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 40px;

      span {
        font-size: 14px;
        font-weight: 500;
        color: ${palette('text', 0)};
        line-height: 1.2;
      }
    }

    button {
      height: 42px;
      ${borderRadius('2px')};
    }
  }
`;

const CheckoutContents = WithDirection(WDCheckoutContents);
const BillingFormWrapper = WithDirection(WDBillingFormWrapper);
const OrderTable = WithDirection(WDOrderTable);
const InputBoxWrapper = WithDirection(WDInputBoxWrapper);

export { CheckoutContents, BillingFormWrapper, OrderTable, InputBoxWrapper };
