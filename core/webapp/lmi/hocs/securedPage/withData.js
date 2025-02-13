
import React, { Component } from 'react';
import redirect from '../../helpers/redirect';
import { getCookie } from '../../helpers/session';

import 'isomorphic-fetch';

export default ComposedComponent =>
  class WithData extends Component {
    static async getInitialProps(context) {
      const isLoggedIn = getCookie('connect.sid', context.req) ? true : false;
      if (context.req && !isLoggedIn) {
        // redirect only on server side rendering
        redirect(context, '/login');
      }
      return { isLoggedIn };
    }
    render() {
      return <ComposedComponent {...this.props} />;
    }
  };
