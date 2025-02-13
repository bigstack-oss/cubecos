import styled from 'styled-components';
import { palette } from 'styled-theme';
import { borderRadius, transition } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const WDYoutubeSearchListStyleWrapper = styled.div`
  width: 100%;
  display: flex;
  flex-direction: column;

  .isoSingleVideoResult {
    padding: 20px 0;
    border-bottom: 1px solid ${palette('border', 2)};
    display: flex;
    width: 100%;

    &:last-of-type {
      border-bottom: 0;
    }

    .videoThumb {
      width: 100px;
      height: 100px;
      display: -webkit-inline-flex;
      display: -ms-inline-flex;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;
      overflow: hidden;

      @media only screen and (max-width: 420px) {
        width: 70px;
        height: 70px;
      }

      img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
    }

    .videoDescription {
      display: flex;
      flex-direction: column;
      width: 100%;
      margin: ${props => (props['data-rtl'] === 'rtl' ? '0 20px 0 0' : '0 0 0 20px')};
      cursor: pointer;

      h3.videoName {
        width: 70%;
        flex-shrink: 0;
        margin: 0;

        @media only screen and (max-width: 767px) {
          width: 100%;
        }

        @media only screen and (min-width: 768px) and (max-width: 1199px) {
          flex-shrink: 1;
        }

        a {
          font-size: 18px;
          font-weight: 400;
          color: ${palette('text', 0)};
          line-height: 1.3;
          word-break: break-word;
          display: inline-block;
          text-decoration: none;
          ${transition('')};

          &:hover {
            color: ${palette('primary', 0)};
          }
        }
      }

      .ChannelNameAndDate {
        width: 100%;
        display: flex;
        align-items: center;
        margin-top: 3px;

        @media only screen and (max-width: 420px) {
          flex-direction: column;
          align-items: flex-start;
        }

        .channelTitle {
          width: auto;
          flex-shrink: 0;
          display: inline-block;
          align-items: center;
          font-size: 13px;
          font-weight: 400;
          color: ${palette('text', 2)};
          line-height: 1.3;
          ${transition('')};

          &:hover {
            color: ${palette('primary', 11)};
          }
        }

        .uploadDate {
          font-size: 13px;
          font-weight: 400;
          color: ${palette('text', 2)};
          line-height: 1.3;
          display: inline-block;
          padding-left: 20px;
          position: relative;

          &:before {
            content: '';
            width: 4px;
            height: 4px;
            display: inline-block;
            background-color: ${palette('grayscale', 0)};
            position: absolute;
            top: 6px;
            left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '8px')};
            right: ${props => (props['data-rtl'] === 'rtl' ? '8px' : 'inherit')};
            ${borderRadius('50%')};
          }

          @media only screen and (max-width: 420px) {
            padding: ${props =>
              props['data-rtl'] === 'rtl' ? '0 13px 0 0' : '0 0 0 13px'};

            &:before {
              left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
              right: ${props => (props['data-rtl'] === 'rtl' ? '0' : 'inherit')};
            }
          }
        }
      }

      p {
        font-size: 14px;
        font-weight: 400;
        color: ${palette('text', 3)};
        line-height: 1.3;
        margin-bottom: 0;
        margin-top: 10px;
        display: block;
        word-break: break-word;
      }
    }
  }
`;
const YoutubeSearchStyleWrapper = styled.div`
  margin-top: 30px;

  .isoTotalResultFind {
    font-size: 18px;
    font-weight: 700;
    color: ${palette('text', 0)};
    line-height: 1.3;
    padding-bottom: 15px;
    border-bottom: 1px solid ${palette('border', 2)};
  }

  .youtubeSearchPagination {
    display: -webkit-flex;
    display: -ms-flex;
    display: flex;
    align-items: center;
    justify-content: center;
    margin: 25px 0 10px;

    button {
      margin: 0 10px;
    }
  }
`;

const YoutubeModal = ComponentName => styled(ComponentName)`
  .ant-modal-close-x {
    width: 35px;
    height: 35px;
    line-height: 35px;
  }

  .ant-modal-body {
    padding: 15px;
    iframe {
      width: 100%;
    }
  }
`;

const YoutubeSearchListStyleWrapper = WithDirection(
  WDYoutubeSearchListStyleWrapper
);

export {
  YoutubeSearchListStyleWrapper,
  YoutubeSearchStyleWrapper,
  YoutubeModal,
};
