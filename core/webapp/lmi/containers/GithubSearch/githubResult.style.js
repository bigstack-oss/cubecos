import styled from 'styled-components';
import { palette } from 'styled-theme';
import { borderRadius, transition } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const WDGithubResultListStyleWrapper = styled.div`
  width: 100%;
  display: flex;
  flex-direction: column;

  .isoSingleRepository {
    padding: 20px 0;
    border-bottom: 1px solid ${palette('border', 2)};

    &:last-of-type {
      border-bottom: 0;
    }

    .titleAndLanguage {
      display: flex;
      width: 100%;
      align-items: center;

      @media only screen and (max-width: 767px) {
        flex-wrap: wrap;
      }

      h3 {
        width: 70%;
        flex-shrink: 0;

        @media only screen and (max-width: 767px) {
          width: 100%;
        }

        @media only screen and (min-width: 768px) and (max-width: 1199px) {
          flex-shrink: 1;
        }

        a {
          font-size: 17px;
          font-weight: 700;
          color: ${palette('primary', 0)};
          line-height: 1.3;
          word-break: break-word;
          display: inline-block;
          ${transition()};

          &:hover {
            color: ${palette('primary', 11)};
          }
        }
      }

      span {
        width: 120px;
        flex-shrink: 0;
        display: flex;
        align-items: center;
        font-size: 14px;
        font-weight: 400;
        color: ${palette('text', 1)};
        line-height: 1.3;

        &.language {
          margin: ${props =>
            props['data-rtl'] === 'rtl' ? '0 0 0 70px' : '0 70px 0 0'};
          &:before {
            content: '';
            width: 10px;
            height: 10px;
            margin: ${props =>
              props['data-rtl'] === 'rtl' ? '0 0 0 5px' : '0 5px 0 0'};
            display: inline-block;
            background-color: ${palette('text', 1)};
            ${borderRadius('50%')};
          }

          @media only screen and (max-width: 767px) {
            margin: ${props => (props['data-rtl'] === 'rtl' ? '0' : '0')};
          }

          @media only screen and (min-width: 768px) and (max-width: 1199px) {
            margin: ${props =>
              props['data-rtl'] === 'rtl' ? '0 0 0 40px' : '0 40px 0 0'};
          }
        }

        &.totalStars {
          width: 100px;
          &:before {
            content: '\f4b3';
            font-family: 'ionicons';
            font-size: 16px;
            color: ${palette('text', 1)};
            margin: ${props =>
              props['data-rtl'] === 'rtl' ? '0 0 0 5px' : '0 5px 0 0'};
          }
        }
      }
    }

    p {
      font-size: 14px;
      font-weight: 400;
      color: ${palette('text', 1)};
      line-height: 1.3;
      margin-bottom: 0;
      margin-top: 10px;
      display: block;
    }

    .updateDate {
      font-size: 13px;
      font-weight: 400;
      color: ${palette('text', 3)};
      line-height: 1.3;
      display: inline-block;
      margin-top: 25px;
    }
  }
`;
const GithubResultStyleWrapper = styled.div`
  margin-top: 30px;

  .isoTotalRepository {
    font-size: 18px;
    font-weight: 700;
    color: ${palette('text', 0)};
    line-height: 1.3;
    padding-bottom: 15px;
    border-bottom: 1px solid ${palette('border', 2)};
  }

  .githubSearchPagination {
    display: -webkit-flex;
    display: -ms-flex;
    display: flex;
    align-items: center;
    justify-content: center;
    margin: 25px 0 10px;

    .ant-pagination {
      display: -webkit-inline-flex;
      display: -ms-inline-flex;
      display: inline-flex;
    }
  }
`;
const GithubResultListStyleWrapper = WithDirection(
  WDGithubResultListStyleWrapper
);

export { GithubResultListStyleWrapper, GithubResultStyleWrapper };
