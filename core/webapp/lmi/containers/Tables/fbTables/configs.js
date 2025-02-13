const cells = [
  {
    header: '',
    col: 'avatar',
    width: 50,
    coulumnType: 'image',
  },
  {
    header: 'First Name',
    col: 'firstName',
    width: 100,
    coulumnType: 'link',
  },
  {
    header: 'Last Name',
    col: 'lastName',
    width: 100,
    coulumnType: 'link',
  },
  {
    header: 'City',
    col: 'city',
    width: 100,
    coulumnType: 'text',
  },
  {
    header: 'Street',
    col: 'street',
    width: 200,
    coulumnType: 'text',
  },
  {
    header: 'Zip Code',
    col: 'zipCode',
    width: 200,
    coulumnType: 'text',
  },
  {
    header: 'Email',
    col: 'email',
    width: 200,
    coulumnType: 'link',
  },
  {
    header: 'DOB',
    col: 'date',
    width: 200,
    coulumnType: 'data',
  },
];
const smallCells = [
  cells[1],
  cells[2],
  cells[3],
  cells[4],
];
const tableinfos = [
  {
    title:'Simple',
    value:'simple',
    cells, 
  },
  {
    title:'Fluid Column Widths',
    value:'fluidColumnWidths',
    cells: [
      { ...smallCells[0], flexGrow: 2 },
      { ...smallCells[1], flexGrow: 3 },
      { ...smallCells[2], flexGrow: 4 },
      { ...smallCells[3], flexGrow: 2 },
    ], 
  },
  {
    title:'Resizable',
    value:'resizable',
    cells: smallCells,
    resizable: true,
  },
  {
    title:'Hide Columns',
    value:'hideColumns',
    cells: cells,
    hideColumns: true,
  },
  {
    title:'Sortable',
    value:'sortable',
    cells: smallCells,
    sortable: true,
  },
  {
    title:'Search Text',
    value:'searchText',
    cells: cells, 
    searchText: true,
  },
  {
    title:'column Groups',
    value:'columnGroup',
    cells: smallCells,
  },
  {
    title:'Reorder Columns',
    value:'reorderable',
    cells: smallCells, 
    reorderable: true,
  },
];
export default tableinfos;