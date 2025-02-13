import React from 'react';
import Link from 'next/link';
import Input from '../../components/uielements/input';
import Button from '../../components/uielements/button';
import IntlMessages from '../../components/utility/intlMessages';
import ResetPasswordStyleWrapper from './resetPassword.style';

class ResetPassword extends React.Component {
  render() {
    return (
      <ResetPasswordStyleWrapper className="isoResetPassPage">
        <div className="isoFormContentWrapper">
          <div className="isoFormContent">
            <div className="isoLogoWrapper">
              <Link to="/dashboard">
                <span className="isoMenuHolder">
                  <span className="nav-text">                 
                    <IntlMessages id="page.resetPassTitle" />
                  </span>
                </span>                  
              </Link>
            </div>

            <div className="isoFormHeadText">
              <h3>
                <IntlMessages id="page.resetPassSubTitle" />
              </h3>
              <p>
                <IntlMessages id="page.resetPassDescription" />
              </p>
            </div>

            <div className="isoResetPassForm">
              <div className="isoInputWrapper">
                <Input
                  size="large"
                  type="password"
                  placeholder="New Password"
                />
              </div>

              <div className="isoInputWrapper">
                <Input
                  size="large"
                  type="password"
                  placeholder="Confirm Password"
                />
              </div>

              <div className="isoInputWrapper">
                <Button type="primary">
                  <IntlMessages id="page.resetPassSave" />
                </Button>
              </div>
            </div>
          </div>
        </div>
      </ResetPasswordStyleWrapper>
    );
  }
}

export default ResetPassword;
