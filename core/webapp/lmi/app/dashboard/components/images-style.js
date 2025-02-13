// dashboard/components/images-style.js

import styled from 'styled-components';
import { palette } from 'styled-theme';

const ImagesDiv = styled.div`
  .ant-tabs-content {
    margin-top: 20px;
  }

  .ant-tabs-nav {
    > div {
      color: ${palette('secondary', 2)};

      &.ant-tabs-ink-bar {
        background-color: ${palette('primary', 0)};
      }

      &.ant-tabs-tab-active {
        color: ${palette('primary', 0)};
      }
    }
  }
`;

export default ImagesDiv;
