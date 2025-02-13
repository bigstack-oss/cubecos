import React, { Component } from 'react';
import { Icon } from 'antd';
import Input from './uielements/input';

export default class extends Component {
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
      this.props.onChange(this.props.itemKey, this.state.value);
    }
  }
  edit() {
    this.setState({ editable: true });
  }

  render() {
    const { value, editable } = this.state;
    return (
      <div className="isoNoteContent">
        {editable ? (
          <div className="isoNoteEditWrapper">
            <Input
              type="textarea"
              rows={5}
              value={value}
              onChange={this.handleChange}
              onPressEnter={this.check}
            />
            <Icon
              type="check"
              className="isoNoteEditIcon"
              onClick={this.check}
            />
          </div>
        ) : (
          <p className="isoNoteTextWrapper" onClick={this.edit}>
            {value || ' '}
            <Icon type="edit" className="isoNoteEditIcon" />
          </p>
        )}
      </div>
    );
  }
}
