import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition, borderRadius, boxShadow } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const WDSingleCardWrapper = styled.li`
  padding: 15px;
  background-color: #ffffff;
  position: relative;
  margin-bottom: 5px;
  ${boxShadow('0 0 1px rgba(0,0,0,0.15)')};

  .isoCardImage {
    overflow: hidden;
    flex-shrink: 0;
    align-items: center;
    justify-content: center;
    background-color: ${palette('grayscale', 6)};

    img {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }
  }

  .isoCardContent {
    width: 100%;
    display: flex;
    flex-direction: column;
    margin: 0 15px;

    .isoCardTitle {
      font-size: 14px;
      font-weight: 500;
      color: ${palette('text', 0)};
      margin: 0 0 3px;
    }

    .isoCardDate {
      font-size: 12px;
      font-weight: 400;
      color: ${palette('grayscale', 0)};
    }
  }

  .isoDeleteBtn {
    width: 24px;
    height: 24px;
    background-color: transparent;
    flex-shrink: 0;
    padding: 0;
    border: 0;
    font-size: 14px;
    color: ${palette('grayscale', 0)};
    cursor: pointer;
    ${transition()};

    &:hover {
      color: ${palette('primary', 0)};
    }
  }

  &.list {
    width: 100%;
    display: flex;
    align-items: center;

    .isoCardImage {
      width: 35px;
      height: 35px;
      display: -webkit-inline-flex;
      display: -ms-inline-flex;
      display: inline-flex;
      ${borderRadius('50%')};
    }
  }

  &.grid {
    width: calc(100% / 3 - 15px);
    display: flex;
    flex-direction: column;
    margin: 0 7px 15px;
    padding: 0;

    @media only screen and (max-width: 767px) {
      width: calc(100% / 2 - 10px);
      margin: 0 5px 10px;
    }

    @media only screen and (max-width: 480px) {
      width: 100%;
      margin-right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
      margin-left: ${props => (props['data-rtl'] === 'rtl' ? '0' : 'inherit')};
    }

    @media only screen and (min-width: 1400px) {
      width: calc(100% / 4 - 15px);
      margin: 0 7px 15px;
    }

    .isoCardImage {
      width: 100%;
      height: 260px;
      display: flex;

      @media only screen and (min-width: 960px) {
        height: 330px;
      }
    }

    .isoCardContent {
      padding: 15px;
      margin: 0;
    }

    .isoDeleteBtn {
      position: absolute;
      top: 0;
      right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
      left: ${props => (props['data-rtl'] === 'rtl' ? '0' : 'inherit')};
    }
  }
`;

const WDSortableCardWrapper = styled.div`
  padding: 50px 35px;

  @media only screen and (max-width: 767px) {
    padding: 30px 20px;
  }

  .isoControlBar {
    width: 100%;
    display: flex;
    margin-bottom: 30px;
    align-items: center;

    @media only screen and (max-width: 767px) {
      align-items: flex-start;
      flex-direction: column;
    }

    > * {
      display: flex;
      align-items: center;

      .isoControlBtn {
        font-size: 12px;
        font-weight: 400;
        text-transform: uppercase;
        color: #ffffff;
        background-color: ${palette('primary', 0)};
        border: 0;
        outline: 0;
        display: -webkit-inline-flex;
        display: -ms-inline-flex;
        display: inline-flex;
        align-items: center;
        height: 35px;
        padding: 0 15px;
        margin-right: ${props => (props['data-rtl'] === 'rtl' ? '0' : '10px')};
        margin-left: ${props => (props['data-rtl'] === 'rtl' ? '10px' : '0')};
        cursor: pointer;
        ${borderRadius('3px')};
        ${transition()};

        @media only screen and (max-width: 430px) {
          padding: 0 10px;
        }

        i {
          padding-right: ${props =>
            props['data-rtl'] === 'rtl' ? '0' : '10px'};
          padding-left: ${props =>
            props['data-rtl'] === 'rtl' ? '10px' : '0'};
        }

        &:last-child {
          margin-right: ${props => (props['data-rtl'] === 'rtl' ? '0' : '0')};
          margin-left: ${props => (props['data-rtl'] === 'rtl' ? '0' : '0')};
        }

        &:hover {
          background-color: ${palette('primary', 1)};
        }
      }

      &.isoControlBtnGroup {
        margin-left: ${props =>
          props['data-rtl'] === 'rtl' ? 'inherit' : 'auto'};
        margin-right: ${props =>
          props['data-rtl'] === 'rtl' ? 'auto' : 'inherit'};

        @media only screen and (max-width: 767px) {
          margin-left: ${props =>
            props['data-rtl'] === 'rtl' ? 'inherit' : '0'};
          margin-right: ${props =>
            props['data-rtl'] === 'rtl' ? '0' : 'inherit'};
          margin-top: 20px;
        }
      }
    }
  }

  .isoAddRemoveControlBar {
    width: 100%;
    display: flex;
    justify-content: center;
    margin-top: 30px;

    .isoControlBtnGroup {
      display: flex;
      align-items: center;

      .isoControlBtn {
        font-size: 12px;
        font-weight: 400;
        padding: 0;
        text-transform: uppercase;
        color: #ffffff;
        background-color: ${palette('primary', 0)};
        border: 0;
        outline: 0;
        height: 30px;
        padding: 0 15px;
        margin-right: ${props => (props['data-rtl'] === 'rtl' ? '0' : '10px')};
        margin-left: ${props => (props['data-rtl'] === 'rtl' ? '10px' : '0')};
        cursor: pointer;
        ${borderRadius('3px')};
        ${transition()};

        i {
          padding-right: ${props =>
            props['data-rtl'] === 'rtl' ? '0' : '10px'};
          padding-left: ${props =>
            props['data-rtl'] === 'rtl' ? '10px' : '0'};
        }

        &:last-child {
          margin: 0;
        }

        &:hover {
          background-color: ${palette('primary', 1)};
        }
      }
    }
  }

  &.grid {
    .isoSortableCardsContainer {
      ul {
        width: 100%;
        display: flex;
        flex-flow: row wrap;
      }
    }
  }
`;
const SingleCardWrapper = WithDirection(WDSingleCardWrapper);
const SortableCardWrapper = WithDirection(WDSortableCardWrapper);

export { SingleCardWrapper, SortableCardWrapper };
