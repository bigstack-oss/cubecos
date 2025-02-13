import React, { Component } from 'react';
import IntlMessages from '../utility/intlMessages';
import MailComposeBtnWrapper from './mailComposeBtn.style';

export default class extends Component {
  render() {
    return (
      <MailComposeBtnWrapper className="isoComposeBtnWrapper">
        <button
          type="button"
          onClick={event => {
            this.props.changeComposeMail(true);
            if (this.props.onDrawerClose) {
              this.props.onDrawerClose();
            }
          }}
        >
          <IntlMessages id="email.compose" />
        </button>
      </MailComposeBtnWrapper>
    );
  }
}
