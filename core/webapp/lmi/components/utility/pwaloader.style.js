import styled from 'styled-components';
import { palette } from 'styled-theme';

const PwaLoader = styled.div`
.pwaLoaderWrapper,
.pwaComponentLoaderWrapper{
  width: 100%;
  padding-top: 50px;
  padding-left: 50px;

  @media only screen and (max-width: 767px) {
    padding-left: 10%;
  }

  .pwaLoader{
    width: 100%;
    margin-bottom: 40px;

    @media only screen and (max-width: 767px) {
      width: 90%;
    }

    &:last-child{
      margin-bottom: 0;
    }
  }

  .animated-background {
    -webkit-animation-duration: 1s;
    animation-duration: 1s;
    -webkit-animation-fill-mode: forwards;
    animation-fill-mode: forwards;
    -webkit-animation-iteration-count: infinite;
    animation-iteration-count: infinite;
    -webkit-animation-name: placeHolderLoading;
    animation-name: placeHolderLoading;
    -webkit-animation-timing-function: linear;
    animation-timing-function: linear;
    background: #f6f7f8;
    background: #dddddd;
    background: -webkit-gradient(linear, left top, right top, color-stop(8%, #dddddd), color-stop(18%, #cccccc), color-stop(33%, #dddddd));
    background: -webkit-linear-gradient(left, #dddddd 8%, #cccccc 18%, #dddddd 33%);
    background: linear-gradient(to right, #dddddd 8%, #cccccc 18%, #dddddd 33%);
    -webkit-background-size: 800px 104px;
    background-size: 800px 104px;
    height: 86px;
    position: relative;

    .background-masker {
      background: #f1f3f6;
      position: absolute;
      -webkit-box-sizing: border-box;
      -moz-box-sizing: border-box;
      box-sizing: border-box;

      &.header-top,
      &.header-bottom,
      &.subheader-bottom {
        top: 0;
        left: 0;
        right: 0;
        height: 10px;
      }

      &.header-right,
      &.subheader-right {
        top: 10px;
        left: 40px;
        height: 8px;
        width: 10px;
      }

      &.header-bottom {
        top: 18px;
        height: 6px;
      }

      &.subheader-left,
      &.subheader-right {
        top: 24px;
        height: 6px;
      }

      &.header-right,
      &.subheader-right {
        width: auto;
        left: 40%;
        right: 0;

        @media only screen and (max-width: 767px) {
          left: 70%;
        }
      }

      &.subheader-right {
        left: 30%;

        @media only screen and (max-width: 767px) {
          left: 58%;
        }
      }

      &.content-top,
      &.content-second-line,
      &.content-third-line,
      &.content-second-end,
      &.content-third-end,
      &.content-first-end {
        top: 40px;
        left: 0;
        right: 0;
        height: 6px;
      }

      &.content-top {
        top: 30px;
        height: 20px;
      }

      &.content-first-end,
      &.content-second-end,
      &.content-third-end {
        width: auto;
        left: 60%;
        right: 0;
        top: 50px;
        height: 8px;

        @media only screen and (max-width: 767px) {
          left: 88%;
        }
      }

      &.content-second-line {
        top: 58px;
      }

      &.content-second-end {
        left: 78%;
        top: 64px;

        @media only screen and (max-width: 767px) {
          left: 100%;
        }
      }

      &.content-third-line {
        top: 72px;
      }

      &.content-third-end {
        left: 67%;
        top: 78px;

        @media only screen and (max-width: 767px) {
          left: 70%;
        }
      }
    }

    &.outlined{
      .background-masker {
        border: 1px solid #ddd;
      }

      &:hover {
        .background-masker {
          border: none;

          &:hover{
            border: 1px solid #ccc;
            z-index: 1;
          }
        }
      }
    }
  }
}

.pwaComponentLoaderWrapper{
  padding: 0px;

  .animated-background{
    .background-masker{
      background-color: #ffffff;
    }
  }
}


@-webkit-keyframes placeHolderLoading {
  0% {
    background-position: -468px 0
  }
  100% {
    background-position: 468px 0
  }
}

@keyframes placeHolderLoading {
  0% {
    background-position: -468px 0
  }
  100% {
    background-position: 468px 0
  }
}

`;

export PwaLoader;
