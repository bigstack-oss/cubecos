import Table from '../../../components/uielements/table';
import styled from 'styled-components';
import { palette } from 'styled-theme';
import {
  transition,
  boxShadow,
  borderRadius,
} from '../../../config/style-util';
import WithDirection from '../../../config/withDirection';

const TableWrapper = styled(Table)`
  overflow: hidden;
  overflow-x: auto;
  background-color: #ffffff;

  .ant-table-thead > tr > th {
    color: ${palette('secondary', 2)};
    font-size: 13px;
    background-color: ${palette('secondary', 1)};
    border-bottom: 0;

    &.ant-table-column-sort {
      background: ${palette('secondary', 1)};
      margin: ${props =>
        props['data-rtl'] === 'rtl' ? '0 4px 0 0' : '0 0 0 4px'};
    }
  }

  .ant-table-thead > tr > th,
  .ant-table-tbody > tr > td {
    padding: 16px 15px;
    white-space: nowrap;
    text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
  }

  .ant-table-tbody > tr > td {
    font-size: 12px;
    color: ${palette('text', 3)};
    border-bottom: 1px solid ${palette('border', 0)};

    a {
      color: ${palette('primary', 0)};
      ${transition()};

      &:hover {
        color: ${palette('primary', 4)};
      }
    }
  }

  .ant-table-thead > tr.ant-table-row-hover > td,
  .ant-table-tbody > tr.ant-table-row-hover > td,
  .ant-table-thead > tr:hover > td,
  .ant-table-tbody > tr:hover > td {
    background-color: transparent;
  }

  .ant-table-bordered .ant-table-thead > tr > th {
    border-bottom: 1px solid ${palette('border', 0)};
  }

  .ant-table-bordered .ant-table-thead > tr > th,
  .ant-table-bordered .ant-table-tbody > tr > td {
    border-right: 1px solid ${palette('border', 0)};
  }

  .ant-table-pagination {
    float: ${props => (props['data-rtl'] === 'rtl' ? 'left' : 'right')};
  }

  .ant-pagination-prev,
  .ant-pagination-next {
    border: 1px solid ${palette('border', 0)};
  }

  .ant-pagination-disabled,
  .ant-pagination-prev.ant-pagination-disabled,
  .ant-pagination-next.ant-pagination-disabled {
    border: 1px solid ${palette('border', 0)};

    a {
      border: 0;
    }
  }

  .ant-pagination-prev,
  .ant-pagination-next,
  .ant-pagination-jump-prev,
  .ant-pagination-jump-next {
    transform: ${props =>
      props['data-rtl'] === 'rtl' ? 'rotate(180deg)' : 'rotate(0)'};
  }

  .ant-pagination-prev,
  .ant-pagination-jump-prev,
  .ant-pagination-jump-next {
    margin: ${props =>
      props['data-rtl'] === 'rtl' ? '0 0 0 8px' : '0 8px 0 0'};
  }

  .ant-pagination-item {
    margin: ${props =>
      props['data-rtl'] === 'rtl' ? '0 0 0 8px' : '0 8px 0 0'};
  }

  .ant-pagination-item-active {
    background-color: ${palette('primary', 0)};
    border-color: ${palette('primary', 0)};
  }

  .ant-table-expanded-row {
    background: ${palette('grayscale', 6)};

    p {
      color: ${palette('text', 3)};
    }
  }

  .ant-spin-nested-loading > div > .ant-spin {
    max-height: none;

    .ant-spin-dot i {
      color: ${palette('primary', 0)};
    }
  }

  .ant-table-header {
    background-color: transparent;
  }

  .ant-table-title {
    background: ${palette('secondary', 1)};
    color: ${palette('secondary', 2)};
    font-size: 13px;
    font-weight: 500;
    padding: 16px 30px;
    ${borderRadius()};
  }

  .ant-table-footer {
    background: ${palette('secondary', 1)};
    color: ${palette('secondary', 2)};
    font-size: 12px;
    font-weight: 400;
    padding: 16px 30px;
    ${borderRadius()};
  }

  .ant-table-content {
    overflow-x: auto;
  }

  .ant-table-column-sorter-up.on .anticon-caret-up,
  .ant-table-column-sorter-down.on .anticon-caret-up,
  .ant-table-column-sorter-up.on .anticon-caret-down,
  .ant-table-column-sorter-down.on .anticon-caret-down {
    color: ${palette('primary', 0)};
  }

  &.isoSearchableTable {
    .isoTableSearchBox {
      padding: 20px;
      display: flex;
      background: #ffffff;
      border: 1px solid ${palette('border', 0)};
      ${boxShadow('0 1px 6px rgba(0,0,0,0.2)')};

      input {
        font-size: 14px;
        font-weight: 400;
        color: ${palette('text', 3)};
        line-height: inherit;
        height: 36px;
        width: 100%;
        padding: 0 15px;
        margin: 0;
        border: 1px solid ${palette('secondary', 7)};
        outline: 0 !important;
        overflow: hidden;
        background-color: #ffffff;
        ${borderRadius('3px 0 0 3px')};
        ${transition()};
        ${boxShadow('none')};

        &:focus,
        &:hover {
          border-color: ${palette('secondary', 7)};
          ${boxShadow('none')};
        }

        &::-webkit-input-placeholder {
          color: ${palette('grayscale', 0)};
        }

        &:-moz-placeholder {
          color: ${palette('grayscale', 0)};
        }

        &::-moz-placeholder {
          color: ${palette('grayscale', 0)};
        }
        &:-ms-input-placeholder {
          color: ${palette('grayscale', 0)};
        }
      }

      button {
        font-size: 12px;
        font-weight: 400;
        padding: 0;
        text-transform: uppercase;
        color: #ffffff;
        background-color: ${palette('primary', 0)};
        border: 0;
        outline: 0;
        height: 36px;
        padding: 0 15px;
        margin-left: -1px;
        cursor: pointer;
        border-radius: ${props =>
          props['data-rtl'] === 'rtl' ? '3px 0 0 3px' : '0 3px 3px 0'};
        ${transition()};

        &:hover {
          background-color: ${palette('primary', 1)};
        }
      }
    }

    .ant-table-thead > tr > th {
      word-break: keep-all;

      span {
        display: flex;
        justify-content: flex-start;
        align-items: center;

        i {
          margin: ${props =>
            props['data-rtl'] === 'rtl' ? '0 0 0 10px' : '0 10px 0 0'};
          order: -1;
        }
      }
    }
  }

  &.isoGroupTable {
    .ant-table-thead > tr {
      th {
        border: 1px solid ${palette('border', 0)};
        border-left: 0;

        &[rowspan] {
          text-align: center;
        }

        &.isoImageCell {
          padding: 3px;
        }
      }

      &:first-child {
        th {
          &:first-child {
            border-left: ${props => (props['data-rtl'] === 'rtl' ? '0' : '1px')}
              solid ${palette('border', 0)};
          }
        }
      }

      &:last-child {
        th {
          border-top: 0;
        }
      }
    }

    .ant-table-tbody {
      .ant-table-row {
        td {
          border-right: 1px solid ${palette('border', 0)};

          &:first-child {
            border-left: ${props => (props['data-rtl'] === 'rtl' ? '0' : '1px')}
              solid ${palette('border', 0)};
          }

          &:last-child {
            border-left: ${props => (props['data-rtl'] === 'rtl' ? '1px' : '0')}
              solid ${palette('border', 0)};
          }

          &.isoImageCell {
            padding: 3px;
          }
        }
      }
    }
  }

  &.isoEditableTable {
    .isoEditData {
      .isoEditDataWrapper {
        display: flex;
        align-items: center;

        input {
          font-size: 12px;
          font-weight: 400;
          color: ${palette('text', 3)};
          line-height: inherit;
          padding: 7px 10px;
          margin: ${props =>
            props['data-rtl'] === 'rtl' ? '0 0 0 10px' : '0 10px 0 0'};
          border: 1px solid ${palette('border', 0)};
          outline: 0 !important;
          overflow: hidden;
          background-color: #ffffff;
          ${borderRadius('3px')};
          ${boxShadow()};
          ${transition()};

          &:focus,
          &:hover {
            border-color: ${palette('border', 0)};
            ${boxShadow()};
          }

          &::-webkit-input-placeholder {
            color: ${palette('grayscale', 0)};
          }

          &:-moz-placeholder {
            color: ${palette('grayscale', 0)};
          }

          &::-moz-placeholder {
            color: ${palette('grayscale', 0)};
          }
          &:-ms-input-placeholder {
            color: ${palette('grayscale', 0)};
          }
        }

        .isoEditIcon {
          cursor: pointer;
        }
      }

      .isoDataWrapper {
        display: flex;
        align-items: center;

        .isoEditIcon {
          margin: ${props =>
            props['data-rtl'] === 'rtl' ? '0 auto 0 0' : '0 0 0 auto'};
          cursor: pointer;
          flex-shrink: 0;
        }
      }
    }
  }
`;

const WDCustomizedTableWrapper = styled.div`
  .isoCustomizedTableControlBar {
    margin-bottom: 40px;

    .ant-form-item {
      margin: ${props =>
        props['data-rtl'] === 'rtl' ? '0 0 0 16px' : '0 16px 0 0'};
    }

    .ant-form-item-label {
      label {
        color: ${palette('secondary', 2)};

        &:after {
          margin: ${props =>
            props['data-rtl'] === 'rtl' ? '0 2px 0 8px' : '0 8px 0 2px'};
        }
      }
    }

    .ant-switch-checked {
      border-color: ${palette('primary', 0)};
      background-color: ${palette('primary', 0)};
    }
  }
`;

const CustomizedTableWrapper = WithDirection(WDCustomizedTableWrapper);

export { CustomizedTableWrapper };
export default WithDirection(TableWrapper);
