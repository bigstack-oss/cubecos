
import React, { Component } from 'react';

export default ComposedComponent =>
  class WithData extends Component {
    render() {
      return <ComposedComponent {...this.props} />;
    }
  };
