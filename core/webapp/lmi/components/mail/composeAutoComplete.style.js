import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition, borderRadius, boxShadow } from '../../config/style-util';

const ComposeAutoCompleteStyleWrapper = styled.div`
  .restrictedSearch .tag-box input {
    display: none;
  }
  .restrictedSearch .tag-box .tag-box-pills {
    margin: 0;
  }
  .tag-box {
    width: 100%;
    position: relative;
    display: -webkit-flex;
    display: -ms-flex;
    display: flex;
    flex-flow: row wrap;
    margin-bottom: 10px;
    padding: 6px 15px;
    border: 1px solid ${palette('border', 0)};
    ${borderRadius('3px')};
  }
  .tag-box .tag-box-pills {
    display: -webkit-flex;
    display: -ms-flex;
    display: flex;
    flex-flow: row wrap;
  }
  .tag-box .tag-box-pills .tag-box-pill {
    display: flex;
    align-items: center;
    padding: 0 7px 0 10px;
    margin: 2px 5px 2px 0;
    height: 22px;
    word-break: break-word;
    background-color: ${palette('grayscale', 10)};
    border: 1px solid ${palette('border', 3)};
    ${borderRadius('3px')};
  }
  .tag-box .tag-box-pills .tag-box-pill .tag-box-pill-text {
    font-size: 13px;
    font-weight: 400;
    line-height: 1;
    color: ${palette('text', 0)};
    padding-right: 7px;
  }
  .tag-box .tag-box-pills .tag-box-pill .remove {
    background: none;
    background-color: transparent;
    border: 0;
    outline: 0;
    color: ${palette('grayscale', 0)};
    padding: 0;
    line-height: 1;
    font-size: 14px;
    font-weight: bold;
    cursor: pointer;
    ${transition()};
  }

  .tag-box .tag-box-pills .tag-box-pill .remove:hover {
    color: ${palette('text', 3)};
  }

  .tag-box input {
    font-size: 14px;
    font-weight: 400;
    color: ${palette('text', 0)};
    line-height: inherit;
    height: 22px;
    padding: 0;
    border: 0;
    outline: 0 !important;
    overflow: hidden;
    background-color: #ffffff;
    ${borderRadius('3px')};
    ${boxShadow()};
    ${transition()};
  }
  .tag-box .autocomplete {
    width: 100%;
    display: -webkit-flex;
    display: -ms-flex;
    display: flex;
    flex-direction: column;
    background-color: #fff;
    margin: 3px 0 0;
    overflow: hidden;
    word-break: break-word;
    border: 1px solid rgba(0, 0, 0, 0.2);
    text-align: left;
    position: absolute;
    left: 0;
    top: 100%;
    z-index: 10;
    ${borderRadius()};
    ${boxShadow('0 2px 4px rgba(0,0,0,0.2)')};
  }
  .tag-box .autocomplete li {
    font-size: 14px;
    font-weight: 400;
    color: ${palette('text', 0)};
    border-bottom: ${palette('border', 0)};
    line-height: 1.5;
    width: 100%;
    padding: 10px 15px;
    margin: 0;
    cursor: pointer;
    ${transition()};
  }
  .tag-box .autocomplete li:hover {
    background-color: ${palette('grayscale', 6)};
  }
  .tag-box .autocomplete li:last-of-type {
    border-bottom: 0;
  }
`;

export default ComposeAutoCompleteStyleWrapper;
