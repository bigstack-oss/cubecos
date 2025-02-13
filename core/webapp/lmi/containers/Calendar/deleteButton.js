import React, { Component } from 'react';
import Popconfirm from '../../components/feedback/popconfirm';
import Button from '../../components/uielements/button';
import { notification } from '../../components/';

export default class extends Component {
  render() {
    const { handleDelete } = this.props;

    return (
      <Popconfirm
        title="Sure to delete the event?"
        okText="DELETE"
        cancelText="No"
        onConfirm={() => {
          notification('error', 'Deleted', '');
          handleDelete();
        }}
      >
        <Button icon="close" type="button" className="isoDeleteBtn" />
      </Popconfirm>
    );
  }
}
