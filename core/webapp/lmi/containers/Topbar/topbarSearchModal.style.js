import Modal from '../../components/feedback/modal';
import styled from 'styled-components';
import { palette } from 'styled-theme';
import WithDirection from '../../config/withDirection';

const TopbarSearchModal = styled(Modal)`
  &.ant-modal {
    top: 150px;
    padding-bottom: 0;
  }

  .ant-modal-close-x {
    width: 28px;
    height: 28px;
    line-height: 28px;
    display: none;
  }

  .ant-modal-content {
    overflow: hidden;
    border-radius: 5px;

    .ant-modal-header {
      display: none;
    }

    .ant-modal-body {
      padding: 0px;

      .isoSearchContainer {
        .ant-input-search {
          .ant-input {
            border: 0;
            border-radius: 0;
            padding-left: ${props =>
              props['data-rtl'] === 'rtl' ? '15px' : '55px'};
            padding-right: ${props =>
              props['data-rtl'] === 'rtl' ? '55px' : '15px'};
            height: 60px;
            font-size: 14px;

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

            &:focus {
              outline: 0;
              box-shadow: none;
            }
          }
        }

        .ant-input-suffix {
          right: ${props => (props['data-rtl'] === 'rtl' ? '20px' : 'auto')};
          left: ${props => (props['data-rtl'] === 'rtl' ? 'auto' : '20px')};
          height: 0;

          &:before {
            content: '\f4a4';
            font-family: 'ionicons';
            font-size: 24px;
            color: ${palette('text', 2)};
          }

          .ant-input-search-icon {
            display: none;
          }
        }
      }
    }
  }
`;

export default WithDirection(TopbarSearchModal);
