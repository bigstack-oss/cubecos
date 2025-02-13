import React from 'react';
import clone from 'clone';

import Tag from '../../../components/uielements/tag';
import IntlMessages from '../../../components/utility/intlMessages';

const TAGCOLORS = {
  category: '#3FB8AF',
  tenant: '#7FC7AF',
  instance: '#DAD8A7',
  host: '#FF9E9D',
  family: '#FF3D7F',
  target: '#3CD8D3',
  service: '#555E7B',
  node: '#B7D968',
  nic: '#B576AD',
  driver: '#FDE47F',
  error: '#CF188D',
  udg: '#E04644',
}

const SEVCOLORS = {
  'I': '#39C783',
  'W': '#ffbf00',
  'E': '#FF5B58',
  'C': '#E42B56',
}

const SEVMSG = {
  'I': 'Info',
  'W': 'Warning',
  'E': 'Error',
  'C': 'Critical',
}

const TextCell = text => <span>{text}</span>;
const EventIdCell = eventid => <Tag key={eventid}>{eventid}</Tag>;
const SeverityCell = severity => <Tag color={SEVCOLORS[severity]} key={severity}>{SEVMSG[severity]}</Tag>;
const DateCell = date => <span>{date.toLocaleString()}</span>;
const MetaCell = metadata => (
  <span>
    {metadata && Object.keys(metadata).map(key => {
      return (<Tag color={TAGCOLORS[key]} key={key}>{key + ": " + metadata[key]}</Tag>);
    })}
  </span>
)

const renderCell = (object, type, key) => {
  const value = object[key];
  switch (type) {
    case 'SeverityCell':
      return SeverityCell(value);
    case 'EventIdCell':
      return EventIdCell(value);
    case 'DateCell':
      const ts = new Date(value / 1000000)
      return DateCell(ts);
    case 'MetaCell':
      return MetaCell(value);
    default:
      return TextCell(value);
  }
};

const columns = [
  {
    title: <IntlMessages id="logs.alert.title.severity" />,
    key: 'severity',
    width: '5%',
    render: object => renderCell(object, 'SeverityCell', 'severity')
  },
  {
    title: <IntlMessages id="logs.alert.title.eventid" />,
    key: 'eventid',
    width: '8%',
    render: object => renderCell(object, 'EventIdCell', 'eventid')
  },
  {
    title: <IntlMessages id="logs.alert.title.message" />,
    key: 'message',
    width: 300,
    render: object => renderCell(object, 'TextCell', 'message')
  },
  {
    title: <IntlMessages id="logs.alert.title.meta" />,
    key: 'metadata',
    width: 200,
    render: object => renderCell(object, 'MetaCell', 'metadata')
  },
  {
    title: <IntlMessages id="logs.alert.title.timestamp" />,
    key: 'date',
    width: 100,
    render: object => renderCell(object, 'DateCell', 'date')
  }
];

const tableTabs = {
  'admin' : [
    {
      title: 'System Events',
      value: 'system',
      columns: clone(columns)
    },
    {
      title: 'Host Alerts',
      value: 'host',
      columns: clone(columns)
    },
    {
      title: 'Instance Alerts',
      value: 'instance',
      columns: clone(columns)
    },
  ],
  '_member_' : [
    {
      title: 'Instance Alerts',
      value: 'instance',
      columns: clone(columns)
    },
  ]
};

export { columns, tableTabs };
