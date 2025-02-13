import React, { Component } from 'react';
import { Icon } from 'antd';
import Popconfirm from '../../../components/feedback/popconfirm';
import Input from '../../../components/uielements/input';

class EditableCell extends Component {
  constructor(props) {
    super(props);
    this.handleChange = this.handleChange.bind(this);
    this.check = this.check.bind(this);
    this.edit = this.edit.bind(this);
    this.state = {
      value: this.props.value,
      editable: false
    };
  }
  handleChange(event) {
    const value = event.target.value;
    this.setState({ value });
  }
  check() {
    this.setState({ editable: false });
    if (this.props.onChange) {
      this.props.onChange(
        this.state.value,
        this.props.columnsKey,
        this.props.index
      );
    }
  }
  edit() {
    this.setState({ editable: true });
  }
  render() {
    const { value, editable } = this.state;
    return (
      <div className="isoEditData">
        {editable ? (
          <div className="isoEditDataWrapper">
            <Input
              value={value}
              onChange={this.handleChange}
              onPressEnter={this.check}
            />
            <Icon type="check" className="isoEditIcon" onClick={this.check} />
          </div>
        ) : (
          <p className="isoDataWrapper">
            {value || ' '}
            <Icon type="edit" className="isoEditIcon" onClick={this.edit} />
          </p>
        )}
      </div>
    );
  }
}
