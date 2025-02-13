import React, { Component } from 'react';
import { InputSearch } from '../uielements/input';
export default class extends Component {
  componentDidMount() {
    setTimeout(() => {
      try {
        document.getElementById('InputTopbarSearch').focus();
      } catch (e) {}
    }, 200);
  }
  render() {
    return (
      <InputSearch
        id="InputTopbarSearch"
        size="large"
        placeholder="Enter search text"
        onBlur={this.props.onBlur}
      />
    );
  }
}
