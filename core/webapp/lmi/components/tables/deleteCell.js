import React, { Component } from 'react';
import Popconfirm from '../feedback/popconfirm';

export default class extends Component {
  render() {
    const { index, onDeleteCell } = this.props;
    return (
      <Popconfirm
        title="Sure to delete?"
        okText="DELETE"
        cancelText="No"
        onConfirm={() => onDeleteCell(index)}
      >
        <a>Delete</a>
      </Popconfirm>
    );
  }
}
