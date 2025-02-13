import React from 'react';
import { Alert } from 'antd';
import styled from 'styled-components';
import { palette } from 'styled-theme';
import WithDirection from '../../config/withDirection';

const AntAlert = props => <Alert {...props} />;

const Alerts = styled(AntAlert)`
  && {
    color: ${palette('text', 1)};
    font-size: 12px;
  }

  &&.ant-alert-success {
    .ant-alert-icon {
      color: ${palette('success', 0)};
    }
  }

  &&.ant-alert-error {
    .ant-alert-icon {
      color: ${palette('error', 0)};
    }
  }

  &&.ant-alert-with-description {
    padding: ${props =>
      props['data-rtl'] === 'rtl'
        ? '16px 60px 16px 16px'
        : '16px 16px 16px 60px'};
    .ant-alert-message {
      font-weight: 500;
      color: ${palette('text', 0)};
    }

    .ant-alert-description {
      color: ${palette('text', 1)};
      font-size: 12px;
    }

    .ant-alert-icon {
      top: 20px;
      left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '20px')};
      right: ${props => (props['data-rtl'] === 'rtl' ? '20px' : 'inherit')};
    }
    &&.ant-alert-no-icon {
      padding: ${props =>
        props['data-rtl'] === 'rtl'
          ? '12px 16px 12px 48px'
          : '12px 48px 12px 16px'};
    }
    .ant-alert-close-icon {
      right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '16px')};
      left: ${props => (props['data-rtl'] === 'rtl' ? '16px' : 'inherit')};
    }
  }
  &&.ant-alert-no-icon {
    padding: ${props =>
      props['data-rtl'] === 'rtl'
        ? '12px 16px 12px 48px'
        : '12px 48px 12px 16px'};
  }
  .ant-alert-close-icon {
    right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '16px')};
    left: ${props => (props['data-rtl'] === 'rtl' ? '16px' : 'inherit')};
  }
`;

export default WithDirection(Alerts);
