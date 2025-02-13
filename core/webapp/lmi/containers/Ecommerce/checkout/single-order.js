import React, { Component } from 'react';

export default class extends Component {
  render() {
    const { price, quantity, name } = this.props;
    const totalPrice = (price * quantity).toFixed(2);
    const trimName = name.substring(0, 30);
    return (
      <div className="isoSingleOrderInfo">
        <p>
          <span>{trimName}</span>
          <span>x</span>
          <span className="isoQuantity">{quantity}</span>
        </p>
        <span className="totalPrice">${totalPrice}</span>
      </div>
    );
  }
}
