import React, { Component } from 'react';
import Input from '../../../components/uielements/input';
import { InputBoxWrapper } from './checkout.style';

export default class extends Component {
  render() {
    const { label, placeholder } = this.props;
    return (
      <InputBoxWrapper className="isoInputBox">
        <label>
          {label}
          {this.props.important ? <span className="asterisk">*</span> : null}
        </label>
        <Input size="large" placeholder={placeholder} />
      </InputBoxWrapper>
    );
  }
}
