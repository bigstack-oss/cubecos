import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition, borderRadius, boxShadow } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const WDContactListWrapper = styled.div`
  width: 100%;
  display: flex;
  flex-direction: column;
  height: 100%;

  .isoNoResultMsg {
    padding: 15px 20px;
    text-align: center;
    color: ${palette('secondary', 2)};
    font-weight: 500;
    font-size: 14px;
  }

  .isoSearchBar {
    .ant-input {
      width: 100%;
      font-size: 14px;
      font-weight: 400;
      color: ${palette('text', 0)};
      line-height: inherit;
      height: 69px;
      padding: 0 20px;
      padding-left: ${props =>
        props['data-rtl'] === 'rtl' ? 'inherit' : '35px'};
      padding-right: ${props =>
        props['data-rtl'] === 'rtl' ? '35px' : 'inherit'};
      border: 0;
      border-bottom: 1px solid ${palette('border', 0)};
      outline: 0 !important;
      overflow: hidden;
      background-color: #ffffff;
      ${boxShadow('none')};
      ${borderRadius()};
      ${transition()};

      @media only screen and (max-width: 767px) {
        height: 50px;
      }

      &:hover,
      &:focus {
        border-color: ${palette('border', 0)} !important;
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
  }

  .ant-input-suffix {
    left: 10px;
    right: auto;
    color: ${palette('grayscale', 0)};
  }

  .isoContactList {
    width: 100%;
    display: flex;
    flex-direction: column;
    max-height: 100%;
    overflow: hidden;
    overflow-y: auto;

    .contactListScrollbar {
      height: calc(100vh - 200px);

      @media only screen and (max-width: 767px) {
        height: 60vh;
      }
    }

    .isoSingleContact {
      width: 100%;
      margin: 0;
      display: flex;
      align-items: center;
      justify-content: flex-start;
      flex-shrink: 0;
      padding: 15px 20px;
      padding-right: ${props =>
        props['data-rtl'] === 'rtl' ? '20px' : '35px'};
      padding-left: ${props => (props['data-rtl'] === 'rtl' ? '35px' : '20px')};
      border-bottom: 1px solid ${palette('border', 0)};
      text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
      position: relative;
      cursor: pointer;

      &.active {
        background-color: ${palette('secondary', 1)};
      }

      &:last-child {
        border-bottom: 0;
      }

      .isoAvatar {
        width: 35px;
        height: 35px;
        display: flex;
        align-items: center;
        justify-content: center;
        margin-right: ${props =>
          props['data-rtl'] === 'rtl' ? 'inherit' : '15px'};
        margin-left: ${props =>
          props['data-rtl'] === 'rtl' ? '15px' : 'inherit'};
        flex-shrink: 0;
        overflow: hidden;
        ${borderRadius('50%')};

        img {
          width: 100%;
          height: 100%;
          object-fit: cover;
        }
      }

      .isoNoteText {
        width: calc(100% - 60px);
        margin-right: ${props =>
          props['data-rtl'] === 'rtl' ? 'inherit' : '20px'};
        margin-left: ${props =>
          props['data-rtl'] === 'rtl' ? '20px' : 'inherit'};
        padding: 20px 0;
        cursor: pointer;

        h3 {
          width: 100%;
          white-space: nowrap;
          text-overflow: ellipsis;
          overflow: hidden;
          color: ${palette('secondary', 2)};
          font-weight: 500;
        }

        .isoNoteCreatedDate {
          font-size: 13px;
          color: ${palette('grayscale', 0)};
        }
      }

      .isoDeleteBtn {
        width: 24px;
        height: 24px;
        background-color: transparent;
        flex-shrink: 0;
        position: absolute;
        top: 20px;
        right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '5px')};
        left: ${props => (props['data-rtl'] === 'rtl' ? '5px' : 'inherit')};
        padding: 0;
        border: 0;
        font-size: 14px;
        color: ${palette('grayscale', 0)};
        ${transition()};

        &:hover {
          color: ${palette('primary', 0)};
        }
      }
    }

    .isoNotlistNotice {
      font-size: 14px;
      font-weight: 400;
      color: ${palette('grayscale', 0)};
      line-height: inherit;
      padding: 30px 0;
    }
  }
`;

const ContactListWrapper = WithDirection(WDContactListWrapper);

export { ContactListWrapper };
