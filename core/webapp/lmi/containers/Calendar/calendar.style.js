import styled from 'styled-components';
import { palette } from 'styled-theme';

import { transition, borderRadius } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const WDCalendarStyleWrapper = styled.div`
  &.isomorphicCalendarWrapper {
    position: relative;
    display: flex;
    flex-direction: column;
    padding: 50px 35px;
    @media (max-width: 767px) {
      padding: 0px;
    }

    .isomorphicCalendar {
      height: 100vh;
      padding: 30px;
      background: #fff;
      border-radius: 10px;
      flex-shrink: 0;
      border: 1px solid ${palette('border', 0)};
    }
  }

  /* Reset */
  .rbc-btn {
    color: inherit;
    font: inherit;
    margin: 0;
  }

  button.rbc-btn {
    overflow: visible;
    text-transform: none;
    -webkit-appearance: button;
    cursor: pointer;
  }

  button[disabled].rbc-btn {
    cursor: not-allowed;
  }

  button.rbc-input::-moz-focus-inner {
    border: 0;
    padding: 0;
  }

  /* Calendar */

  .rbc-calendar {
    box-sizing: border-box;
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: stretch;
  }

  .rbc-calendar *,
  .rbc-calendar *:before,
  .rbc-calendar *:after {
    box-sizing: inherit;
  }

  .rbc-abs-full {
    overflow: hidden;
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
  }

  .rbc-ellipsis {
    display: block;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .rbc-rtl {
    direction: rtl;
  }

  .rbc-off-range {
    color: ${palette('text', 2)};
  }

  .rbc-header {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    padding: 7px 3px;
    text-align: center;
    vertical-align: middle;
    font-weight: 500;
    font-size: 11px;
    min-height: 0;
    color: ${palette('secondary', 2)};

    > a {
      &,
      &:active,
      &:visited {
        color: inherit;
        text-decoration: none;
      }
    }
  }

  .rbc-row-content {
    position: relative;
    user-select: none;
    z-index: 4;
  }

  .rbc-today {
    background-color: ${palette('grayscale', 11)};
  }

  /* Toolbar */
  .rbc-toolbar {
    display: flex;
    align-items: center;
    margin-bottom: 40px;
    font-size: 16px;

    @media (max-width: 990px) {
      flex-direction: column;
    }

    .rbc-toolbar-label {
      width: 100%;
      padding: 0 10px;
      text-align: center;
      font-size: 15px;
      color: ${palette('secondary', 2)};
    }

    & button {
      color: ${palette('secondary', 2)};
      font-size: 14px;
      display: inline-block;
      margin: 0;
      text-align: center;
      height: 35px;
      vertical-align: middle;
      background: none;
      background-image: none;
      border: 1px solid ${palette('border', 2)};
      padding: 0 15px;
      border-radius: 0;
      outline: 0;
      line-height: normal;
      white-space: nowrap;
      cursor: pointer;
      text-transform: capitalize;
      ${transition()};

      &:active,
      &.rbc-active {
        background-image: none;
        box-shadow: none;
        background-color: ${palette('primary', 0)};
        border-color: ${palette('primary', 0)};
        color: #ffffff;

        &:hover,
        &:focus {
          color: #ffffff;
          background-color: ${palette('primary', 0)};
          border-color: ${palette('primary', 0)};
        }
      }

      &:focus {
        color: ${palette('secondary', 2)};
        background-color: transparent;
        border-color: ${palette('border', 2)};
      }

      &:hover {
        color: #ffffff;
        background-color: ${palette('primary', 0)};
        border-color: ${palette('primary', 0)};
      }
    }
  }

  .rbc-btn-group {
    display: inline-block;
    white-space: nowrap;
    @media (max-width: 990px) {
      order: 2;
      margin-bottom: 10px;
      margin-top: 10px;
    }

    > button:first-child:not(:last-child) {
      border-top-right-radius: 0;
      border-bottom-right-radius: 0;
    }

    > button:last-child:not(:first-child) {
      border-top-left-radius: 0;
      border-bottom-left-radius: 0;
    }

    .rbc-rtl & > button:first-child:not(:last-child) {
      border-radius: 0;
      border-top-left-radius: 0;
      border-bottom-left-radius: 0;
    }

    .rbc-rtl & > button:last-child:not(:first-child) {
      border-radius: 0;
      border-top-right-radius: 0;
      border-bottom-right-radius: 0;
    }

    > button:not(:first-child):not(:last-child) {
      border-radius: 0;
    }

    button + button {
      margin: ${props =>
        props['data-rtl'] === 'rtl' ? '0 -1px 0 0' : '0 0 0 -1px'};
    }

    .rbc-rtl & button + button {
      margin-left: 0;
      margin-right: -1px;
    }

    & + &,
    & + button {
      margin-left: 10px;
    }
  }

  /* Event */
  .rbc-event {
    cursor: pointer;
    padding: 3px 15px;
    background-color: ${palette('primary', 0)};
    color: #fff;
    ${borderRadius('5px')};

    &.rbc-selected {
      background-color: ${palette('primary', 12)};
    }
  }

  .rbc-event-label {
    display: block;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 80%;
  }

  .rbc-event-overlaps {
    box-shadow: -1px 1px 5px 0px rgba(51, 51, 51, 0.5);
  }

  .rbc-event-continues-prior {
    border-top-left-radius: 0;
    border-bottom-left-radius: 0;
  }
  .rbc-event-continues-after {
    border-top-right-radius: 0;
    border-bottom-right-radius: 0;
  }

  .rbc-event-continues-earlier {
    border-top-left-radius: 0;
    border-top-right-radius: 0;
  }
  .rbc-event-continues-later {
    border-bottom-left-radius: 0;
    border-bottom-right-radius: 0;
  }

  /* Month */
  .rbc-row {
    display: flex;
    flex-direction: row;
  }

  .rbc-row-segment {
    padding: 0 1px 1px 1px;

    .rbc-event-content {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }

  .rbc-selected-cell {
    background-color: rgba(0, 0, 0, 0.1);
  }

  .rbc-show-more {
    display: block;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    background-color: rgba(255, 255, 255, 0.3);
    z-index: 4;
    font-weight: 500;
    font-size: 11px;
    height: auto;
    line-height: normal;
    white-space: nowrap;
    padding: 0 5px;
    margin-top: 5px;
    color: ${palette('secondary', 2)};
    ${transition()};

    &:hover {
      color: #252424;
    }
  }

  .rbc-month-view {
    position: relative;
    border: 1px solid transparent;
    display: flex;
    flex-direction: column;
    flex: 1 0 0;
    width: 100%;
    user-select: none;

    height: 100%;

    .rbc-header {
      border-bottom: 1px solid ${palette('border', 2)};
    }

    .rbc-header + .rbc-header {
      border-left: 1px solid ${palette('border', 2)};
    }

    .rbc-rtl & .rbc-header + .rbc-header {
      border-left-width: 0;
      border-right: 1px solid ${palette('border', 2)};
    }
  }

  .rbc-month-header {
    display: flex;
    flex-direction: row;
  }

  .rbc-month-row {
    display: flex;
    position: relative;
    flex-direction: column;
    flex: 1 0 0;
    overflow: hidden;

    height: 100%;

    + .rbc-month-row {
      border-top: 1px solid ${palette('border', 2)};
    }
  }

  .rbc-date-cell {
    padding-right: 5px;
    text-align: right;

    &.rbc-now {
      font-weight: bold;
    }

    > a {
      &,
      &:active,
      &:visited {
        color: inherit;
        text-decoration: none;
      }
    }
  }

  .rbc-row-bg {
    overflow: hidden;
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    display: flex;
    flex-direction: row;
    flex: 1 0 0;
    overflow: hidden;
  }

  .rbc-day-bg + .rbc-day-bg {
    border-left: ${props => (props['data-rtl'] === 'rtl' ? '0' : '1px')} solid
      ${palette('border', 2)};
    border-right: ${props => (props['data-rtl'] === 'rtl' ? '1px' : '0')} solid
      ${palette('border', 2)};
  }

  .rbc-day-bg .rbc-rtl + .rbc-rtl {
    border-left-width: 0;
    border-right: 1px solid ${palette('border', 2)};
  }

  .rbc-overlay {
    position: absolute;
    z-index: 5;
    border: 1px solid #e5e5e5;
    background-color: #fff;
    box-shadow: 0 5px 15px rgba(0, 0, 0, 0.25);
    padding: 10px;

    > * + * {
      margin-top: 1px;
    }
  }

  .rbc-overlay-header {
    border-bottom: 1px solid #e5e5e5;
    margin: -10px -10px 5px -10px;
    padding: 10px;
    font-weight: 700;
    text-align: center;
    color: #323332;
  }

  /* Agenda */
  .rbc-agenda-view {
    display: flex;
    flex-direction: column;
    flex: 1 0 0;
    overflow: scroll;
    -webkit-overflow-scrolling: touch;

    table {
      width: 100%;
      border: 1px solid ${palette('border', 2)};
      border-bottom: 0;

      tbody > tr > td {
        padding: 5px 10px;
        vertical-align: top;
        border-right: 1px solid ${palette('border', 2)};
      }

      .rbc-agenda-time-cell {
        padding-left: 15px;
        padding-right: 15px;
        text-transform: lowercase;
      }

      tbody > tr > td + td {
        border-left: 0;
      }

      .rbc-rtl & {
        tbody > tr > td + td {
          border-left-width: 0;
          border-right: 1px solid ${palette('border', 2)};
        }
      }

      tbody > tr + tr {
        border-top: 1px solid ${palette('border', 2)};
      }

      thead > tr > th {
        padding: 5px 12px;
        text-align: ${props =>
          props['data-rtl'] === 'rtl' ? 'right' : 'left'};
        border-bottom: 1px solid ${palette('border', 2)};

        .rbc-rtl & {
          text-align: right;
        }
      }
    }
  }

  .rbc-agenda-content {
    width: 100%;
    overflow-x: scroll;
    border: 1px solid ${palette('border', 2)};
    -webkit-overflow-scrolling: touch;

    table {
      border: 0;

      tbody {
        height: 28px;
        display: table;
      }
    }
  }

  .rbc-agenda-time-cell {
    text-transform: lowercase;

    .rbc-continues-after:after {
      content: ' »';
    }
    .rbc-continues-prior:before {
      content: '« ';
    }
  }

  .rbc-agenda-date-cell,
  .rbc-agenda-time-cell {
    white-space: nowrap;
    color: ${palette('secondary', 2)};
    font-size: 12px;
    font-weight: 400;
  }

  .rbc-agenda-event-cell {
    width: 100%;
    color: ${palette('secondary', 2)};
    font-size: 12px;
  }

  /* Time Column */
  .rbc-time-column {
    display: flex;
    flex-direction: column;
    min-height: 100%;

    .rbc-timeslot-group {
      flex: 1;
    }
  }

  .rbc-timeslot-group {
    border-bottom: 1px solid ${palette('border', 2)};
    min-height: 40px;
    display: flex;
    flex-flow: column nowrap;
  }

  .rbc-time-gutter,
  .rbc-header-gutter {
    flex: none;
  }

  .rbc-label {
    padding: 0 5px;
    color: ${palette('secondary', 2)};
  }

  .rbc-day-slot {
    position: relative;

    .rbc-event {
      border: 1px solid ${palette('primary', 12)};
      display: flex;
      max-height: 100%;
      flex-flow: column wrap;
      align-items: flex-start;
      overflow: hidden;
    }

    .rbc-event-label {
      flex: none;
      padding-right: 5px;
      width: auto;
    }

    .rbc-event-content {
      width: 100%;
      flex: 1 1 auto;
      word-wrap: break-word;
      line-height: 1;
      height: 100%;
      ${'' /* min-height: 1em; */}
    }

    .rbc-time-slot {
      border-top: 1px solid #fff;
    }
  }

  .rbc-time-content {
    .rbc-time-gutter {
      > * {
        border-left: 0;
      }
    }
  }

  .rbc-time-slot {
    flex: 1 0 0;

    &.rbc-now {
      font-weight: bold;
    }
  }

  .rbc-day-header {
    text-align: center;
  }

  .rbc-day-slot .rbc-event {
    position: absolute;
    z-index: 2;
  }

  /* Time Grid*/
  .rbc-slot-selection {
    z-index: 10;
    position: absolute;
    cursor: default;
    background-color: rgba(0, 0, 0, 0.5);
    color: #ffffff;
    font-size: 75%;
    padding: 3px;
  }

  .rbc-time-view {
    display: flex;
    flex-direction: column;
    flex: 1;
    width: 100%;
    border: 1px solid ${palette('border', 2)};
    min-height: 0;

    .rbc-time-gutter {
      white-space: nowrap;
    }

    .rbc-allday-cell {
      width: 100%;
      position: relative;
    }

    .rbc-allday-events {
      position: relative;
      z-index: 4;
    }

    .rbc-row {
      min-height: 20px;
    }
  }

  .rbc-time-header {
    display: flex;
    flex: 0 0 auto;
    flex-direction: column;

    &.rbc-overflowing {
      border-right: 1px solid ${palette('border', 2)};
    }

    .rbc-rtl &.rbc-overflowing {
      border-right-width: 0;
      border-left: 1px solid ${palette('border', 2)};
    }

    > .rbc-row > * + * {
      border-left: 1px solid ${palette('border', 2)};
    }

    .rbc-rtl & > .rbc-row > * + * {
      border-left-width: 0;
      border-right: 1px solid ${palette('border', 2)};
    }

    > .rbc-row:first-child {
      border-bottom: 1px solid ${palette('border', 2)};
    }

    .rbc-gutter-cell {
      flex: none;
    }

    > .rbc-gutter-cell + * {
      width: 100%;
    }
  }

  .rbc-time-content {
    display: flex;
    flex: 1 0 0%;
    align-items: flex-start;
    width: 100%;
    border-top: 1px solid ${palette('border', 2)};
    overflow-y: auto;
    position: relative;

    > .rbc-time-gutter {
      flex: none;
    }

    > * + * > * {
      border-left: 1px solid ${palette('border', 2)};
    }

    .rbc-rtl & > * + * > * {
      border-left-width: 0;
      border-right: 1px solid ${palette('border', 2)};
    }

    > .rbc-day-slot {
      width: 100%;
      user-select: none;
    }
  }

  .rbc-current-time-indicator {
    position: absolute;
    z-index: 1;
    left: 0;
    height: 1px;

    background-color: ${palette('primary', 0)};
    pointer-events: none;

    &::before {
      display: block;

      position: absolute;
      left: -3px;
      top: -3px;

      content: ' ';
      background-color: ${palette('primary', 0)};
      width: 8px;
      height: 8px;
      ${borderRadius('50%')};
    }

    .rbc-rtl &::before {
      left: 0;
      right: -3px;
    }
  }

  .token.comment,
  .token.prolog,
  .token.doctype,
  .token.cdata {
    color: slategray;
  }

  .token.punctuation {
    color: ${palette('text', 2)};
  }

  .namespace {
    opacity: 0.7;
  }

  .token.property,
  .token.tag,
  .token.boolean,
  .token.number,
  .token.constant,
  .token.symbol,
  .token.deleted {
    color: ${palette('calendar', 0)};
  }

  .token.selector,
  .token.attr-name,
  .token.string,
  .token.char,
  .token.builtin,
  .token.inserted {
    color: ${palette('calendar', 1)};
  }

  .token.operator,
  .token.entity,
  .token.url,
  .language-css .token.string,
  .style .token.string {
    color: ${palette('calendar', 2)};
    background: hsla(0, 0%, 100%, 0.5);
  }

  .token.atrule,
  .token.attr-value,
  .token.keyword {
    color: ${palette('calendar', 3)};
  }

  .token.function {
    color: ${palette('calendar', 4)};
  }

  .token.regex,
  .token.important,
  .token.variable {
    color: ${palette('calendar', 5)};
  }

  .token.important,
  .token.bold {
    font-weight: bold;
  }
  .token.italic {
    font-style: italic;
  }

  .token.entity {
    cursor: help;
  }
`;

const WDCalendarModalBody = styled.div`
  color: #000000;
  .isoCalendarInputWrapper {
    width: 100%;
    margin-bottom: 15px;
  }

  .isoCalendarDatePicker {
    display: flex;

    .ant-calendar-picker {
      width: calc(100% - 35px) !important;

      .ant-input {
        border-radius: ${props =>
          props['data-rtl'] === 'rtl' ? '0 4px 4px 0' : '4px 0 0 4px'};
      }

      &:hover {
        z-index: 1;
      }
    }

    .isoDeleteBtn {
      width: 35px;
      height: 35px;
      padding: 0;
      display: flex;
      flex-shrink: 0;
      margin: ${props =>
        props['data-rtl'] === 'rtl' ? '0 -1px 0 0' : '0 0 0 -1px'};
      align-items: center;
      justify-content: center;
      border-radius: ${props =>
        props['data-rtl'] === 'rtl' ? '4px 0 0 4px' : '0 4px 4px 0'};

      &:hover {
        z-index: 1;
      }
    }
  }
`;

const CalendarStyleWrapper = WithDirection(WDCalendarStyleWrapper);
const CalendarModalBody = WithDirection(WDCalendarModalBody);
export { CalendarStyleWrapper, CalendarModalBody };
