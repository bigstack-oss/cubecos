import React, { Component } from "react";
import Link from "next/link";
import { connect } from "react-redux";
import Input from "../../components/uielements/input";
import Checkbox from "../../components/uielements/checkbox";
import Button from "../../components/uielements/button";
import { jwtConfig } from "../../config";
import AuthAction from "../../redux/auth/actions";
import Auth0 from "../../helpers/auth0";
import Firebase from "../../helpers/firebase";
import FirebaseLogin from "../../components/firebase";
import IntlMessages from "../../components/utility/intlMessages";
import SignInStyleWrapper from "./signin.style";
const logo = "/static/image/cube_logo.png";

class SignIn extends Component {
  handleLogin = () => {
    const { login, history } = this.props;
    login(history);
  };

  handleJWTLogin = () => {
    const { jwtLogin, history } = this.props;
    const userInfo = {
      username: document.getElementById("inputUserName").value || "",
      password: document.getElementById("inpuPassword").value || ""
    };
    // jwtLogin(history, userInfo);
  };

  render() {
    const from = { pathname: "/dashboard" };
    const { isLoggedIn } = this.props;
    return (
      <SignInStyleWrapper className="isoSignInPage">
        <div className="isoLoginContentWrapper">
          <div className="isoLoginContent">
            <div className="isoLogoWrapper">
              <Link href="/dashboard" style={{justifyContent: 'flex-start', marginBottom: '25px'}}>
                <img alt="user" src={logo} width="200" height="66" fetchpriority="high" />
              </Link>
            </div>

            <div className="isoSignInForm">
              <div className="isoInputWrapper">
                <Input
                  id="inputUserName"
                  size="large"
                  placeholder="Username"
                />
              </div>

              <div className="isoInputWrapper">
                <Input
                  id="inpuPassword"
                  size="large"
                  type="password"
                  placeholder="Password"
                />
              </div>

              <div className="isoInputWrapper isoLeftRightComponent">
                <Checkbox>
                  <IntlMessages id="signin.remember" />
                </Checkbox>
                <Button
                  type="primary"
                  onClick={
                    jwtConfig.enabled ? this.handleJWTLogin : this.handleLogin
                  }
                >
                  <IntlMessages id="signin.signin" />
                </Button>
              </div>

              <p className="isoHelperText">
                <IntlMessages id="signin.tips" />
              </p>

            </div>
          </div>
        </div>
      </SignInStyleWrapper>
    );
  }
}

export default connect(
  state => ({
    state
  }),
  { ...AuthAction }
)(SignIn);
