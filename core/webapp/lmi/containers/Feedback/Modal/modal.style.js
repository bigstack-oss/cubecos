import styled from 'styled-components';
import { palette } from 'styled-theme';
import { borderRadius } from '../../../config/style-util';

const Modals = ComponentName => styled(ComponentName)`
  .ant-modal-header {
    padding: 13px 16px;
    background: ${palette('grayscale', 5)};
    color: ${palette('text', 0)};
    border-bottom: 1px solid ${palette('border', 0)};
    ${borderRadius('4px 4px 0 0')};
  }

  .ant-modal-title {
    margin: 0;
    font-size: 15px;
    line-height: 21px;
    font-weight: 500;
    color: ${palette('text', 0)};
  }

  .ant-modal-close {
    right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
    left: ${props => (props['data-rtl'] === 'rtl' ? '0' : 'inherit')};
  }

  .ant-modal-body {
    padding: 16px;
    font-size: 13px;
    color: ${palette('text', 3)};
    line-height: 1.5;
  }

  .ant-modal-footer {
    border-top: 1px solid ${palette('border', 0)};
    padding: 10px 16px 10px 10px;
    text-align: right;
    ${borderRadius('0 0 4px 4px')};

    .ant-btn-lg {
      padding: 0 35px;
      font-size: 14px;
      height: 42px;
    }

    button + button {
      margin: ${props =>
        props['data-rtl'] === 'rtl' ? '0 8px 0 0' : '0 0 0 8px'};
    }
  }

  .ant-confirm {
    .ant-modal-body {
      padding: 30px 35px;
    }
  }

  .ant-confirm-body {
    .ant-confirm-title {
      color: ${palette('text', 0)};
      font-weight: 700;
      font-size: 15px;
    }

    .ant-confirm-content {
      margin-left: 42px;
      font-size: 13px;
      color: ${palette('text', 3)};
      margin-top: 8px;
    }
  }
`;

const ModalContent = styled.div`
  p {
    font-size: 13px;
    color: ${palette('text', 3)};
    line-height: 1.5;
  }
`;

export default Modals;
export { ModalContent };
