import React, { Component } from 'react';
import TableWrapper from '../antTable.style';

export default class GroupView extends Component {
  render() {
    return (
      <TableWrapper
        columns={this.props.tableInfo.columns}
        dataSource={this.props.dataList.getAll()}
        className="isoGroupTable"
      />
    );
  }
}
