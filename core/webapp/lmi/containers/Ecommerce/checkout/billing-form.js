import React, { Component } from 'react';
import Input from '../../../components/uielements/input';
import Select, { SelectOption } from '../../../components/uielements/select';
import Checkbox from '../../../components/uielements/checkbox';
import InputBox from './input-box';
import IntlMessages from '../../../components/utility/intlMessages';
import { BillingFormWrapper, InputBoxWrapper } from './checkout.style';

const Option = SelectOption;

export default class extends Component {
  handleOnChange = checkedValues => {};

  render() {
    return (
      <BillingFormWrapper className="isoBillingForm">
        <div className="isoInputFieldset">
          <InputBox
            label={<IntlMessages id="checkout.billingform.firstname" />}
            important
          />
          <InputBox
            label={<IntlMessages id="checkout.billingform.lastname" />}
            important
          />
        </div>

        <div className="isoInputFieldset">
          <InputBox
            label={<IntlMessages id="checkout.billingform.company" />}
          />
        </div>

        <div className="isoInputFieldset">
          <InputBox
            label={<IntlMessages id="checkout.billingform.email" />}
            important
          />
          <InputBox label={<IntlMessages id="checkout.billingform.mobile" />} />
        </div>

        <div className="isoInputFieldset">
          <InputBoxWrapper className="isoInputBox">
            <label>{<IntlMessages id="checkout.billingform.country" />}</label>
            <Select size="large" defaultValue="unitedstate">
              <Option value="argentina">Argentina</Option>
              <Option value="australia">Australia</Option>
              <Option value="brazil">Brazil</Option>
              <Option value="france">France</Option>
              <Option value="germany">Germany</Option>
              <Option value="southafrica">South Africa</Option>
              <Option value="spain">Spain</Option>
              <Option value="unitedstate">United State</Option>
              <Option value="unitedkingdom">United Kingdom</Option>
            </Select>
          </InputBoxWrapper>

          <InputBox label={<IntlMessages id="checkout.billingform.city" />} />
        </div>

        <div className="isoInputFieldset vertical">
          <InputBox
            label={<IntlMessages id="checkout.billingform.address" />}
            placeholder="Address"
          />
          <Input
            size="large"
            placeholder="Apartment, suite, unit etc. (optional)"
            style={{ marginTop: '35px' }}
          />
        </div>

        <Checkbox onChange={this.handleOnChange}>
          <IntlMessages id="checkout.billingform.checkbox" />
        </Checkbox>
      </BillingFormWrapper>
    );
  }
}
