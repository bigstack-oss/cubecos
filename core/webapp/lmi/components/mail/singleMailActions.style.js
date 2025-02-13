import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const WDSingleMailActions = styled.div`
  width: 100%;
  height: 80px;
  display: flex;
  flex-shrink: 0;
  align-items: center;
  justify-content: flex-start;
  padding: 0px 30px;
  background-color: ${palette('grayscale', 6)};
  border-bottom: 1px solid ${palette('border', 0)};

  @media only screen and (max-width: 767px) {
    padding: 0 15px;
    height: 60px;
    overflow: hidden;
    overflow-x: auto;
  }

  .mailBackBtn {
    color: ${palette('secondary', 0)};
    width: auto;
    height: 35px;
    padding: 0 10px;
    font-size: 14px;
    font-weight: 500;
    display: flex;
    align-items: center;
    justify-content: center;
    background-color: #ffffff;
    outline: 0;
    border: 1px solid ${palette('border', 0)};
    margin: ${props =>
      props['data-rtl'] === 'rtl' ? '0 -1px 0 15px' : '0 15px 0 -1px'};
    cursor: pointer;
    ${transition()};

    @media only screen and (max-width: 479px) {
      margin: ${props =>
        props['data-rtl'] === 'rtl' ? '0 -1px 0 5px' : '0 5px 0 -1px'};
    }

    i {
      font-size: 16px;
      color: ${palette('secondary', 0)};
      ${transition()};
    }

    &:hover {
      color: ${palette('primary', 0)};
      background-color: darken(#ffffff, 1%);

      i {
        color: ${palette('primary', 0)};
      }
    }
  }

  .mailMoveDropdown {
    .ant-popover-inner-content {
      li {
        cursor: pointer;
        padding: 3px 0;

        &:hover {
          color: ${palette('primary', 0)};
        }
      }
    }
  }
`;

const WDMailActionsWrapper = styled.div`
  display: -webkit-flex;
  display: -ms-flex;
  display: flex;

  button {
    font-size: 16px;
    color: ${palette('secondary', 0)};
    text-align: center;
    width: 35px;
    height: 35px;
    display: flex;
    align-items: center;
    justify-content: center;
    background-color: #ffffff;
    outline: 0;
    border: 1px solid ${palette('border', 0)};
    margin: ${props =>
      props['data-rtl'] === 'rtl' ? '0 -1px 0 0' : '0 0 0 -1px'};
    cursor: pointer;
    ${transition()};

    i {
      font-size: 16px;
      color: ${palette('secondary', 0)};
      width: 100%;
      ${transition()};
    }

    &:first-child {
      margin: ${props =>
        props['data-rtl'] === 'rtl' ? '0 0 0 -1px' : '0 -1px 0 0'};
    }

    &:hover {
      color: ${palette('primary', 0)};
      background-color: #fcfcfc;

      i {
        color: ${palette('primary', 0)};
      }
    }

    &.mailBackBtn {
      width: auto;
      padding: 0 10px;
      font-size: 14px;
    }
  }
`;

const WDMailCategoryWrapper = WDMailActionsWrapper.extend`
  margin: ${props =>
    props['data-rtl'] === 'rtl' ? '0 20px 0 0' : '0 0 0 20px'};

  @media only screen and (max-width: 767px) {
    margin: ${props =>
      props['data-rtl'] === 'rtl' ? '0 auto 0 10px' : '0 10px 0 auto'};
  }

  @media only screen and (max-width: 479px) {
    margin: ${props =>
      props['data-rtl'] === 'rtl' ? '0 0 0 5px' : '0 5px 0 0'};
  }
`;

const WDMailPaginationWrapper = WDMailActionsWrapper.extend`
  margin: ${props =>
    props['data-rtl'] === 'rtl' ? '0 auto 0 0' : '0 0 0 auto'};
`;

const MailActionDropdown = styled.ul`
  li {
    cursor: pointer;
    padding: 3px 0;

    &:hover {
      color: ${palette('primary', 0)};
    }
  }
`;

const SingleMailActions = WithDirection(WDSingleMailActions);
const MailCategoryWrapper = WithDirection(WDMailCategoryWrapper);
const MailPaginationWrapper = WithDirection(WDMailPaginationWrapper);
const MailActionsWrapper = WithDirection(WDMailActionsWrapper);

export {
  SingleMailActions,
  MailActionsWrapper,
  MailCategoryWrapper,
  MailPaginationWrapper,
  MailActionDropdown,
};
