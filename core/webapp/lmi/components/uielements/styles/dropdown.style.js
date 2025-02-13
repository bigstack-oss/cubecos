import styled from 'styled-components';
import { palette } from 'styled-theme';

const DropdownWrapper = ComponentName => styled(ComponentName)`
  display: inline-block;

  &.ant-dropdown-button {
    &.ant-btn-group > .ant-btn:first-child:not(:last-child) {
      border-radius: ${props =>
        props['data-rtl'] === 'rtl' ? '0 4px 4px 0' : '4px 0  0 4px'};
    }

    &.ant-btn-group > .ant-btn:last-child:not(:first-child) {
      border-radius: ${props =>
        props['data-rtl'] === 'rtl' ? '4px 0 0 4px' : '0 4px 4px 0'};
    }

    &.ant-btn-group .ant-btn + .ant-btn {
      margin: ${props => (props['data-rtl'] === 'rtl' ? '0 -1px 0 0' : '0 0 0 -1px')};
    }
  }

  .ant-dropdown-link {
    font-size: 13px;
    color: ${palette('primary', 0)};

    &:hover {
      color: ${palette('primary', 2)};
    }
  }
`;

const DropdownMenus = ComponentName => styled(ComponentName)`
  .ant-dropdown-menu-item {
    a {
      font-size: 13px;
      color: ${palette('text', 1)};
    }
  }

  .ant-dropdown-menu-item,
  .ant-dropdown-menu-submenu-title {
    a {
      font-size: 13px;
      color: ${palette('text', 1)};
    }

    &:hover {
      background-color: ${palette('secondary', 1)};
    }
  }
`;

export default DropdownWrapper;
export { DropdownMenus };
