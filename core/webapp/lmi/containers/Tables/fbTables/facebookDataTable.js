import React, { Component } from 'react';
import { Table, Cell, Column, ColumnGroup } from 'fixed-data-table-2';
import Button from '../../../components/uielements/button';
import { InputSearch } from '../../../components/uielements/input';
import filterListWrapper from './filterListWrapper';
import * as helperCells from './helperCells.js';

import 'fixed-data-table-2/dist/fixed-data-table.min.css';

const SortTypes = {
  ASC: 'ASC',
  DESC: 'DESC'
};

export default class FacebookDataTable extends Component {
  constructor(props) {
    super(props);
    this.createHeader = this.createHeader.bind(this);
    this.columnGroup = this.columnGroup.bind(this);
    this.cellViews = this.cellViews.bind(this);
    this.resetColumns = this.resetColumns.bind(this);
    this.resizeColumns = this.resizeColumns.bind(this);
    this.reOrderColumns = this.reOrderColumns.bind(this);
    this.searchText = this.searchText.bind(this);
    this.filterDataList = this.filterDataList.bind(this);
    const { dataList, tableInfo } = props;
    this.state = {
      fullDatalist: dataList,
      dataList,
      columnOrders: tableInfo.cells.map(cell => cell.col),
      allColumns: tableInfo.cells.map(cell => cell.col),
      columnWidths: {},
      colSortDirs: {},
      searchText: ''
    };
  }
  createHeader(cellInfo) {
    const { tableInfo } = this.props;
    const { colSortDirs } = this.state;
    const { header } = cellInfo;
    let headerCell;
    const hideColumns = tableInfo.hideColumns;
    const isSortable = tableInfo.sortable;
    if (hideColumns) {
      const handleColumnHide = id => {
        let newColumnOrders = this.state.columnOrders.filter(
          column => column !== cellInfo.col
        );
        this.setState({ columnOrders: newColumnOrders });
      };
      headerCell = (
        <helperCells.RemovableHeaderCell callback={handleColumnHide}>
          {cellInfo.header}
        </helperCells.RemovableHeaderCell>
      );
    } else if (isSortable) {
      let sortDir = colSortDirs[cellInfo.col];
      const sortChange = () => {
        if (sortDir === SortTypes.ASC) {
          sortDir = SortTypes.DESC;
        } else {
          sortDir = SortTypes.ASC;
        }
        this.setState({
          colSortDirs: {
            [cellInfo.col]: sortDir
          }
        });
      };
      headerCell = (
        <helperCells.SortHeaderCell
          sortChange={sortChange}
          sortTypes={SortTypes}
          sortDir={sortDir}
        >
          {cellInfo.header}
        </helperCells.SortHeaderCell>
      );
    } else if (header) {
      headerCell = <Cell>{header}</Cell>;
    } else {
      headerCell = '';
    }
    return headerCell;
  }
  columnGroup(dataList, columnGroupName, index) {
    const { allColumns } = this.state;
    return (
      <ColumnGroup key={index} header={<Cell>{columnGroupName}</Cell>}>
        {this.cellViews(allColumns[index * 2 + 0], dataList)}
        {this.cellViews(allColumns[index * 2 + 1], dataList)}
      </ColumnGroup>
    );
  }
  cellViews(collumnName, dataList) {
    const { tableInfo } = this.props;
    const { columnWidths } = this.state;
    const isResizable = tableInfo.resizable;
    const cellInfo = this.props.tableInfo.cells.filter(
      cell => cell.col === collumnName
    )[0];
    const width = columnWidths[cellInfo.col]
      ? columnWidths[cellInfo.col]
      : cellInfo.width;
    let ComponentCell;
    switch (cellInfo.coulumnType) {
      case 'data':
        ComponentCell = helperCells.DateCell;
        break;
      case 'image':
        ComponentCell = helperCells.ImageCell;
        break;
      case 'link':
        ComponentCell = helperCells.LinkCell;
        break;
      default:
        ComponentCell = helperCells.TextCell;
    }
    const { col, flexGrow, fixed } = cellInfo;
    return (
      <Column
        key={col}
        columnKey={col}
        header={this.createHeader(cellInfo)}
        cell={<ComponentCell data={dataList} col={col} />}
        width={width}
        isReorderable={tableInfo.reorderable}
        allowCellsRecycling={tableInfo.reorderable}
        flexGrow={flexGrow ? flexGrow : undefined}
        fixed={fixed === true}
        isResizable={isResizable}
      />
    );
  }
  resetColumns() {
    this.setState({ columnOrders: this.state.allColumns });
  }
  resizeColumns(newColumnWidth, columnKey) {
    this.setState(({ columnWidths }) => ({
      columnWidths: {
        ...columnWidths,
        [columnKey]: newColumnWidth
      }
    }));
  }
  reOrderColumns(event) {
    const columnOrders = this.state.columnOrders.filter(
      columnKey => columnKey !== event.reorderColumn
    );
    if (event.columnAfter) {
      const index = columnOrders.indexOf(event.columnAfter);
      columnOrders.splice(index, 0, event.reorderColumn);
    } else {
      columnOrders.push(event.reorderColumn);
    }
    this.setState({ columnOrders });
  }
  searchText(event) {
    this.setState({ searchText: event.target.value });
  }
  filterSearchText(columnName, searchText, datas) {
    searchText = searchText.toLowerCase();
    let filterIndex = [];
    datas.forEach((data, index) => {
      if (data[columnName].toLowerCase().includes(searchText)) {
        filterIndex.push(index);
      }
    });
    return filterIndex;
  }
  filterDataList() {
    const { colSortDirs, searchText, allColumns, dataList } = this.state;
    if (Object.keys(colSortDirs).length === 1) {
      const sortKey = Object.keys(colSortDirs)[0];
      if (colSortDirs[sortKey] === SortTypes.ASC) {
        dataList.getSortAsc(sortKey);
      } else {
        dataList.getSortDesc(sortKey);
      }
    } else if (searchText) {
      const filteredIndexes = this.filterSearchText(
        allColumns[1],
        searchText,
        dataList.datas
      );
      return new filterListWrapper(filteredIndexes, dataList);
    }
    return dataList;
  }
  render() {
    const { tableInfo } = this.props;
    const value = tableInfo.value;
    const filterdataList = this.filterDataList();
    const columnOrders = this.state.columnOrders;
    const columnGroupNames = ['Name', 'Address'];
    return (
      <div>
        {tableInfo.hideColumns ? (
          <Button type="primary" onClick={this.resetColumns}>
            Reset
          </Button>
        ) : (
          ''
        )}
        {tableInfo.searchText ? (
          <InputSearch
            placeholder="search first name"
            onChange={this.searchText}
          />
        ) : (
          ''
        )}
        <Table
          rowHeight={50}
          isColumnResizing={false}
          headerHeight={50}
          rowsCount={filterdataList.getSize()}
          onColumnResizeEndCallback={
            tableInfo.resizable ? this.resizeColumns : undefined
          }
          onColumnReorderEndCallback={
            tableInfo.reorderable ? this.reOrderColumns : undefined
          }
          width={1000}
          height={500}
          groupHeaderHeight={50}
          renderPage={false}
        >
          {value === 'columnGroup' ? (
            columnGroupNames.map((columnGroupName, index) =>
              this.columnGroup(filterdataList, columnGroupName, index)
            )
          ) : (
            columnOrders.map(columnOrder =>
              this.cellViews(columnOrder, filterdataList)
            )
          )}
        </Table>
      </div>
    );
  }
}
