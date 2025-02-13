import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition, borderRadius, boxShadow } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const WDTodoWrapper = styled.div`
  padding: 50px 35px;

  @media only screen and (max-width: 767px) {
    padding: 30px 20px;
  }
  @media only screen and (min-width: 767px) and (max-width: 990px) {
    padding: 40px 20px;
  }

  .isoTodoHeader {
    height: auto;
    line-height: inherit;
    padding: 0;
    margin-bottom: 40px;
    background: none;

    @media only screen and (max-width: 767px) {
      margin-bottom: 20px;
    }

    .isoTodoInput {
      font-size: 14px;
      font-weight: 400;
      color: ${palette('text', 2)};
      line-height: inherit;
      height: 50px;
      padding: 0 15px;
      margin: 0;
      border: 1px solid ${palette('border', 0)};
      outline: 0 !important;
      overflow: hidden;
      background-color: #ffffff;
      ${boxShadow('none')};
      ${borderRadius('3px')};
      ${transition()};

      &:focus {
        border-color: ${palette('primary', 0)};
        ${boxShadow('0 0 0 2px rgba(68, 130, 255, 0.2)')};
        outline: 0;
      }

      &:hover {
        border-color: ${palette('primary', 0)};
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
  }

  .isoTodoContentBody {
    width: 100%;
  }
`;

const WDTodoListWrapper = styled.div`
  width: 100%;
  display: flex;
  flex-direction: column;

  .isoTodoStatusTab {
    margin-bottom: 20px;
    display: flex;

    .isoTodoStatus {
      margin-left: ${props =>
        props['data-rtl'] === 'rtl' ? 'inherit' : 'auto'};
      margin-right: ${props =>
        props['data-rtl'] === 'rtl' ? 'auto' : 'inherit'};

      .ant-radio-button-wrapper {
        margin: 0;
        height: auto;
        line-height: 1.5;
        color: rgba(0, 0, 0, 0.65);
        display: inline-block;
        transition: all 0.3s ease;
        cursor: pointer;
        border: 0;
        background: transparent;
        padding: 0 15px;
        ${boxShadow('none')};

        &:last-child {
          padding-right: ${props =>
            props['data-rtl'] === 'rtl' ? '15px' : '0'};
          padding-left: ${props =>
            props['data-rtl'] === 'rtl' ? '0' : '15px'};
        }

        &:first-child {
          padding-left: ${props =>
            props['data-rtl'] === 'rtl' ? '15px' : '0'};
          padding-right: ${props =>
            props['data-rtl'] === 'rtl' ? '0' : '15px'};
        }

        &:not(:first-child)::before {
          left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '-1px')};
          right: ${props => (props['data-rtl'] === 'rtl' ? '-1px' : 'inherit')};
        }

        span {
          font-size: 14px;
          font-weight: 400;
          color: ${palette('text', 3)};
        }
      }

      .ant-radio-button-wrapper-checked {
        span {
          color: ${palette('primary', 0)};
        }
      }
    }
  }

  .isoTodoListWrapper {
    width: 100%;
    display: flex;
    flex-direction: column;

    .isoTodoList {
      width: 100%;
      padding: ${props =>
        props['data-rtl'] === 'rtl' ? '20px 0 20px 15px' : '20px 15px 20px 0'};
      overflow: hidden;
      margin: 0 0 15px;
      background: #ffffff;
      border: 1px solid ${palette('border', 0)};
      display: flex;
      align-items: flex-start;
      text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
      position: relative;

      .isoColorChooser {
        width: 5px;
        height: 100%;
        padding: 0;
        border: 0;
        outline: 0;
        flex-shrink: 0;
        margin-right: ${props =>
          props['data-rtl'] === 'rtl' ? 'inherit' : '10px'};
        margin-left: ${props =>
          props['data-rtl'] === 'rtl' ? '10px' : 'inherit'};
        position: absolute;
        top: 0;
        left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
        right: ${props => (props['data-rtl'] === 'rtl' ? '0' : 'inherit')};
        ${borderRadius(0)};
        ${transition(0.25)};
      }

      .ant-checkbox-wrapper {
        line-height: 1;
        margin-right: ${props =>
          props['data-rtl'] === 'rtl' ? '25px' : '15px'};
        margin-left: ${props =>
          props['data-rtl'] === 'rtl' ? '15px' : '25px'};

        .ant-checkbox-inner {
          width: 15px;
          height: 15px;
        }
      }

      .isoTodoContentWrapper {
        width: 100%;
        padding: ${props =>
          props['data-rtl'] === 'rtl' ? '0 0 0 30px' : '0 30px 0 0'};
        position: relative;

        .isoTodoDate {
          font-size: 12px;
          font-weight: 400;
          color: ${palette('grayscale', 0)};
          line-height: inherit;
          display: flex;
          margin-bottom: 10px;
          text-transform: capitalize;
        }

        .isoNoteContent {
          width: 100%;
          display: flex;

          .isoNoteTextWrapper {
            font-size: 14px;
            font-weight: 400;
            color: ${palette('text', 4)};
            line-height: 24px;
          }

          .isoNoteEditWrapper {
            width: 100%;
            display: flex;

            textarea {
              font-size: 14px;
              font-weight: 400;
              color: ${palette('text', 4)};
              line-height: 24px;
              height: 210px;
              padding: 10px 15px;
              margin: 0;
              border: 0;
              outline: 0 !important;
              background-color: #ffffff;
              ${boxShadow('none')};
              ${borderRadius('3px')};
              box-sizing: content-box;
              resize: vertical;
              ${transition()};

              &:focus {
                border: 1px solid ${palette('primary', 0)};
                outline: 0;
                ${boxShadow('0 0 0 2px rgba(68, 130, 255, 0.2)')};
              }

              &:hover {
                border-color: ${palette('primary', 0)};
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
          }
        }
      }

      .isoTodoDelete,
      .isoNoteEditIcon {
        font-size: 16px;
        color: ${palette('secondary', 0)};
        width: 30px;
        height: 30px;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        background-color: #ffffff;
        outline: 0;
        padding: 0;
        border: 1px solid ${palette('border', 0)};
        margin-left: ${props =>
          props['data-rtl'] === 'rtl' ? 'inherit' : '-1px'};
        margin-right: ${props =>
          props['data-rtl'] === 'rtl' ? '-1px' : 'inherit'};
        cursor: pointer;
        ${transition()};
        ${borderRadius()};

        &:first-child {
          margin-left: ${props =>
            props['data-rtl'] === 'rtl' ? 'inherit' : '0'};
          margin-right: ${props =>
            props['data-rtl'] === 'rtl' ? '0' : 'inherit'};
        }

        &:hover {
          color: ${palette('primary', 0)};
          background-color: ${palette('grayscale', 7)};
        }
      }

      .isoNoteEditIcon {
        position: absolute;
        top: 0;
        right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
        left: ${props => (props['data-rtl'] === 'rtl' ? '0' : 'inherit')};
      }
    }

    .isoNoTodoFound {
      font-size: 21px;
      font-weight: 300;
      padding: 0;
      text-transform: uppercase;
      color: ${palette('text', 3)};
      width: 100%;
      text-align: center;
      margin: 50px 0;
    }
  }

  .isoTodoFooter {
    margin-top: 5px;
    display: flex;
    justify-content: flex-end;
    align-items: center;

    .isoTodoCheckAll {
      display: -webkit-inline-flex;
      display: -ms-inline-flex;
      display: inline-flex;
      align-items: center;

      .ant-checkbox {
        .ant-checkbox-inner {
          width: 15px;
          height: 15px;
        }

        &.ant-checkbox-disabled {
          .ant-checkbox-inner {
            border-color: ${palette('grayscale', 2)};

            &:after {
              border-color: ${palette('grayscale', 2)};
            }
          }
        }
      }

      span {
        font-size: 13px;
        line-height: 1;
        color: ${palette('text', 3)};
      }
    }

    .isoDeleteAll {
      background-color: ${palette('primary', 0)};
      border: 0;
      height: 30px;
      padding: 0 15px;
      ${borderRadius('3px')};
      ${transition()};

      span {
        font-size: 12px;
        font-weight: 400;
        padding: 0;
        text-transform: uppercase;
        color: #ffffff;
      }

      &:hover {
        background-color: ${palette('primary', 1)};
      }
    }
  }
`;
const TodoWrapper = WithDirection(WDTodoWrapper);
const TodoListWrapper = WithDirection(WDTodoListWrapper);
export { TodoWrapper, TodoListWrapper };
