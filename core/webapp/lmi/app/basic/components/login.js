// basic/components/alert.js

import React, { forwardRef } from 'react';
import { injectIntl } from 'react-intl';

import * as c from '../constant';

import Link from 'next/link';

import Form from '../../../components/uielements/form';
import Select, { SelectOption } from '../../../components/uielements/select';
import Input from '../../../components/uielements/input';
import Button from '../../../components/uielements/button';
import IntlMessages from '../../../components/utility/intlMessages';

import LoginStyleWrapper from './login.style';

const Logo = '/static/image/cube_logo.png';
const FormItem = Form.Item;

const SelectDomain = forwardRef(({ size, value = {}, onChange }, ref) => (
  <Select id='domain' size={size} onChange={onChange} style={{ width: '315px' }} >
    <SelectOption value='default'>Default</SelectOption>
  </Select>
));

const SelectTenant = forwardRef(({ size, value = {}, onChange }, ref) => (
  <Select id='tenant' size={size} onChange={onChange} style={{ width: '315px' }} >
    <SelectOption value='admin'>Admin</SelectOption>
  </Select>
));

const Login = () => {
  return(
    <LoginStyleWrapper className='isoSignInPage'>
      <div className='isoLoginContentWrapper'>
        <div className='isoLoginContent'>
          <div className='isoLogoWrapper' style={{justifyContent: 'flex-start', marginBottom: '25px'}}>
            <img alt='Cube' src={Logo} width="160px" height="auto" fetchpriority="high" />
          </div>
          <p>{window.env.LOGIN_GREETING}</p>
          <div className='isoLoginForm'>
              <div className='isoInputWrapper isoLeftRightComponent'>
                <p className='isoHelperText'>
                  <IntlMessages id='login.tips' />
                </p>
              </div>
              <div>
                <a href={`${window.cluster['local'].API_URL}/v1/auth/connect`}>
                  <Button type='primary' onClick=''>
                    <IntlMessages id='login.signin' />
                  </Button>
                </a>
              </div>
          </div>
        </div>
      </div>
    </LoginStyleWrapper>
  )
}

export default Form.create()(injectIntl(Login));