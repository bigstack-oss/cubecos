import styled from 'styled-components';
import { palette } from 'styled-theme';

const Messages = styled(message)`
  &.ant-message {
    .ant-message-notice-content {
      padding: 12px 16px;
      border-radius: 4px;
      box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
      background: #fff;
      display: inline-block;
      pointer-events: all;

      .ant-message-custom-content {
        font-size: 13px;
        color: ${palette('text', 1)};

        .anticon {
          margin-right: 8px;
          font-size: 15px;
          top: 1px;
          position: relative;
        }

        &.ant-message-error {
          .anticon {
            color: ${palette('error', 0)};
          }
        }
      }
    }
  }
`;

export default Messages;
