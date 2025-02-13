import styled from 'styled-components';
import { palette } from 'styled-theme';
import {
  transition,
  borderRadius,
  boxShadow,
} from '../../../config/style-util';
import WithDirection from '../../../config/withDirection';

const ProductsTable = styled.div`
  width: 100%;
  background-color: #ffffff;
  margin: 0 15px;

  @media only screen and (max-width: 767px) {
    overflow-x: auto;
    margin: 0;
  }

  &.bordered {
    table {
      tbody {
        tr {
          border-bottom: 1px solid ${palette('border', 0)};

          &:last-child {
            border-bottom: 0;
          }

          &.isoTotalBill {
            border-top: 0;
          }
        }
      }
    }
  }

  table {
    width: 100%;
    display: flex;
    flex-direction: column;
    border: 1px solid ${palette('border', 0)};

    @media only screen and (max-width: 767px) {
      width: 767px;
      overflow: hidden;
    }

    /* TABLE HEAD */
    thead {
      width: 100%;
      min-height: 50px;
      border-bottom: 1px solid ${palette('border', 0)};

      tr {
        width: 100%;
        display: flex;
        align-items: center;
        justify-content: flex-start;

        th {
          font-size: 14px;
          font-weight: 500;
          color: ${palette('text', 0)};
          line-height: 1.2;
          white-space: nowrap;
          padding: 15px 0;
          margin: 0 20px;
          width: 15%;
          text-align: center;

          &:last-child {
            margin-right: 0;
          }

          @media only screen and (max-width: 991px) {
            margin: 0 10px;
            flex-shrink: 0;
          }

          &.isoItemRemove {
            width: 50px;
            margin: 0;
            flex-shrink: 0;
            margin-left: 15px;

            @media only screen and (max-width: 991px) {
              width: 30px;
              margin-left: 10px;
            }
          }

          &.isoItemImage {
            width: 80px;
            flex-shrink: 0;

            @media only screen and (max-width: 991px) {
              width: 60px;
            }
          }

          &.isoItemName {
            max-width: none;
            text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
            width: 45%;

            @media only screen and (max-width: 991px) {
              margin: 0 10px;
              flex-shrink: 1;
            }
          }
        }
      }
    }

    /* TABLE BODY */
    tbody {
      width: 100%;

      tr {
        width: 100%;
        display: flex;
        align-items: center;
        justify-content: flex-start;
        min-height: 140px;
        .isoTransition;

        &.isoNoItemMsg {
          min-height: 300px;
          justify-content: center;
          font-size: 30px;
          font-weight: 300;
          color: ${palette('grayscale', 1)};
          line-height: 1.2;
        }

        td {
          font-size: 14px;
          font-weight: 500;
          color: ${palette('text', 0)};
          line-height: 1.2;
          overflow: hidden;
          padding: 15px 0;
          margin: 0 20px;
          width: 15%;
          text-align: center;

          &:last-child {
            margin-right: 0;
          }

          @media only screen and (max-width: 991px) {
            margin: 0 10px;
            flex-shrink: 0;
          }

          h3 {
            font-size: 14px;
            font-weight: 500;
            color: ${palette('text', 0)};
            line-height: 1.2;
            margin-bottom: 10px;
          }

          p {
            font-size: 12px;
            font-weight: 400;
            color: ${palette('text', 2)};
            line-height: 1.5;
          }

          span {
            font-size: 14px;
            font-weight: 500;
            color: ${palette('text', 0)};
          }

          &.isoItemRemove {
            text-align: center;
            width: 50px;
            margin: 0;
            flex-shrink: 0;
            margin-left: 15px;

            a {
              color: ${palette('text', 0)};
              ${transition()};

              &:hover {
                color: ${palette('primary', 0)};
              }
            }

            @media only screen and (max-width: 991px) {
              width: 30px;
              margin-left: 10px;
            }
          }

          &.isoItemImage {
            width: 80px;
            flex-shrink: 0;
            display: flex;
            align-items: center;
            justify-content: center;

            img {
              width: 100%;
              height: 100%;
              object-fit: cover;
            }

            @media only screen and (max-width: 991px) {
              width: 60px;
            }
          }

          &.isoItemName {
            text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
            max-width: none;
            width: 45%;

            @media only screen and (max-width: 991px) {
              margin: 0 10px;
              flex-shrink: 1;
            }
          }

          .ant-input-number {
            background-color: transparent;

            &.ant-input-number-focused {
              .isoBoxShadow(none);
              ${boxShadow()};
            }

            .ant-input-number-handler-wrap {
              background-color: transparent;
            }

            .ant-input-number-input {
              background-color: transparent;
            }
          }
        }

        &.isoTotalBill {
          border-top: 1px solid ${palette('border', 0)};
          padding-top: 10px;
          min-height: 100px;

          &:hover {
            background-color: #fff;
          }
        }
      }
    }

    /* TABLE FOOTER */
    tfoot {
      width: 100%;
      padding: 25px;
      padding-top: 10px;

      tr {
        width: 100%;
        display: flex;
        align-items: center;

        &.isoTotalBill {
          justify-content: flex-end;

          td {
            width: 15%;
          }
        }

        td {
          .ant-input {
            ${borderRadius('2px')};
          }

          .ant-btn {
            height: 42px;
            min-width: 125px;
            ${borderRadius('2px')};
          }
        }
      }
    }
  }
`;

export default WithDirection(ProductsTable);
