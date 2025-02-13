import React, { Component } from 'react';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import Box from '../../../components/utility/box';
import BillingForm from './billing-form';
import OrderInfo from './order-info';
import { CheckoutContents } from './checkout.style';

export default class extends Component {
  render() {
    return (
      <CheckoutContents>
        <LayoutWrapper className="isoCheckoutPage">
          <Box>
            <div className="isoBillingAddressWrapper">
              <h3 className="isoSectionTitle">Billing details</h3>
              <div className="isoBillingSection">
                <BillingForm />
                <OrderInfo />
              </div>
            </div>
          </Box>
        </LayoutWrapper>
      </CheckoutContents>
    );
  }
}
