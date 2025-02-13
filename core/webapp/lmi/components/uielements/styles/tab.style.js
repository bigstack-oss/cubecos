import styled from 'styled-components';

const AntTab = ComponentName => styled(ComponentName)`
  &.ant-tabs {
    &:not(.ant-tabs-vertical) {
      > .ant-tabs-content-animated {
        display: ${props => (props['data-rtl'] === 'rtl' ? 'block' : 'flex')};
      }
    }

    .ant-tabs-nav {
      .ant-tabs-tab {
        margin: ${props =>
					props['data-rtl'] === 'rtl' ? '0 0 0 24px' : '0 24px 0 0'};

        .anticon:not(.anticon-close) {
          margin: ${props =>
						props['data-rtl'] === 'rtl' ? '0 0 0 8px' : '0 8px 0 0'};

          &.anticon-close{
            right: ${props =>
							props['data-rtl'] === 'rtl' ? 'inherit' : '2px'};;
            left: ${props =>
							props['data-rtl'] === 'rtl' ? '2px' : 'inherit'};;
          }
        }
      }
    }

    .ant-tabs-tab-prev {
      left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
      right ${props => (props['data-rtl'] === 'rtl' ? '2px' : 'inherit')};
      transform: ${props =>
				props['data-rtl'] === 'rtl' ? 'rotate(180deg)' : 'rotate(0)'};
        &.ant-tabs-tab-btn-disabled{
          opacity:0;
        }

    }

    .ant-tabs-tab-next {
      left: ${props => (props['data-rtl'] === 'rtl' ? '0' : 'inherit')};
      right ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '2px')};
      transform: ${props =>
				props['data-rtl'] === 'rtl' ? 'rotate(180deg)' : 'rotate(0)'};
        &.ant-tabs-tab-btn-disabled{
          opacity:0;
        }
    }

    &.ant-tabs-vertical{
      .ant-tabs-tab-prev,
      .ant-tabs-tab-next{
        transform: rotate(0);
      }
    }
    .ant-tabs-tab-arrow-show{
      opacity:1;
    }
  }
`;

export default AntTab;
