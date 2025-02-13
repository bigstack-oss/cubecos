import styled from 'styled-components';
import { palette } from 'styled-theme';
import { borderRadius, transition } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const SingleMailContents = styled.div`
  display: flex;
  flex-direction: column;
  flex-shrink: 0;
  height: 100%;

  .isoSingleMail {
    width: 100%;
    display: flex;
    flex-direction: column;
    height: 100%;
    overflow-y: auto;
  }
`;

const WDSingleMailHeader = styled.div`
  width: 100%;
  display: flex;
  align-items: center;
  padding: 35px;
  flex-shrink: 0;
  border-bottom: 1px solid ${palette('border', 0)};

  @media only screen and (max-width: 767px) {
    padding: 35px 20px;
  }

  h2 {
    font-size: 18px;
    font-weight: 400;
    color: ${palette('secondary', 2)};
    line-height: 1.5;
    margin: 0;
    text-align: left;
  }

  .label {
    font-size: 12px;
    font-weight: 400;
    color: #ffffff;
    line-height: 1;
    padding: 0 15px;
    height: 25px;
    line-height: 25px;
    background-color: ${palette('primary', 0)};
    text-transform: capitalize;
    margin: ${props => (props['data-rtl'] === 'rtl' ? '0 25px 0 0' : '0 0 0 25px')};
  }
`;

const WDSingleMailInfo = styled.div`
  width: 100%;
  display: flex;
  align-items: center;
  flex-shrink: 0;
  padding: 25px 35px;
  border-bottom: 1px solid ${palette('border', 0)};

  @media only screen and (max-width: 767px) {
    padding: 25px 20px;
  }

  .isoRecipentsImg {
    width: 48px;
    height: 48px;
    display: -webkit-inline-flex;
    display: -ms-inline-flex;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    flex-shrink: 0;
    ${borderRadius('50%')};

    img {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }

    span {
      width: 100%;
      height: 100%;
      display: flex;
      align-items: center;
      justify-content: center;
      background-color: ${palette('color', 4)};
      font-size: 16px;
      font-weight: 300;
      color: #fff;
      letter-spacing: 1px;
    }
  }

  .isoMailAddress {
    width: 100%;
    padding: ${props => (props['data-rtl'] === 'rtl' ? '0 20px 0 0' : '0 0 0 20px')};
    display: flex;
    flex-direction: column;
    text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};

    .isoAddress {
      width: 100%;
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      position: relative;

      h3 {
        font-size: 14px;
        font-weight: 700;
        color: ${palette('text', 0)};
        line-height: 1.1;
        margin: 0 0 8px;

        @media only screen and (max-width: 767px) {
          line-height: 1.5;
        }

        span {
          font-size: inherit;
          font-weight: 400;
          color: ${palette('secondary', 2)};
          padding: ${props =>
            props['data-rtl'] === 'rtl' ? '0 5px 0 0' : '0 0 0 5px'};
          display: -webkit-inline-flex;
          display: -ms-inline-flex;
          display: inline-flex;
        }
      }

      .mailDate {
        font-size: 13px;
        font-weight: 400;
        color: ${palette('secondary', 2)};
        flex-shrink: 0;

        @media only screen and (max-width: 767px) {
          position: absolute;
          right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
          left: ${props => (props['data-rtl'] === 'rtl' ? '0' : 'inherit')};
        }
      }
    }

    p {
      font-size: 13px;
      font-weight: 400;
      color: ${palette('secondary', 2)};
      line-height: 1.1;

      span {
        font-size: inherit;
        font-weight: 700;
        color: ${palette('text', 0)};
      }
    }
  }
`;

const WDSingleMailBody = styled.div`
  padding: 30px 35px;
  text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};
  flex-shrink: 0;
  border-bottom: 1px solid ${palette('border', 0)};

  @media only screen and (max-width: 767px) {
    padding: 30px 20px;
  }

  p {
    font-size: 14px;
    font-weight: 400;
    color: ${palette('text', 3)};
    line-height: 1.5;
    margin-bottom: 21px;
  }
`;

const WDSingleMailReply = styled.div`
  width: 100%;
  display: flex;
  align-items: center;
  padding: 35px;
  flex-shrink: 0;

  @media only screen and (max-width: 767px) {
    padding: 35px 20px;
  }

  .isoComposeMailWrapper {
    padding: 0;
    height: auto;
    overflow: hidden;
  }

  .isoReplyMailBtn {
    width: 100%;
    height: 80px;
    display: -webkit-flex;
    display: -ms-flex;
    display: flex;
    justify-content: flex-start;
    align-items: flex-start;
    font-size: 14px;
    color: ${palette('text', 2)};
    border: 1px solid ${palette('border', 0)};
    padding: 10px 15px;

    span {
      font-size: inherit;
      color: ${palette('text', 2)};
      text-decoration: underline;
      padding: ${props => (props['data-rtl'] === 'rtl' ? '0 3px 0 0' : '0 0 0 3px')};
      cursor: pointer;
      ${transition()};

      &:hover {
        color: ${palette('primary', 0)};
      }
    }
  }
`;

const SingleMailHeader = WithDirection(WDSingleMailHeader);
const SingleMailInfo = WithDirection(WDSingleMailInfo);
const SingleMailBody = WithDirection(WDSingleMailBody);
const SingleMailReply = WithDirection(WDSingleMailReply);

export {
  SingleMailContents,
  SingleMailHeader,
  SingleMailInfo,
  SingleMailBody,
  SingleMailReply,
};
