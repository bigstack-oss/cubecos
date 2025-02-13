import React, { Component } from 'react';
import Button from '../uielements/button';
import Input from '../uielements/input';
import Modal from '../feedback/modal';
import { notification } from '../index';
import Firebase from '../../helpers/firebase/index';

export default class extends Component {
  state = {
    visible: false,
    email: 'demo@gmail.com',
    password: 'demodemo',
    confirmLoading: false
  };
  showModal = () => {
    this.setState({
      visible: true
    });
  };
  handleCancel = e => {
    this.setState({
      visible: false
    });
  };
  handleLogin = () => {
    const { email, password } = this.state;
    if (!(email && password)) {
      notification('error', 'Please fill in email. and password');
      return;
    }
    this.setState({
      confirmLoading: true
    });
    const self = this;
    let isError = false;
    Firebase.login(Firebase.EMAIL, { email, password })
      .catch(result => {
        const message =
          result && result.message ? result.message : 'Sorry Some error occurs';
        notification('error', message);
        self.setState({
          confirmLoading: false
        });
        isError = true;
      })
      .then(result => {
        if (isError) {
          return;
        }
        if (!result || result.message) {
          const message =
            result && result.message
              ? result.message
              : 'Sorry Some error occurs';
          notification('error', message);
          self.setState({
            confirmLoading: false
          });
        } else {
          self.setState({
            visible: false,
            confirmLoading: false
          });
          this.props.login();
        }
      });
  };
  resetPassword = () => {
    const { email } = this.state;
    if (!email) {
      notification('error', `Please fill in email.`);
      return;
    }
    Firebase.resetPassword(email)
      .then(() =>
        notification('success', `Password reset email sent to ${email}.`)
      )
      .catch(error => notification('error', 'Email address not found.'));
  };
  render() {
    return (
      <div>
        <Button type="primary" onClick={this.showModal} className="btnFirebase">
          {this.props.signup ? (
            'Sign up with Firebase'
          ) : (
            'Sign in with Firebase'
          )}
        </Button>
        <Modal
          title="Sign in with Firebase"
          visible={this.state.visible}
          confirmLoading={this.state.confirmLoading}
          onCancel={this.handleCancel}
          onOk={this.handleLogin}
          className="isoFirebaseLoginModal"
          cancelText="Cancel"
          okText="Login"
        >
          <form>
            <div className="isoInputWrapper">
              <label>Email</label>
              <Input
                size="large"
                placeholder="Email"
                value={this.state.email}
                onChange={event => {
                  this.setState({ email: event.target.value });
                }}
              />
            </div>
            <div className="isoInputWrapper" style={{ marginBottom: 10 }}>
              <label>Password</label>
              <Input
                type="password"
                size="large"
                placeholder="Password"
                value={this.state.password}
                onChange={event => {
                  this.setState({ password: event.target.value });
                }}
              />
            </div>
            <span className="isoResetPass" onClick={this.resetPassword}>
              Reset Password
            </span>
          </form>
        </Modal>
      </div>
    );
  }
}
