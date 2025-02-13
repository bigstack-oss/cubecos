import React, { Component } from 'react';
import InputNumber from '../../../components/uielements/InputNumber';

export default class extends Component {
  onChange = value => {};
  render() {
    return <InputNumber min={0} max={10} step={0.1} onChange={this.onChange} />;
  }
}
