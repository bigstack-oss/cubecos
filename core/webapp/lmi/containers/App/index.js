import React, { Component } from 'react';
import {
  Form,
  Select,
  InputNumber,
  DatePicker,
  Switch,
  Slider,
  Button
} from 'antd';
import { connect } from 'react-redux';
import dynamic from 'next/dynamic';
import Helmet from 'react-helmet';
import styled from 'styled-components';
import { font, palette } from 'styled-theme';
import IntlMessages from '../../components/utility/intlMessages';
import Widgets from '../Widgets';

const Header = styled.h1`
  font-family: ${font('primary')};
  background-color: ${palette('secondary', 1, true)};
  color: ${palette('grayscale', 0, true)};
`;

const IButton = styled(Button)`
  background-color: ${palette('secondary', 0, true)};
  color: ${palette('grayscale', 0, true)};
`;

class App extends Component {
  login = () => {};
  render() {
    return (
      <div>
        <Helmet>
          <title>Home page</title>
        </Helmet>
        <Widgets />
        {/*<DynamicComponent />*/}
      </div>
    );
  }
}

export default connect(state => state)(App);
