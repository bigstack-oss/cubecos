import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition, borderRadius, boxShadow } from '../../config/style-util';

const ComposeForm = styled.div`
  padding: 35px;
  text-align: left;
  height: 100%;
  width: 100%;
  overflow-y: auto;

  .isoInputBox {
    font-size: 14px;
    font-weight: 400;
    color: ${palette('text', 0)};
    line-height: inherit;
    height: 36px;
    padding: 0 15px;
    margin-bottom: 10px;
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
      box-shadow: none;
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

  .isoComposeMailBtnWrapper {
    margin-top: 10px;
    display: flex;
    align-items: center;
    justify-content: space-between;

    .isoSendMailBtn,
    .isoCancelMailBtn {
      height: 36px;
      padding: 0 30px;
      background-color: ${palette('primary', 0)};
      border: 0;
      ${transition()};

      &:hover {
        background-color: ${palette('primary', 1)};
      }
    }

    .isoCancelMailBtn {
      background-color: ${palette('error', 0)};

      &:hover {
        background-color: ${palette('error', 1)};
      }
    }
  }
`;

export default ComposeForm;
