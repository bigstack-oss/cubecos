import styled from 'styled-components';
import { palette } from 'styled-theme';
import WithDirection from '../../../config/withDirection';

const ReactDatesStyleWrapper = styled.div`
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  margin-bottom: 40px;

  .ant-form-item {
    display: flex;
    align-items: center;
    margin-right: 30px;
    margin-bottom: 0;
    margin-left: 0;

    &:last-child {
      margin-right: 0;
    }

    .ant-form-item-label {
      label {
        color: ${palette('text', 3)};
        font-size: 13px;
      }
    }
  }
`;

const ReactDateWrapper = ComponentName => styled(ComponentName)`
  .isoReactDate {
    height: 100vh;

    .DateInput__display-text--focused {
      background-color: ${palette('primary', 0)};
      border-color: ${palette('primary', 0)};
      color: #fff;
      font-weight: 400;
    }

    .CalendarDay--selected-start,
    .CalendarDay--selected-end,
    .CalendarDay--selected {
      background: ${palette('primary', 0)};
      border: 1px double ${palette('primary', 0)};
      color: #fff;

      &.CalendarDay--hovered-span {
        background: ${palette('primary', 0)};
        border: 1px double ${palette('primary', 0)};
      }

      &:active {
        background: ${palette('primary', 0)};
      }
    }

    .CalendarDay--selected-span {
      background: ${palette('primary', 7)};
      border: 1px double ${palette('primary', 7)};
      color: #fff;
    }

    .CalendarDay--hovered-span,
    .CalendarDay--after-hovered-start {
      background: ${palette('primary', 7)};
      border: 1px double ${palette('primary', 8)};
      color: #fff;

      &:active {
        background: ${palette('primary', 0)};
      }

      &.CalendarDay--hovered {
        background: ${palette('primary', 0)};
      }
    }

    .CalendarDay--selected-span.CalendarDay--hovered,
    .CalendarDay--selected-span:active {
      background: ${palette('primary', 0)};
      border: 1px double ${palette('primary', 0)};
    }

    .CalendarDay--selected-span.CalendarDay--last-in-range {
      border-right: ${palette('primary', 7)};
    }

    .DayPickerKeyboardShortcuts__show--bottom-right {
      border-top: 26px solid transparent;
      border-right: 33px solid ${palette('primary', 0)};
      bottom: 0;
      right: 0;
    }

    .DayPicker--horizontal {
      .DayPickerNavigation--horizontal {
        .DayPickerNavigation__prev,
        .DayPickerNavigation__next {
          -webkit-transform: ${props =>
            props['data-rtl'] === 'rtl' ? 'rotate(180deg)' : 'inherit'};
          -ms-transform: ${props =>
            props['data-rtl'] === 'rtl' ? 'rotate(180deg)' : 'inherit'};
          transform: ${props =>
            props['data-rtl'] === 'rtl' ? 'rotate(180deg)' : 'inherit'};
        }
      }
    }

    .DateRangePickerInput {
      .DateRangePickerInput__arrow {
        -webkit-transform: ${props =>
          props['data-rtl'] === 'rtl' ? 'rotate(180deg)' : 'inherit'};
        -ms-transform: ${props =>
          props['data-rtl'] === 'rtl' ? 'rotate(180deg)' : 'inherit'};
        transform: ${props =>
          props['data-rtl'] === 'rtl' ? 'rotate(180deg)' : 'inherit'};
      }
    }
  }
`;

const ReactDatesWrapper = WithDirection(ReactDateWrapper);

export { ReactDatesStyleWrapper, ReactDatesWrapper };
