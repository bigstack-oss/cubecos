import { DateCell, LinkCell, TextCell } from './helperCells';
import clone from 'clone';
const renderCell = (object, type, key) => {
  const value = object[key];
  switch(type) {
    case 'DateCell': return DateCell(value);
    case 'LinkCell': return LinkCell(value);
    default: return TextCell(value);
  }
}

const columns = [
  {
    title: 'First Name',
    key: 'firstName',
    width: 100,
    render: object => renderCell(object, 'TextCell', 'firstName'),
  },
  {
    title: 'Last Name',
    key: 'lastName',
    width: 100,
    render: object => renderCell(object, 'TextCell', 'lastName'),
  },
  {
    title: 'City',
    key: 'city',
    width: 100,
    render: object => renderCell(object, 'TextCell', 'city'),
  },
  {
    title: 'Street',
    key: 'street',
    width: 200,
    render: object => renderCell(object, 'TextCell', 'street'),
  },
  {
    title: 'Email',
    key: 'email',
    width: 200,
    render: object => renderCell(object, 'LinkCell', 'email'),
  },
  {
    title: 'DOB',
    key: 'date',
    width: 200,
    render: object => renderCell(object, 'DateCell', 'date'),
  },
];
const smallColumns = [
  columns[1],
  columns[2],
  columns[3],
  columns[4],
];
const sortColumns = [
  { ...columns[1], sorter: true, },
  { ...columns[2], sorter: true, },
  { ...columns[3], sorter: true, },
  { ...columns[4], sorter: true, },
];
const editColumns = [
  { ...columns[1], width: 300, },
  columns[2],
  columns[3],
  columns[4],
];
const groupColumns = [
  columns[0],
  {
    title: 'Name',
    children: [
      columns[1],
      columns[2],
    ],
  },
  {
    title: 'Address',
    children: [
      columns[3],
      columns[4],
    ],
  },
];
const tableinfos = [
  {
    title:'Simple Table',
    value:'simple',
    columns: clone(smallColumns),
  },
  {
    title:'Sortable Table',
    value:'sortView',
    columns: clone(sortColumns),
  },
  {
    title:'Search Text',
    value:'filterView',
    columns: clone(smallColumns),
  },
  {
    title:'Editable View',
    value:'editView',
    columns: clone(editColumns),
  },
  {
    title:'Grouping View',
    value:'groupView',
    columns: clone(groupColumns),
  },
  {
    title:'Customized View',
    value:'customizedView',
    columns: clone(columns),
  },

]
export {
  columns,
  tableinfos,
}
