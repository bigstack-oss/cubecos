import styled from 'styled-components';
import { palette } from 'styled-theme';

const AppHolder = styled.div`
  .trigger {
    font-size: 18px;
    line-height: 64px;
    padding: 0 16px;
    cursor: pointer;
    transition: color 0.3s;
  }

  .trigger:hover {
    color: ${palette('primary', 0)};
  }

  .ant-layout-sider-collapsed .anticon {
    font-size: 16px;
  }

  .ant-layout-sider-collapsed .nav-text {
    display: none;
  }

  .ant-layout {
    background: ${palette('secondary', 1)};

    &.isoContentMainLayout {
      overflow: auto;
      overflow-x: hidden;
      @media only screen and (min-width: 768px) and (max-width: 1220px) {
        width: calc(100% - 64px);
        flex-shrink: 0;
      }

      @media only screen and (max-width: 767px) {
        width: 100%;
        flex-shrink: 0;
      }
    }
  }

  .isoLayoutContent {
    width: 100%;
    padding: 35px;
    background-color: #ffffff;
    border: 1px solid ${palette('border', 0)};
    height: 100%;
  }

  .isomorphicLayout {
    width: calc(100% - 240px);
    flex-shrink: 0;
    overflow-x: hidden !important;

    @media only screen and (max-width: 767px) {
      width: 100%;
    }

    @media only screen and (min-width: 768px) and (max-width: 1220px) {
      width: calc(100% - 64px);
    }
  }

  .ant-layout-footer {
    font-size: 13px;
    @media (max-width: 767px) {
      padding: 10px 20px;
    }
  }
`;

export default AppHolder;
