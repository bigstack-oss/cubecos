import Auth0Lock from 'auth0-lock';
import { Auth0Config } from '../../config';
import { notification } from '../../components';
import { setCookie, getCookie, removeCookie } from '../session';
import redirectTo from '../session';

class Auth0Helper {
  isValid = Auth0Config.clientID && Auth0Config.domain;
  lock = null;
  constructor() {
    this.login = this.login.bind(this);
  }
  login(handleLogin) {
    this.lock = this.isValid
      ? new Auth0Lock(
          Auth0Config.clientID,
          Auth0Config.domain,
          Auth0Config.options
        )
      : null;

    this.lock.on('authenticated', authResult => {
      if (authResult && authResult.accessToken) {
        setCookie('access_token', authResult.accessToken);
        handleLogin();
        return;
      }
    });
    this.lock.show();
  }
}
export default new Auth0Helper();
