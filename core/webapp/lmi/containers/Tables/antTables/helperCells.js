import React, { Component } from 'react';
import ImageCellView from './imageCell';
import { Icon, Input, Popconfirm } from 'antd';

const DateCell = data => <p>{data.toLocaleString()}</p>;
const ImageCell = src => <ImageCellView src={src} />;
const LinkCell = (link, href) => <a href={href ? href : '#'}>{link}</a>;
const TextCell = text => <p>{text}</p>;

class EditableCell extends Component {
  constructor(props) {
    super(props);
    this.handleChange = this.handleChange.bind(this);
    this.check = this.check.bind(this);
    this.edit = this.edit.bind(this);
    this.state = {
      value: this.props.value,
      editable: false,
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
        this.props.index,
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
        {editable
          ? <div className="isoEditDataWrapper">
              <Input
                value={value}
                onChange={this.handleChange}
                onPressEnter={this.check}
              />
              <Icon type="check" className="isoEditIcon" onClick={this.check} />
            </div>
          : <p className="isoDataWrapper">
              {value || ' '}
              <Icon type="edit" className="isoEditIcon" onClick={this.edit} />
            </p>}
      </div>
    );
  }
}
class DeleteCell extends Component {
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

export { DateCell, ImageCell, LinkCell, TextCell, EditableCell, DeleteCell };
