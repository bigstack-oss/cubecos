import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition, borderRadius } from '../../../../config/style-util';

const BasicMapWrapper = styled.div`
  .isoGoogleMap {
    display: flex;
    background: #fdfdfd;
    position: relative;
    overflow: hidden;

    .marker-icon {
      width: 44px;
      height: 44px;
      margin-left: 0;
      margin-bottom: -22px !important;
      display: -webkit-inline-flex;
      display: -ms-inline-flex;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      background-color: #ffffff;
      position: relative;
      transform: scale(1);
      transform-origin: center center;
      ${transition()};
      ${borderRadius('50%')};

      &:hover {
        transform: scale(1.15);
      }

      .marker-icon-wrapper {
        width: 36px;
        height: 36px;
        display: -webkit-inline-flex;
        display: -ms-inline-flex;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        background-color: ${palette('primary', 0)};
        ${borderRadius('50%')};

        i {
          color: #fff;
          font-size: 19px;
          line-height: 1;
        }
      }
    }

    .isoMarkerInfoWindow {
      position: relative;
    }

    .isoInfoWindowWrapper {
      position: relative;
    }

    .isoInfoWindow {
      display: block;
      overflow: hidden;
      width: 280px;
      background-color: #ffffff;
      z-index: 100;

      .isoInfoWindowImage {
        width: 100%;
        height: 180px;
        overflow: hidden;
        text-align: center;
        position: relative;
        display: inline-block;

        img {
          display: block;
          max-width: 100%;
          position: absolute;
          top: 0;
          bottom: 0;
          left: 0;
          right: 0;
          margin: auto;
        }
      }

      .isoInfoWindowDetails {
        display: block;
        padding: 15px 30px;

        .isoHeading {
          font-size: 16px;
          font-weight: 500;
          color: ${palette('text', 1)};
          margin: 0 0 5px;
        }

        .isoLocation {
          font-size: 12px;
          font-weight: 400;
          color: ${palette('text', 1)};
          margin-bottom: 0px;
        }
      }
    }

    .gm-style-iw {
      > div {
        display: block;
      }

      + div {
        display: none;
      }
    }
  }
`;

export default BasicMapWrapper;
