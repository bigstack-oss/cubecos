import moment from 'moment';
const events = [
  {
    allDay: false,
    start: '2017-06-13T12:41:31.046Z',
    end: '2017-06-13T12:41:31.046Z'
  },
  {
    allDay: true,
    start: '2017-06-06T18:22:42.716Z',
    end: '2017-06-06T18:22:42.716Z'
  },
  {
    allDay: false,
    start: '2017-06-14T18:53:31.353Z',
    end: '2017-06-14T18:53:31.353Z'
  },
  {
    allDay: true,
    start: '2017-06-06T10:50:35.587Z',
    end: '2017-06-06T10:50:35.587Z'
  },
  {
    allDay: true,
    start: '2017-06-01T07:26:27.020Z',
    end: '2017-06-01T07:26:27.020Z'
  },
  {
    allDay: false,
    start: '2017-06-01T04:19:19.302Z',
    end: '2017-06-01T04:19:19.302Z'
  },
  {
    allDay: true,
    start: '2017-06-05T08:21:30.519Z',
    end: '2017-06-05T08:21:30.519Z'
  },
  {
    allDay: true,
    start: '2017-06-06T12:33:34.094Z',
    end: '2017-06-06T12:33:34.094Z'
  },
  {
    allDay: false,
    start: '2017-06-06T19:08:51.789Z',
    end: '2017-06-06T19:08:51.789Z'
  },
  {
    allDay: false,
    start: '2017-06-04T12:53:06.477Z',
    end: '2017-06-04T12:53:06.477Z'
  },
  {
    allDay: true,
    start: '2017-05-31T08:13:58.232Z',
    end: '2017-05-31T08:13:58.232Z'
  },
  {
    allDay: true,
    start: '2017-05-31T20:49:56.502Z',
    end: '2017-05-31T20:49:56.502Z'
  },
  {
    allDay: false,
    start: '2017-05-25T16:37:46.342Z',
    end: '2017-05-25T16:37:46.342Z'
  },
  {
    allDay: true,
    start: '2017-05-22T20:55:43.440Z',
    end: '2017-05-22T20:55:43.440Z'
  },
  {
    allDay: true,
    start: '2017-06-08T01:26:44.401Z',
    end: '2017-06-08T01:26:44.401Z'
  },
  {
    allDay: false,
    start: '2017-06-13T15:13:00.444Z',
    end: '2017-06-13T15:13:00.444Z'
  },
  {
    allDay: true,
    start: '2017-06-15T15:07:34.588Z',
    end: '2017-06-15T15:07:34.588Z'
  },
  {
    allDay: true,
    start: '2017-06-17T05:51:03.042Z',
    end: '2017-06-17T05:51:03.042Z'
  },
  {
    allDay: false,
    start: '2017-06-04T05:44:43.848Z',
    end: '2017-06-04T05:44:43.848Z'
  },
  {
    allDay: true,
    start: '2017-05-27T18:52:12.327Z',
    end: '2017-05-27T18:52:12.327Z'
  },
  {
    allDay: false,
    start: '2017-06-03T10:56:32.981Z',
    end: '2017-06-03T10:56:32.981Z'
  },
  {
    allDay: true,
    start: '2017-06-04T23:39:50.313Z',
    end: '2017-06-04T23:39:50.313Z'
  },
  {
    allDay: false,
    start: '2017-06-13T01:47:36.119Z',
    end: '2017-06-13T01:47:36.119Z'
  },
  {
    allDay: true,
    start: '2017-06-09T10:53:59.669Z',
    end: '2017-06-09T10:53:59.669Z'
  },
  {
    allDay: false,
    start: '2017-06-06T23:37:30.150Z',
    end: '2017-06-06T23:37:30.150Z'
  },
  {
    allDay: false,
    start: '2017-05-24T15:47:41.647Z',
    end: '2017-05-24T15:47:41.647Z'
  },
  {
    allDay: false,
    start: '2017-05-20T09:37:22.294Z',
    end: '2017-05-20T09:37:22.294Z'
  },
  {
    allDay: true,
    start: '2017-05-22T04:18:23.139Z',
    end: '2017-05-22T04:18:23.139Z'
  },
  {
    allDay: true,
    start: '2017-05-21T12:52:59.331Z',
    end: '2017-05-21T12:52:59.331Z'
  },
  {
    allDay: false,
    start: '2017-06-05T19:12:46.218Z',
    end: '2017-06-05T19:12:46.218Z'
  },
  {
    allDay: false,
    start: '2017-06-18T05:42:32.376Z',
    end: '2017-06-18T05:42:32.376Z'
  },
  {
    allDay: false,
    start: '2017-06-13T08:25:55.959Z',
    end: '2017-06-13T08:25:55.959Z'
  },
  {
    allDay: true,
    start: '2017-06-13T06:24:45.567Z',
    end: '2017-06-13T06:24:45.567Z'
  },
  {
    allDay: false,
    start: '2017-06-10T16:02:57.478Z',
    end: '2017-06-10T16:02:57.478Z'
  },
  {
    allDay: false,
    start: '2017-06-13T18:05:48.180Z',
    end: '2017-06-13T18:05:48.180Z'
  },
  {
    allDay: false,
    start: '2017-06-17T11:41:16.372Z',
    end: '2017-06-17T11:41:16.372Z'
  },
  {
    allDay: true,
    start: '2017-05-25T01:29:20.872Z',
    end: '2017-05-25T01:29:20.872Z'
  },
  {
    allDay: false,
    start: '2017-06-01T18:23:07.322Z',
    end: '2017-06-01T18:23:07.322Z'
  },
  {
    allDay: false,
    start: '2017-05-22T04:20:36.858Z',
    end: '2017-05-22T04:20:36.858Z'
  },
  {
    allDay: false,
    start: '2017-05-26T12:05:32.983Z',
    end: '2017-05-26T12:05:32.983Z'
  },
  {
    allDay: false,
    start: '2017-06-01T13:57:24.817Z',
    end: '2017-06-01T13:57:24.817Z'
  },
  {
    allDay: false,
    start: '2017-05-29T17:58:20.674Z',
    end: '2017-05-29T17:58:20.674Z'
  },
  {
    allDay: false,
    start: '2017-06-11T01:19:28.050Z',
    end: '2017-06-11T01:19:28.050Z'
  },
  {
    allDay: false,
    start: '2017-05-31T07:10:27.044Z',
    end: '2017-05-31T07:10:27.044Z'
  },
  {
    allDay: true,
    start: '2017-05-26T09:00:39.158Z',
    end: '2017-05-26T09:00:39.158Z'
  },
  {
    allDay: true,
    start: '2017-05-31T17:15:18.611Z',
    end: '2017-05-31T17:15:18.611Z'
  },
  {
    allDay: false,
    start: '2017-06-10T19:42:35.124Z',
    end: '2017-06-10T19:42:35.124Z'
  },
  {
    allDay: false,
    start: '2017-05-20T18:40:49.210Z',
    end: '2017-05-20T18:40:49.210Z'
  },
  {
    allDay: false,
    start: '2017-06-04T11:36:22.540Z',
    end: '2017-06-04T11:36:22.540Z'
  },
  {
    allDay: false,
    start: '2017-06-13T20:53:08.880Z',
    end: '2017-06-13T20:53:08.880Z'
  }
];

const datediff = new moment(new Date()).diff(
  new moment('2017-06-01T18:23:07.322Z'),
  'days'
);
events.forEach((event, index) => {
  events[index].id = `${index + 1}`;
  events[index].title = `Demo event ${index + 1}`;
  events[index].desc = `Desc of event ${index + 1}`;
  events[index].start = new moment(event.start).add(datediff, 'days').toDate();
  events[index].end = new moment(event.end).add(datediff, 'days').toDate();
});
export default events.splice(0, 10);
