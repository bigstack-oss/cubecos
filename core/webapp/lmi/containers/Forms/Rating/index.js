import React, { Component } from 'react';
import Rate from '../../../components/uielements/rate';

export default class extends Component {
  state = {
    value: 3,
    count: null
  };
  handleChange = value => {
    this.setState({ value });
  };
  render() {
    const { value } = this.state;
    return (
      <span>
        <Rate onChange={this.handleChange} value={value} />
        {value && <span className="ant-rate-text">{value} stars</span>}
      </span>
    );
  }
}
