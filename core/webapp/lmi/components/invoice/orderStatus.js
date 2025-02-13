import React from 'react';
import {
  DropdownButtons,
  DropdownMenu,
  MenuItem
} from '../uielements/dropdown';

export default ({ value, onChange, orderStatusOptions }) => (
  <DropdownButtons
    overlay={
      <DropdownMenu onClick={val => onChange(orderStatusOptions[val.key])}>
        {orderStatusOptions.map((option, index) => (
          <MenuItem key={index}>{option}</MenuItem>
        ))}
      </DropdownMenu>
    }
  >
    {value}
  </DropdownButtons>
);
