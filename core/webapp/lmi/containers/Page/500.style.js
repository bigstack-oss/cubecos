import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition, borderRadius } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const FiveZeroZeroStyleWrapper = styled.div`
  width: 100%;
  height: 100vh;
  display: flex;
  flex-flow: row wrap;
  align-items: center;
  justify-content: center;
  position: relative;

  @media only screen and (max-width: 767px) {
    flex-direction: column;
    flex-wrap: nowrap;
    padding: 50px 0;
  }

  .iso500Content {
    display: flex;
    justify-content: center;
    align-items: flex-end;
    flex-direction: column;

    @media only screen and (max-width: 767px) {
      order: 2;
      margin-top: 20px;
      align-items: center;
      text-align: center;
    }

    h1 {
      font-size: 84px;
      font-weight: 700;
      color: ${palette('secondary', 2)};
      line-height: 1;
      margin: 0 0 25px;
    }

    h3 {
      font-size: 24px;
      font-weight: 400;
      color: ${palette('text', 1)};
      margin: 0 0 10px;
      line-height: 1.2;
    }

    p {
      font-size: 14px;
      font-weight: 400;
      color: ${palette('text', 3)};
      margin: 0 0 10px;
    }

    button {
      display: inline-block;
      margin-top: 15px;
      margin-bottom: 0;
      font-weight: 500;
      text-align: center;
      -ms-touch-action: manipulation;
      touch-action: manipulation;
      cursor: pointer;
      background-image: none;
      border: 0;
      white-space: nowrap;
      line-height: 1.5;
      padding: 0 30px;
      font-size: 13px;
      height: 36px;
      -webkit-user-select: none;
      -moz-user-select: none;
      -ms-user-select: none;
      user-select: none;
      position: relative;
      color: #ffffff;
      background-color: ${palette('primary', 0)};
      ${transition()};
      ${borderRadius('18px')};
      .isoMenuHolder {
        color: ${palette('primary', 0)};
        .nav-text {
          color: #fff;
        }
      }

      a {
        width: 100%;
        height: 100%;
        color: #ffffff;
        text-decoration: none;
      }

      &:hover {
        background-color: ${palette('primary', 2)};

        a {
          text-decoration: none;
        }
      }

      &:focus {
        outline: 0;
        box-shadow: none;

        a {
          text-decoration: none;
        }
      }
    }
  }

  .iso500Artwork {
    display: flex;
    align-items: center;
    justify-content: center;
    margin-left: ${props =>
      props['data-rtl'] === 'rtl' ? 'inherit' : '100px'};
    margin-right: ${props =>
      props['data-rtl'] === 'rtl' ? '100px' : 'inherit'};
    height: 500px;

    @media only screen and (max-width: 767px) {
      margin-left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
      margin-right: ${props => (props['data-rtl'] === 'rtl' ? '0' : 'inherit')};
    }

    img {
      max-height: 100%;
    }
  }
`;

export default WithDirection(FiveZeroZeroStyleWrapper);
