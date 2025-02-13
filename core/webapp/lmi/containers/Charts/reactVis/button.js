import React, { Component } from 'react';
import IsoButton from '../../../components/uielements/button';

export default class extends Component {
  render() {
    const { buttonContent, onClick } = this.props;
    return (
      <IsoButton size="small" onClick={onClick}>
        {buttonContent}
      </IsoButton>
    );
  }
}
