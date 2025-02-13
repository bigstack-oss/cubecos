import clone from 'clone';
const defaultOptions = [
  {
    id: 'disabled',
    title: 'Disabled',
    trueValue: true,
    falseValue: false,
    value: false
  },
  {
    id: 'showDefaultInputIcon',
    title: 'Show Defaut Icon',
    trueValue: true,
    falseValue: false,
    value: false
  },
  {
    id: 'isRTL',
    title: 'Enable RTL',
    trueValue: true,
    falseValue: false,
    value: false
  },
  {
    id: 'numberOfMonths',
    title: 'Single Month Enable',
    trueValue: 1,
    falseValue: 2,
    value: 2
  },
  {
    id: 'enableOutsideDays',
    title: 'Enable Outside Days',
    trueValue: true,
    falseValue: false,
    value: false
  },
  {
    id: 'keepOpenOnDateSelect',
    title: 'Keep Open On Date Select',
    trueValue: true,
    falseValue: false,
    value: false
  }
];
const configs = [
  {
    id: 'SingleDatePicker',
    title: 'Single Date Picker',
    options: [
      ...clone(defaultOptions),
      {
        id: 'placeholder',
        title: 'Custom Placeholder',
        trueValue: 'Custom Date',
        falseValue: undefined,
        value: undefined
      }
    ]
  },
  {
    id: 'DateRangePicker',
    title: 'Date Range Picker',
    options: [
      ...clone(defaultOptions),
      {
        id: 'startDatePlaceholderText',
        title: 'Custom Start',
        trueValue: 'C start',
        falseValue: undefined,
        value: undefined
      },
      {
        id: 'endDatePlaceholderText',
        title: 'C end',
        trueValue: 'Custom Date',
        falseValue: undefined,
        value: undefined
      }
    ]
  }
];
export default configs;
