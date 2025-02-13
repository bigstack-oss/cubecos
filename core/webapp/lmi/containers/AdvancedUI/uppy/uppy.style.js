import styled from 'styled-components';

const UppyStyleWrapper = styled.div`
  @-webkit-keyframes 'a' {
    40% {
      opacity: 1;
      -webkit-transform: scale3d(0.475, 0.475, 0.475) translate3d(42px, 0, 0);
      transform: scale3d(0.475, 0.475, 0.475) translate3d(42px, 0, 0);
    }
    to {
      opacity: 0;
      -webkit-transform: scale(0.1) translate3d(-2000px, 0, 0);
      transform: scale(0.1) translate3d(-2000px, 0, 0);
      -webkit-transform-origin: left center;
      transform-origin: left center;
    }
  }
  @keyframes 'a' {
    40% {
      opacity: 1;
      -webkit-transform: scale3d(0.475, 0.475, 0.475) translate3d(42px, 0, 0);
      transform: scale3d(0.475, 0.475, 0.475) translate3d(42px, 0, 0);
    }
    to {
      opacity: 0;
      -webkit-transform: scale(0.1) translate3d(-2000px, 0, 0);
      transform: scale(0.1) translate3d(-2000px, 0, 0);
      -webkit-transform-origin: left center;
      transform-origin: left center;
    }
  }
  @-webkit-keyframes 'b' {
    0% {
      background-position: 64px 0;
    }
    to {
      background-position: 0 0;
    }
  }
  @keyframes 'b' {
    0% {
      background-position: 64px 0;
    }
    to {
      background-position: 0 0;
    }
  }
  .UppyAnimation-zoomOutLeft {
    -webkit-animation-name: a;
    animation-name: a;
    -webkit-animation-duration: 1s;
    animation-duration: 1s;
    -webkit-animation-fill-mode: both;
    animation-fill-mode: both;
  }
  .Uppy {
    box-sizing: border-box;
  }
  .Uppy * {
    box-sizing: inherit;
  }
  .Uppy:after {
    box-sizing: inherit;
  }
  .Uppy:before {
    box-sizing: inherit;
  }
  .UppyIcon {
    max-width: 100%;
    max-height: 100%;
    fill: currentColor;
    display: inline-block;
    vertical-align: text-top;
    overflow: hidden;
  }
  .UppyTheme--default {
    font-family: -apple-system, BlinkMacSystemFont, avenir next, avenir,
      helvetica, helvetica neue, ubuntu, roboto, noto, segoe ui, arial,
      sans-serif;
    line-height: 1;
    -webkit-font-smoothing: antialiased;
  }
  .UppyButton--circular {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    box-shadow: 1px 2px 4px 0 rgba(0, 0, 0, 0.2);
    border-radius: 50%;
    cursor: pointer;
    transition: all 0.3s;
  }
  .UppyButton--blue {
    color: #fff;
    background-color: #4a90e2;
  }
  .UppyButton--blue:focus {
    background-color: #2275d7;
  }
  .UppyButton--blue:hover {
    background-color: #2275d7;
  }
  .UppyButton--white {
    color: #525252;
    background-color: #fff;
  }
  .UppyButton--white:focus {
    color: #fff;
    background-color: #2275d7;
  }
  .UppyButton--white:hover {
    color: #fff;
    background-color: #2275d7;
  }
  .UppyButton--yellow {
    color: #fff;
    background-color: #ffd600;
  }
  .UppyButton--yellow:focus {
    background-color: #e6c100;
  }
  .UppyButton--yellow:hover {
    background-color: #e6c100;
  }
  .UppyButton--green {
    color: #fff;
    background-color: #7ac824;
  }
  .UppyButton--green:focus {
    background-color: #609d1c;
  }
  .UppyButton--green:hover {
    background-color: #609d1c;
  }
  .UppyButton--red {
    color: #fff;
    background-color: #d32f2f;
  }
  .UppyButton--red:focus {
    background-color: #ab2424;
  }
  .UppyButton--red:hover {
    background-color: #ab2424;
  }
  .UppyButton--sizeM {
    width: 60px;
    height: 60px;
  }
  .UppyButton--sizeS {
    width: 45px;
    height: 45px;
  }
  .uppy-FileInput-form {
    margin-bottom: 15px;
  }
  .uppy-FileInput-btn {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    font-family: sans-serif;
    font-size: 0.85em;
    padding: 10px 15px;
    color: #e02177;
    border: 1px solid #e02177;
    border-radius: 15px;
    cursor: pointer;
  }
  .uppy-FileInput-btn:hover {
    background-color: #e02177;
    color: #fff;
  }
  .UppyInformer {
    position: absolute;
    bottom: 0;
    left: 0;
    right: 0;
    text-align: center;
    font-size: 12px;
    font-weight: 500;
    padding: 0 15px;
    height: 30px;
    line-height: 30px;
    background-color: #000;
    color: #fff;
    opacity: 0.9;
    -webkit-transform: none;
    transform: none;
    transition: all 0.3s ease-in;
    z-index: 1004;
  }
  .UppyInformer p {
    margin: 0;
    padding: 0;
    height: 30px;
    line-height: 30px;
  }
  .UppyDashboard--wide .UppyInformer {
    height: 40px;
    line-height: 40px;
    font-size: 13px;
  }
  .UppyDashboard--wide .UppyInformer p {
    height: 40px;
    line-height: 40px;
  }
  .UppyDashboard--wide .UppyDashboard-close {
    color: #525252;
    top: 16px;
    right: 16px;
  }
  .UppyDashboard--wide .UppyDashboard-close .UppyIcon {
    width: 17px;
    height: 17px;
  }
  .UppyDashboard--wide .UppyDashboardTabs-title {
    font-size: 17px;
    line-height: 40px;
  }
  .UppyDashboard--wide .UppyDashboardTab {
    width: 75px;
    margin: 0 5px;
  }
  .UppyDashboard--wide .UppyDashboardTab .UppyIcon {
    width: 23px;
    height: 23px;
  }
  .UppyDashboard--wide .UppyDashboardTab-name {
    font-size: 9px;
  }
  .UppyDashboard--wide .UppyDashboardContent-bar {
    height: 50px;
  }
  .UppyDashboard--wide .UppyDashboardContent-title {
    font-size: 16px;
    line-height: 50px;
    max-width: 300px;
  }
  .UppyDashboard--wide .UppyDashboardContent-back {
    font-size: 15px;
    line-height: 50px;
  }
  .UppyDashboard--wide .UppyDashboardContent-panel {
    padding-top: 50px;
  }
  .UppyDashboard--wide .UppyDashboard-bgIcon .UppyIcon {
    height: 110px;
  }
  .UppyDashboard--wide .UppyDashboard-dropFilesTitle {
    font-size: 18px;
  }
  .UppyDashboard--wide .UppyDashboard-note {
    font-size: 13px;
  }
  .UppyDashboard--wide .UppyDashboardItem {
    -webkit-box-orient: vertical;
    -webkit-box-direction: normal;
    -ms-flex-direction: column;
    flex-direction: column;
    float: left;
    width: 140px;
    height: 170px;
    margin: 15px 21px;
    border-radius: 6px;
    border: 0;
  }
  .UppyDashboard--wide .UppyDashboardItem-preview {
    width: 100%;
    height: 100px;
    border: 0;
  }
  .UppyDashboard--wide .UppyDashboardItem-sourceIcon {
    top: 8px;
    left: 8px;
    width: 15px;
    height: 15px;
  }
  .UppyDashboard--wide .UppyDashboardItem-previewInnerWrap {
    border-top-left-radius: 6px;
    border-top-right-radius: 6px;
  }
  .UppyDashboard--wide .UppyDashboardItem-previewIcon {
    width: 40%;
    max-height: 80%;
  }
  .UppyDashboard--wide .UppyDashboardItem-info {
    width: 100%;
    max-width: 100%;
    -webkit-box-flex: 1;
    -ms-flex: 1;
    flex: 1;
    border-bottom-left-radius: 6px;
    border-bottom-right-radius: 6px;
    border: 1px solid rgba(148, 148, 148, 0.2);
    border-top: 0;
  }
  .UppyDashboard--wide .UppyDashboardItem-name {
    word-wrap: break-word;
    white-space: normal;
  }
  .UppyDashboard--wide .UppyDashboardItem-copyLink {
    top: 8px;
    right: 8px;
  }
  .UppyDashboard--wide .UppyDashboardItem-copyLink .UppyIcon {
    width: 13px;
    height: 13px;
  }
  .UppyDashboard--wide .UppyDashboardItem-edit {
    top: 8px;
    right: 8px;
  }
  .UppyDashboard--wide .UppyDashboardItem-edit .UppyIcon {
    width: 12px;
    height: 12px;
  }
  .UppyDashboard--wide .UppyDashboardItem-action {
    top: -8px;
    right: -8px;
  }
  .UppyDashboard--wide .UppyDashboardItem-remove {
    width: 20px;
    color: #525252;
  }
  .UppyDashboard--wide .UppyDashboardItem-progressBtn {
    width: 55px;
    height: 55px;
  }
  .UppyDashboard--wide
    .UppyDashboardItem.is-complete
    .UppyDashboardItem-progressBtn {
    width: 25px;
    height: 25px;
  }
  .UppyDashboard--wide .UppyDashboardItem-progressInfo {
    display: block;
  }
  .UppyDashboard--wide .UppyDashboard-actions {
    bottom: 20px;
    right: 20px;
  }
  .UppyDashboard--wide .UppyDashboard-upload {
    width: 60px;
    height: 60px;
  }
  .UppyDashboard--wide .UppyDashboard-uploadCount {
    width: 18px;
    height: 18px;
    line-height: 18px;
    font-size: 9px;
  }
  .UppyDashboard--wide .UppyDashboardFileCard-inner {
    padding-top: 50px;
  }
  .UppyDashboard--wide .UppyDashboardFileCard-label {
    font-size: 13px;
  }
  .UppyDashboard--wide .UppyDashboardFileCard-input {
    font-size: 15px;
  }
  .UppyDashboard--wide .UppyDashboardFileCard-done {
    width: 60px;
    height: 60px;
  }
  .UppyDashboard--wide .UppyDashboardFileCard-done .UppyIcon {
    width: 30px;
    height: 30px;
  }
  .UppyDashboard--wide .UppyStatusBar {
    height: 40px;
    line-height: 40px;
    font-size: 14px;
  }
  .UppyDashboard--wide .UppyStatusBar-content .UppyIcon {
    width: 17px;
    height: 17px;
  }
  .UppyInformer[aria-hidden='true'] {
    opacity: 0;
    -webkit-transform: translateY(200%);
    transform: translateY(200%);
    transition: all 0.3s ease-in;
  }
  .UppyDashboard--modal {
    z-index: 1001;
  }
  .UppyDashboard--modal .UppyDashboard-overlay {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background-color: rgba(255, 255, 255, 0.8);
    z-index: 990;
  }
  .UppyDashboard--modal .UppyDashboard-inner {
    position: fixed;
    top: 0;
    left: 0;
    border: none;
  }
  .UppyDashboard--modal .UppyDashboard-close {
    display: block;
  }
  .UppyDashboard--modal[aria-hidden='true'] {
    display: none;
  }
  .is-UppyDashboard-open {
    width: 100%;
    overflow: hidden;
    position: fixed;
  }
  .UppyDashboard-inner {
    position: relative;
    background-color: #fafafa;
    max-width: 100%;
    max-height: 100%;
    width: 100%;
    height: 100%;
    margin: 0 auto;
    overflow: hidden;
    z-index: 993;
    outline: none;
    border: 1px solid rgba(148, 148, 148, 0.2);
  }
  .UppyDashboard-innerWrap {
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-orient: vertical;
    -webkit-box-direction: normal;
    -ms-flex-direction: column;
    flex-direction: column;
    height: 100%;
    overflow: hidden;
    min-height: 300px;
  }
  .UppyDashboard--semiTransparent .UppyDashboard-inner {
    background-color: rgba(255, 255, 255, 0.8);
    -webkit-backdrop-filter: saturate(180%) blur(20px);
  }
  .UppyDashboard-close {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    display: none;
    position: fixed;
    top: 12px;
    right: 12px;
    cursor: pointer;
    color: #929292;
    z-index: 1004;
    transition: all 0.2s;
  }
  .UppyDashboard-close:hover {
    color: #000;
  }
  .UppyDashboard-close .UppyIcon {
    width: 14px;
    height: 14px;
  }
  .UppyDashboardTabs {
    padding-top: 7px;
    padding-bottom: 7px;
    border-bottom: 1px dashed #b9b9b9;
  }
  .UppyDashboardTabs[aria-hidden='true'] {
    display: none;
  }
  .UppyDashboardTabs-title {
    font-size: 15px;
    line-height: 30px;
    font-weight: 400;
    margin: 0;
    padding: 0;
    text-align: center;
    color: #525252;
  }
  .UppyDashboard-browse {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    cursor: pointer;
    color: #2275d7;
  }
  .UppyDashboardTabs-list {
    list-style-type: none;
    margin: 0;
    padding: 0;
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-pack: center;
    -ms-flex-pack: center;
    justify-content: center;
    -webkit-box-align: center;
    -ms-flex-align: center;
    align-items: center;
  }
  .UppyDashboardTab {
    width: 70px;
    margin: 0 2px;
    display: inline-block;
    text-align: center;
  }
  .UppyDashboardTab .UppyIcon {
    width: 20px;
    height: 20px;
    vertical-align: middle;
  }
  .UppyDashboardTab-btn {
    width: 100%;
    cursor: pointer;
    border: 0;
    background-color: transparent;
    -webkit-appearance: none;
    outline: none;
    transition: all 0.3s;
    color: #535353;
  }
  .UppyDashboardTab-btn:active {
    color: #4a90e2;
  }
  .UppyDashboardTab-btn:focus {
    color: #4a90e2;
  }
  .UppyDashboardTab-btn:hover {
    color: #4a90e2;
  }
  .UppyDashboardTab-name {
    font-size: 8px;
    margin-top: 5px;
    margin-bottom: 0;
    font-weight: 400;
    overflow-x: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .UppyDashboard-input {
    width: 0.1px;
    height: 0.1px;
    opacity: 0;
    overflow: hidden;
    position: absolute;
    z-index: -1;
  }
  .UppyDashboardContent-bar {
    position: absolute;
    top: 0;
    left: 0;
    height: 40px;
    width: 100%;
    border-bottom: 1px solid rgba(148, 148, 148, 0.3);
    z-index: 1004;
    background-color: #f5f5f5;
  }
  .UppyDashboardContent-title {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    text-align: center;
    margin: 0;
    font-size: 14px;
    line-height: 40px;
    font-weight: 400;
    max-width: 170px;
    text-overflow: ellipsis;
    white-space: nowrap;
    overflow-x: hidden;
    margin: auto;
  }
  .UppyDashboardContent-titleFile {
    text-decoration: underline;
  }
  .UppyDashboardContent-back {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    position: absolute;
    top: 0;
    right: 15px;
    font-size: 14px;
    line-height: 40px;
    font-weight: 500;
    cursor: pointer;
    color: #4a90e2;
  }
  .UppyDashboardContent-back .UppyIcon {
    position: relative;
    margin-right: 3px;
  }
  .UppyDashboardContent-panel {
    position: absolute;
    top: 0;
    bottom: 0;
    left: 0;
    right: 0;
    -webkit-transform: translateY(-105%);
    transform: translateY(-105%);
    transition: -webkit-transform 0.2s ease-in-out;
    transition: transform 0.2s ease-in-out;
    transition: transform 0.2s ease-in-out, -webkit-transform 0.2s ease-in-out;
    will-change: transform;
    background-color: #f5f5f5;
    box-shadow: 0 0 10px 5px rgba(0, 0, 0, 0.15);
    padding-top: 40px;
    overflow: hidden;
    z-index: 1003;
  }
  .UppyDashboardContent-panel[aria-hidden='false'] {
    -webkit-transform: none;
    transform: none;
  }
  .UppyDashboard-progress {
    position: absolute;
    bottom: 0;
    left: 0;
    width: 100%;
    height: 12%;
  }
  .UppyDashboard-progressBarContainer.is-active {
    z-index: 1004;
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
  }
  .UppyDashboard-next {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: none;
    background-color: rgba(148, 148, 148, 0.7);
    -webkit-appearance: none;
    border: 0;
    z-index: 1003;
    transition: background-color 0.5s;
    color: #fff;
    font-family: inherit;
    font-size: 14px;
    line-height: 1;
    padding: 0;
    margin: 0;
    outline: none;
    cursor: not-allowed;
  }
  .UppyDashboard-next.is-active {
    cursor: pointer;
    background-color: #4a90e2;
  }
  .UppyDashboard-next.is-active:hover {
    background-color: #1b5dab;
  }
  .UppyDashboard-filesContainer {
    position: relative;
    overflow-y: hidden;
    margin: 0;
    -webkit-box-flex: 1;
    -ms-flex: 1;
    flex: 1;
  }
  .UppyDashboard-filesContainer:after {
    content: '';
    display: table;
    clear: both;
  }
  .UppyDashboard-files {
    margin: 0;
    padding: 10px;
    overflow-y: auto;
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
  }
  .UppyDashboard.drag .UppyDashboard-innerWrap {
    background-color: #e6e6e6;
  }
  .UppyDashboard.drag .UppyDashboard-files--noFiles {
    border-color: #b1b1b1;
  }
  .UppyDashboard.drag .UppyDashboard-bgIcon {
    opacity: 1;
  }
  .UppyDashboard-bgIcon {
    width: 100%;
    max-width: 360px;
    position: absolute;
    top: 50%;
    left: 50%;
    -webkit-transform: translate(-50%, -50%);
    transform: translate(-50%, -50%);
    opacity: 0.7;
    transition: all 0.3s;
    padding: 0 20px;
  }
  .UppyDashboard-bgIcon .UppyIcon {
    width: 100%;
    height: 80px;
    fill: none;
    stroke: #525252;
  }
  .UppyDashboard-dropFilesTitle {
    text-align: center;
    font-size: 15px;
    line-height: 1.45;
    font-weight: 400;
    color: #525252;
    margin: 0;
    margin-top: 25px;
  }
  .UppyDashboard-note {
    font-size: 12px;
    line-height: 1.2;
    text-align: center;
    margin-top: 20px;
    color: #525252;
  }
  .UppyDashboardItem {
    list-style: none;
    margin: 10px 0;
    position: relative;
    background-color: #fff;
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-align: center;
    -ms-flex-align: center;
    align-items: center;
    border: 1px solid rgba(148, 148, 148, 0.2);
  }
  .UppyDashboardItem .bg {
    stroke: rgba(255, 255, 255, 0.4);
    opacity: 0;
  }
  .UppyDashboardItem .progress {
    stroke: #fff;
    transition: stroke-dashoffset 0.5s ease-out;
    opacity: 0;
  }
  .UppyDashboardItem .play {
    stroke: #fff;
    display: none;
    fill: #fff;
    opacity: 0;
    transition: all 0.2s;
  }
  .UppyDashboardItem .cancel {
    fill: #fff;
    opacity: 0;
    transition: all 0.2s;
  }
  .UppyDashboardItem .pause {
    fill: #fff;
    opacity: 0;
    transition: all 0.2s;
    stroke: #fff;
    display: none;
  }
  .UppyDashboardItem-preview {
    width: 60px;
    height: 60px;
    border-bottom: 0;
    position: relative;
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-pack: center;
    -ms-flex-pack: center;
    justify-content: center;
    -webkit-box-align: center;
    -ms-flex-align: center;
    align-items: center;
  }
  .UppyDashboardItem-preview img {
    width: 100%;
    height: 100%;
    -o-object-fit: cover;
    object-fit: cover;
  }
  .UppyDashboardItem-sourceIcon {
    color: rgba(255, 255, 255, 0.95);
    position: absolute;
    top: 4px;
    left: 4px;
    width: 10px;
    height: 10px;
    z-index: 1003;
  }
  .UppyDashboardItem-sourceIcon .UppyIcon {
    -webkit-filter: drop-shadow(0 0 1px rgba(0, 0, 0, 0.3));
    filter: drop-shadow(0 0 1px rgba(0, 0, 0, 0.3));
  }
  .UppyDashboardItem-previewInnerWrap {
    width: 100%;
    height: 100%;
    overflow: hidden;
    position: relative;
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-pack: center;
    -ms-flex-pack: center;
    justify-content: center;
    -webkit-box-align: center;
    -ms-flex-align: center;
    align-items: center;
    -webkit-box-orient: vertical;
    -webkit-box-direction: normal;
    -ms-flex-direction: column;
    flex-direction: column;
  }
  .UppyDashboardItem-previewInnerWrap:after {
    content: '';
    position: absolute;
    top: 0;
    bottom: 0;
    left: 0;
    right: 0;
    background-color: rgba(0, 0, 0, 0.65);
    display: none;
    z-index: 1001;
  }
  .UppyDashboardItem-previewIconWrap {
    height: 85%;
    position: relative;
  }
  .UppyDashboardItem-previewIconBg {
    height: 100%;
    -webkit-filter: drop-shadow(rgba(0, 0, 0, 0.1) 0 0 1px);
    filter: drop-shadow(rgba(0, 0, 0, 0.1) 0 0 1px);
  }
  .UppyDashboardItem-previewIcon {
    width: 25%;
    max-height: 55%;
    z-index: 100;
    position: absolute;
    top: 50%;
    left: 50%;
    -webkit-transform: translate(-50%, -50%);
    transform: translate(-50%, -50%);
  }
  .UppyDashboardItem-info {
    padding: 8px 32px 8px 10px;
    position: relative;
    max-width: 70%;
  }
  .UppyDashboardItem-name {
    font-size: 11px;
    line-height: 1.35;
    font-weight: 500;
    margin: 0;
    padding: 0;
    max-height: 28px;
    margin-bottom: 5px;
    text-overflow: ellipsis;
    white-space: nowrap;
    overflow: hidden;
  }
  .UppyDashboardItem-name a {
    text-decoration: underline;
    color: #000;
  }
  .UppyDashboardItem-status {
    font-size: 11px;
    font-weight: 400;
    color: #939393;
    margin-bottom: 4px;
  }
  .UppyDashboardItem-statusSize {
    text-transform: uppercase;
  }
  .UppyDashboardItem-copyLink {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    font-size: 12px;
    text-align: left;
    cursor: pointer;
    position: absolute;
    top: 9px;
    right: 10px;
  }
  .UppyDashboardItem-copyLink .UppyIcon {
    width: 11px;
    height: 11px;
    color: #525252;
  }
  .UppyDashboardItem-edit {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    font-size: 12px;
    text-align: left;
    cursor: pointer;
    position: absolute;
    top: 9px;
    right: 10px;
  }
  .UppyDashboardItem-edit .UppyIcon {
    width: 11px;
    height: 11px;
    color: #525252;
  }
  .UppyDashboardItem-action {
    position: absolute;
    top: 8px;
    right: 5px;
    z-index: 1003;
  }
  .UppyDashboardItem-remove {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    cursor: pointer;
    color: rgba(82, 82, 82, 0.6);
    width: 16px;
  }
  .UppyDashboardItem-remove .UppyIcon {
    max-width: 100%;
  }
  .UppyDashboardItem.is-inprogress:not(.is-resumable)
    .UppyDashboardItem-remove {
    display: none;
  }
  .UppyDashboardItem.is-inprogress .UppyDashboardItem-progress {
    display: block;
  }
  .UppyDashboardItem.is-inprogress .bg {
    opacity: 1;
  }
  .UppyDashboardItem.is-inprogress .cancel {
    opacity: 1;
  }
  .UppyDashboardItem.is-inprogress .pause {
    opacity: 1;
  }
  .UppyDashboardItem.is-inprogress .progress {
    opacity: 1;
  }
  .UppyDashboardItem.is-inprogress .UppyDashboardItem-previewInnerWrap:after {
    display: block;
  }
  .UppyDashboardItem-progress {
    position: absolute;
    top: 50%;
    left: 50%;
    -webkit-transform: translate(-50%, -50%);
    transform: translate(-50%, -50%);
    z-index: 1003;
    color: #fff;
    text-align: center;
    width: 120px;
    display: none;
    transition: all 0.35 ease;
  }
  .UppyDashboardItem.is-complete .UppyDashboardItem-progress {
    -webkit-transform: initial;
    transform: none;
    top: -7px;
    right: -7px;
    left: auto;
    width: auto;
    display: block;
  }
  .UppyDashboardItem.is-complete .UppyDashboardItem-progressBtn {
    width: 18px;
    height: 18px;
    opacity: 1;
    cursor: default;
  }
  .UppyDashboardItem.is-complete .progress {
    stroke: #7ac824;
    fill: #7ac824;
    opacity: 1;
  }
  .UppyDashboardItem.is-complete .check {
    opacity: 1;
  }
  .UppyDashboardItem-progressBtn {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    width: 38px;
    height: 38px;
    opacity: 0.9;
    cursor: pointer;
    transition: all 0.35s ease;
  }
  .UppyDashboardItem-progressInfo {
    font-size: 9px;
    line-height: 1;
    font-weight: 500;
    height: 10px;
    display: none;
    position: absolute;
    bottom: -10px;
    left: 0;
    width: 100%;
    text-shadow: 0 1px 0 rgba(0, 0, 0, 0.3);
  }
  .UppyIcon-progressCircle {
    width: 100%;
    height: 100%;
  }
  .UppyIcon-progressCircle .check {
    opacity: 0;
    fill: #fff;
    transition: all 0.2s;
  }
  .UppyDashboardItem.is-resumable .pause {
    display: block;
  }
  .UppyDashboardItem.is-resumable .play {
    display: block;
  }
  .UppyDashboardItem.is-resumable .cancel {
    display: none;
  }
  .UppyDashboardItem.is-paused .pause {
    opacity: 0;
  }
  .UppyDashboardItem.is-paused .play {
    opacity: 1;
  }
  .UppyTotalProgress {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    width: 70px;
    height: 70px;
    cursor: pointer;
  }
  .UppyTotalProgress .UppyIcon {
    width: 100%;
    height: 100%;
  }
  .UppyTotalProgress .bg {
    stroke: rgba(74, 144, 226, 0.3);
    transition: all 0.2s;
    opacity: 1;
    box-shadow: 1px 2px 4px 0 rgba(0, 0, 0, 0.2);
  }
  .UppyTotalProgress .progress {
    stroke: #3483de;
    transition: stroke-dashoffset 0.5s ease-out;
    opacity: 1;
  }
  .UppyTotalProgress .play {
    stroke: #3483de;
    fill: #3483de;
    transition: all 0.2s;
    opacity: 0;
  }
  .UppyTotalProgress .pause {
    stroke: #3483de;
    fill: #3483de;
    transition: all 0.2s;
    opacity: 1;
  }
  .UppyTotalProgress .check {
    fill: #fff;
    transition: all 0.2s;
    opacity: 0;
  }
  .UppyTotalProgress--is-paused .pause {
    opacity: 0;
  }
  .UppyTotalProgress--is-paused .play {
    opacity: 1;
  }
  .UppyTotalProgress--is-complete {
    cursor: default;
  }
  .UppyTotalProgress--is-complete .pause {
    opacity: 0;
  }
  .UppyTotalProgress--is-complete .play {
    opacity: 0;
  }
  .UppyTotalProgress--is-complete .bg {
    stroke: #7ac824;
    opacity: 1;
  }
  .UppyTotalProgress--is-complete .progress {
    stroke: #7ac824;
    fill: #7ac824;
    opacity: 1;
  }
  .UppyTotalProgress--is-complete .check {
    opacity: 1;
  }
  .UppyTotalProgress-info {
    font-size: 10px;
    color: #525252;
  }
  .UppyDashboardItem-progressNum {
    position: relative;
    z-index: 1001;
  }
  .UppyDashboardItem-progressInner {
    height: 15px;
    background-color: #4a90e2;
    position: absolute;
    top: 0;
    left: 0;
  }
  .UppyDashboard-actions {
    text-align: center;
    position: absolute;
    bottom: 16px;
    right: 16px;
    z-index: 1003;
  }
  .UppyDashboard-pauseResume .UppyIcon {
    width: 100%;
    height: 100%;
  }
  .UppyDashboard-upload {
    position: relative;
    width: 50px;
    height: 50px;
  }
  .UppyDashboard-upload .UppyIcon {
    position: relative;
    top: 1px;
    width: 50%;
  }
  .UppyDashboard-uploadCount {
    position: absolute;
    top: -12px;
    right: -12px;
    background-color: #7ac824;
    color: #fff;
    border-radius: 50%;
    width: 16px;
    height: 16px;
    line-height: 16px;
    font-size: 8px;
  }
  .UppyDashboardFileCard {
    -webkit-transform: translateY(0);
    transform: translateY(0);
    transition: all 0.25s ease-in-out;
    width: 100%;
    height: 100%;
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: 1004;
    box-shadow: 0 0 10px 4px rgba(0, 0, 0, 0.1);
    background-color: #fff;
  }
  .UppyDashboardFileCard[aria-hidden='true'] {
    -webkit-transform: translateY(-105%);
    transform: translateY(-105%);
  }
  .UppyDashboardFileCard-inner {
    height: 100%;
    padding-top: 40px;
  }
  .UppyDashboardFileCard-preview {
    height: 45%;
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-align: center;
    -ms-flex-align: center;
    align-items: center;
    -webkit-box-pack: center;
    -ms-flex-pack: center;
    justify-content: center;
    border-bottom: 1px solid rgba(148, 148, 148, 0.3);
    background-color: #f9f9f9;
    position: relative;
  }
  .UppyDashboardFileCard-preview img {
    box-shadow: 0 3px 20px rgba(0, 0, 0, 0.15);
    max-width: 90%;
    max-height: 90%;
    -o-object-fit: cover;
    object-fit: cover;
  }
  .UppyDashboardFileCard-info {
    padding: 30px 20px 20px;
  }
  .UppyDashboardFileCard-fieldset {
    font-size: 0;
    border: 0;
    padding: 0;
    margin: 0;
    max-width: 450px;
    margin: auto;
    margin-bottom: 15px;
  }
  .UppyDashboardFileCard-label {
    display: inline-block;
    vertical-align: middle;
    width: 25%;
    font-size: 11px;
    color: #525252;
  }
  .UppyDashboardFileCard-input {
    display: inline-block;
    vertical-align: middle;
    width: 75%;
    border: 0;
    border-bottom: 1px solid rgba(82, 82, 82, 0.3);
    outline: none;
    font-size: 12px;
    line-height: 1.8;
    padding-left: 5px;
    margin: auto;
  }
  .UppyDashboardFileCard-input:focus {
    border-color: #525252;
  }
  .UppyDashboardFileCard-done {
    width: 50px;
    height: 50px;
  }
  .UppyDashboardFileCard-done .UppyIcon {
    width: 25px;
    height: 25px;
  }
  .UppyDragDrop-container {
    min-height: 100px;
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-align: center;
    -ms-flex-align: center;
    align-items: center;
    -webkit-box-pack: center;
    -ms-flex-pack: center;
    justify-content: center;
    border-radius: 10px;
  }
  .UppyDragDrop-inner {
    margin: 0;
  }
  .UppyDragDrop-container.is-dragdrop-supported {
    border: 2px dashed;
    border-color: #c6c6c6;
  }
  .UppyDragDrop-container.is-dragdrop-supported .UppyDragDrop-dragText {
    display: inline;
  }
  .UppyDragDrop-container.drag {
    border-color: #939393;
  }
  .UppyDragDrop-input {
    width: 0.1px;
    height: 0.1px;
    opacity: 0;
    overflow: hidden;
    position: absolute;
    z-index: -1;
  }
  .UppyDragDrop-label {
    display: block;
    cursor: pointer;
    font-size: 1.2em;
  }
  .UppyDragDrop-selectedCount {
    text-align: center;
    font-size: 0.75em;
    text-transform: uppercase;
    letter-spacing: 1px;
    margin-top: 10px;
  }
  .UppyDragDrop-dragText {
    display: none;
  }
  .UppyProvider-auth {
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-align: center;
    -ms-flex-align: center;
    align-items: center;
    -webkit-box-pack: center;
    -ms-flex-pack: center;
    justify-content: center;
    -ms-flex-flow: column wrap;
    flex-flow: column wrap;
    height: 100%;
  }
  .UppyProvider-error {
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-align: center;
    -ms-flex-align: center;
    align-items: center;
    -webkit-box-pack: center;
    -ms-flex-pack: center;
    justify-content: center;
    -ms-flex-flow: column wrap;
    flex-flow: column wrap;
    height: 100%;
  }
  .UppyProvider-loading {
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-align: center;
    -ms-flex-align: center;
    align-items: center;
    -webkit-box-pack: center;
    -ms-flex-pack: center;
    justify-content: center;
    -ms-flex-flow: column wrap;
    flex-flow: column wrap;
    height: 100%;
  }
  .UppyProvider-authTitle {
    font-size: 22px;
    line-height: 1.35;
    font-weight: 300;
    margin-bottom: 30px;
    padding: 0 15px;
    max-width: 500px;
    text-align: center;
  }
  .UppyProvider-authBtn {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    border-radius: 6px;
    background-color: #4a90e2;
    color: #fff;
    font-size: 20px;
    padding: 12px 46px;
    transition: background-color 0.3s;
    text-decoration: none;
    margin-bottom: 20px;
    cursor: pointer;
  }
  .UppyProvider-authBtn:hover {
    background-color: #2275d7;
    color: #fff;
  }
  .UppyGoogleDrive-sidebar button {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    margin: 0;
    border: 0;
    outline: none;
    cursor: pointer;
    font-size: 14px;
    padding: 0;
  }
  .UppyGoogleDrive-sidebar button:focus {
    outline: 1px dotted #aaa;
  }
  .UppyProvider-breadcrumbs {
    -webkit-box-flex: 1;
    -ms-flex: 1;
    flex: 1;
    color: #000;
    font-size: 12px;
    list-style-type: none;
    padding: 0;
    margin: 0;
    margin-left: 16px;
  }
  .UppyProvider-breadcrumbs button {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    cursor: pointer;
    font-size: 14px;
  }
  .UppyProvider-breadcrumbs button:hover {
    text-decoration: underline;
  }
  .UppyProvider-breadcrumbs button:focus {
    outline: 1px dotted #aaa;
  }
  .UppyProvider-breadcrumbs li {
    display: inline-block;
    margin: 0;
    margin-right: 6px;
  }
  .UppyProvider-breadcrumbs li:not(:last-child):after {
    content: '/';
  }
  .Browser {
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-orient: vertical;
    -webkit-box-direction: normal;
    -ms-flex-direction: column;
    flex-direction: column;
    font-size: 13px;
    font-weight: 400;
    height: 100%;
  }
  .Browser-user {
    margin: 16px 0;
  }
  .Browser-header {
    z-index: 1000;
    border-bottom: 1px solid #e5e5e5;
    position: relative;
  }
  ::-webkit-input-placeholder {
    color: rgba(120, 120, 120, 0.75);
  }
  :-moz-placeholder {
    color: rgba(120, 120, 120, 0.75);
  }
  ::-moz-placeholder {
    color: rgba(120, 120, 120, 0.75);
  }
  :-ms-input-placeholder {
    color: rgba(120, 120, 120, 0.75);
  }
  .Browser-headerBar {
    line-height: 50px;
    padding-left: 16px;
    z-index: 1001;
    height: 50px;
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-align: center;
    -ms-flex-align: center;
    align-items: center;
    background-color: #f9f9f9;
  }
  .Browser-search {
    height: 50px;
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-align: center;
    -ms-flex-align: center;
    align-items: center;
    background-color: #f9f9f9;
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    z-index: 1003;
    -webkit-transform: translateY(-50px);
    transform: translateY(-50px);
    transition: all 0.2s;
  }
  .Browser-search input {
    -webkit-box-flex: 1;
    -ms-flex: 1;
    flex: 1;
    background-color: transparent;
    outline: 0;
    font-size: 15px;
    font-weight: 400;
    line-height: 50px;
    border: 0;
    padding: 0 16px;
  }
  .Browser-search[aria-hidden='false'] {
    -webkit-transform: translate(0);
    transform: translate(0);
  }
  .Browser-searchToggle {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    width: 15px;
    cursor: pointer;
    color: #939393;
    transition: all 0.2s;
  }
  .Browser-searchToggle:hover {
    color: #000;
  }
  .Browser-searchClose {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    cursor: pointer;
    width: 12px;
    color: #939393;
    transition: all 0.2s;
    position: relative;
    right: 16px;
  }
  .Browser-searchClose:hover {
    color: #000;
  }
  .Browser-userLogout {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    margin-right: 16px;
    cursor: pointer;
  }
  .Browser-userLogout:hover {
    text-decoration: underline;
  }
  .Browser-breadcrumbs span {
    font-size: 16px;
    margin-left: 32px;
  }
  .Browser-breadcrumbs span.active {
    color: #666;
    -webkit-box-flex: 1;
    -ms-flex: 1;
    flex: 1;
    font-weight: 500;
  }
  .Browser-body {
    -webkit-box-flex: 1;
    -ms-flex: 1;
    flex: 1;
    position: relative;
  }
  .BrowserTable {
    display: block;
    width: 100%;
    height: 100%;
    background-color: #fff;
    border-spacing: 0;
    overflow-x: hidden;
    overflow-y: auto;
    position: absolute;
    top: 0;
    bottom: 0;
    left: 0;
    right: 0;
  }
  .BrowserTable tbody {
    display: block;
  }
  .Browser-viewType--grid .BrowserTable tbody {
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-orient: horizontal;
    -webkit-box-direction: normal;
    -ms-flex-direction: row;
    flex-direction: row;
    -ms-flex-wrap: wrap;
    flex-wrap: wrap;
    -ms-flex-pack: distribute;
    justify-content: space-around;
  }
  .Browser-viewType--grid .BrowserTable-column {
    padding: 14px 10px;
  }
  .BrowserTable-row {
    display: block;
    cursor: pointer;
  }
  .BrowserTable-row:hover {
    background-color: #eee;
  }
  .BrowserTable-header {
    display: block;
    background-color: #fafafa;
  }
  .BrowserTable-header:hover {
    background-color: #939393;
  }
  .BrowserTable-column {
    color: #525252;
    line-height: 1.2;
    font-weight: 700;
    padding: 16px;
  }
  .BrowserTable-column img {
    vertical-align: text-top;
    margin-right: 3px;
  }
  .BrowserTable-headerColumn {
    cursor: pointer;
    text-align: left;
  }
  .nav-active {
    font-weight: 700;
  }
  .UppyProgressBar {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 3px;
    z-index: 10000;
  }
  .UppyProgressBar-inner {
    background-color: #4a90e2;
    box-shadow: 0 0 10px rgba(74, 144, 226, 0.7);
    height: 100%;
    width: 0;
    transition: width 0.4s ease;
  }
  .UppyProgressBar-percentage {
    display: none;
    text-align: center;
    position: absolute;
    top: 50%;
    left: 50%;
    -webkit-transform: translate(-50%, -50%);
    transform: translate(-50%, -50%);
    color: #fff;
  }
  .UppyStatusBar {
    position: relative;
    height: 30px;
    line-height: 30px;
    font-size: 12px;
    font-weight: 500;
    color: #fff;
    background-color: rgba(82, 82, 82, 0.7);
    box-shadow: 1px 1px 4px 0 rgba(82, 82, 82, 0.3);
    overflow: hidden;
    z-index: 1001;
    transition: height 0.35s;
  }
  .UppyStatusBar[aria-hidden='true'] {
    height: 0;
  }
  .UppyStatusBar.is-complete .UppyStatusBar-progress {
    background-color: #7ac824;
  }
  .UppyStatusBar.is-complete .UppyStatusBar-content {
    text-align: center;
    padding-left: 0;
  }
  .UppyStatusBar.is-error .UppyStatusBar-progress {
    background-color: #d32f2f;
  }
  .UppyStatusBar-progress {
    background-color: #4a90e2;
    height: 100%;
    position: absolute;
    z-index: 1001;
    transition: background-color, width 0.3s ease-out;
  }
  .UppyStatusBar-progress.is-indeterminate {
    background-size: 64px 64px;
    background-image: linear-gradient(
      45deg,
      #2275d7 25%,
      transparent 0,
      transparent 50%,
      #2275d7 0,
      #2275d7 75%,
      transparent 0,
      transparent
    );
    -webkit-animation: b 1s linear infinite;
    animation: b 1s linear infinite;
  }
  .UppyStatusBar-content {
    font-weight: 600;
    position: relative;
    z-index: 1003;
    padding-left: 15px;
    white-space: nowrap;
    text-overflow: ellipsis;
    overflow: hidden;
  }
  .UppyStatusBar-content .UppyIcon {
    width: 15px;
    height: 15px;
  }
  .UppyStatusBar-action {
    color: #fff;
    margin-right: 8px;
  }
  button.UppyStatusBar-action {
    background: none;
    -webkit-appearance: none;
    font-family: inherit;
    font-size: inherit;
    line-height: 1;
    padding: 0;
    margin: 0;
    border: 0;
    outline: none;
    margin-right: 8px;
    cursor: pointer;
  }
  .UppyWebcam-container {
    width: 100%;
    height: 100%;
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-pack: center;
    -ms-flex-pack: center;
    justify-content: center;
    -webkit-box-align: center;
    -ms-flex-align: center;
    align-items: center;
  }
  .UppyWebcam-videoContainer {
    height: 100%;
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    -webkit-box-pack: center;
    -ms-flex-pack: center;
    justify-content: center;
    -webkit-box-align: center;
    -ms-flex-align: center;
    align-items: center;
  }
  .UppyWebcam-video {
    max-width: 100%;
    max-height: 100%;
  }
  .UppyWebcam-buttonContainer {
    position: absolute;
    bottom: 30px;
    right: 30px;
  }
  .UppyWebcam-recordButton .UppyIcon {
    width: 50%;
    height: 50%;
    position: relative;
    top: -1px;
  }
  @media only screen and (min-width: 768px) {
    .UppyDashboard-inner {
      width: 750px;
      height: 550px;
      border-radius: 5px;
    }
    .UppyDashboard--modal .UppyDashboard-inner {
      top: 50%;
      left: 50%;
      -webkit-transform: translate(-50%, -50%);
      transform: translate(-50%, -50%);
      box-shadow: 0 0 20px 7px rgba(148, 148, 148, 0.15);
    }
  }
`;

export default UppyStyleWrapper;
