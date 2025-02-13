const calendarActions = {
  CALENDAR_VIEW: 'CALENDAR_VIEW',
  CALENDAR_EVENTS: 'CALENDAR_EVENTS',
  changeView: view => ({
    type: calendarActions.CALENDAR_VIEW,
    view
  }),
  changeEvents: events => ({
    type: calendarActions.CALENDAR_EVENTS,
    events
  })
};
export default calendarActions;
