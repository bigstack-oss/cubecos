import React from 'react';
import Countdown from 'react-count-down';
import Input from '../../components/uielements/input';
import Button from '../../components/uielements/button';
import Image from '../../image/rob.png';
import IntlMessages from '../../components/utility/intlMessages';
import FourZeroFourStyleWrapper from './404.style';

const validateEmail = email => {
  const regax = /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/;
  return regax.test(email);
};

class FourZeroFour extends React.Component {
  state = {
    email: '',
    disabled: true
  };
  render() {
    const options = {
      endDate: '03/01/2019 10:55 AM',
      prefix: 'until my birthday!'
    };
    const { email, disabled } = this.state;
    const onChange = event => {
      const value = event.target.value;
      this.setState({ disabled: !validateEmail(value), email: value });
    };
    return (
      <FourZeroFourStyleWrapper className="iso404Page">
        <div className="iso404Content">
          <h1>Hey! Thank you for checking out our app.</h1>
          <h3>
            It’s not quite ready yet, but we are working hard and it will be
            ready in approximately:
          </h3>
          <Countdown options={options} />
          <h3>
            If you would like to be notified when the app is ready, you can
            subscribe to our e-mail list.
          </h3>
          <p>
            <IntlMessages id="page404.description" />
          </p>
          <Input value={email} onChange={onChange} />
          <Button type="button" disabled={disabled}>
            SUBSCRIBE
          </Button>
        </div>

        <div className="iso404Artwork">
          <img alt="#" src={Image} />
        </div>
      </FourZeroFourStyleWrapper>
    );
  }
}

export default FourZeroFour;
