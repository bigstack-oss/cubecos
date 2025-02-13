import React, { Component } from 'react';
import clone from 'clone';
import TableWrapper from '../antTable.style';
import { EditableCell, DeleteCell } from '../helperCells';

export default class CustomizedView extends Component {
  constructor(props) {
    super(props);
    this.onCellChange = this.onCellChange.bind(this);
    this.onDeleteCell = this.onDeleteCell.bind(this);
    this.state = {
      columns: this.createcolumns(clone(this.props.tableInfo.columns)),
      dataList: this.props.dataList.getAll(),
    };
  }
  createcolumns(columns) {
    const editColumnRender = (text, record, index) =>
      <EditableCell
        index={index}
        columnsKey={columns[0].key}
        value={text[columns[0].key]}
        onChange={this.onCellChange}
      />;
    columns[0].render = editColumnRender;
    const deleteColumn = {
      title: 'operation',
      dataIndex: 'operation',
      render: (text, record, index) =>
        <DeleteCell index={index} onDeleteCell={this.onDeleteCell} />,
    };
    columns.push(deleteColumn);
    return columns;
  }
  onCellChange(value, columnsKey, index) {
    const { dataList } = this.state;
    dataList[index][columnsKey] = value;
    this.setState({ dataList });
  }
  onDeleteCell = index => {
    const { dataList } = this.state;
    dataList.splice(index, 1);
    this.setState({ dataList });
  };
  render() {
    const { columns, dataList } = this.state;

    return (
      <TableWrapper
        columns={columns}
        dataSource={dataList}
        className="isoEditableTable"
      />
    );
  }
}
