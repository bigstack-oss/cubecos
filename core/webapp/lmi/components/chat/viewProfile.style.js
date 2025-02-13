import styled from 'styled-components';
import { palette } from 'styled-theme';

const ViewProfileWrapper = styled.div`
  background: #ffffff;
  border: 1px solid ${palette('border', 0)};
  overflow: auto;
  position: absolute;
  right: 0;
  width: 95%;
  height: 100%;

  .viewProfileTopBar {
    background: ${palette('grayscale', 4)};
    border-bottom: 1px solid ${palette('border', 0)};
    padding: 25px 20px 25px 30px;
    display: flex;
    justify-content: space-between;
    line-height: 1;

    span {
      margin: 0;
      margin-left: 15px;
      cursor: pointer;
      i {
        font-size: 14px;
        font-weight: normal;
      }
    }
  }
  .viewProfileContent {
    padding: 30px 30px 0;
  }
  .viewProfileImage {
    display: flex;
    flex-direction: column;
    align-items: center;
  }
  h1 {
    font-size: 21px;
    text-align: center;
    font-weight: 300;
    margin-bottom: 30px;
    margin-top: 10px;
    color: #212121;
  }
  img {
    height: 120px;
    border-radius: 6px;
  }
  .viewProfileQuickInfo {
    border-top: 1px solid ${palette('border', 2)};
    padding-top: 40px;
  }
  @media only screen and (min-width: 768px) {
    width: 350px;
  }
`;

const SingleInfoWrapper = styled.div`
  display: flex;

  .viewProfileTitle {
    width: 35%;
    font-size: 13px;
    font-weight: 500;
    font-weight: light;
    color: ${palette('text', 0)};
    margin-bottom: 30px;
  }
  .viewProfileValue {
    width: 65%;
    text-align: right;
    font-size: 13px;
    color: ${palette('text', 1)};
    margin-bottom: 30px;
  }
`;

export { ViewProfileWrapper, SingleInfoWrapper };
