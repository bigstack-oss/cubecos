import React, { Component } from 'react';
import BigCalendar from 'react-big-calendar';
import moment from 'moment';
import HTML5Backend from 'react-dnd-html5-backend';
import { DragDropContext } from 'react-dnd';
import withDragAndDrop from 'react-big-calendar/lib/addons/dragAndDrop';

BigCalendar.momentLocalizer(moment);
const Calendar = withDragAndDrop(BigCalendar);

function EventAgenda({ event }) {
  return (
    <span>
      <em style={{ color: 'magenta' }}>{event.title}</em>
      <p>{event.desc}</p>
    </span>
  );
}

class FullCalender extends Component {
  render() {
    const calendarOptions = {
      popup: true,
      selectable: true,
      step: 60,
      timeslots: 2,
      className: 'isomorphicCalendar',
      agenda: {
        event: EventAgenda
      }
    };
    return <Calendar {...calendarOptions} {...this.props} />;
  }
}
const CalendarExample = DragDropContext(HTML5Backend)(FullCalender);
export default CalendarExample;
