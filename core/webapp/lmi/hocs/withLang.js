import React, { Component } from 'react';
import { LocaleProvider } from 'antd';
import { IntlProvider } from 'react-intl';
import AppLocale from '../languageProvider';
import config, {
  getCurrentLanguage
} from '../containers/LanguageSwitcher/config';

const currentAppLocale = AppLocale[getCurrentLanguage(config.defaultLanguage || 'english').locale];

export default ComposedComponent => props => (
  <LocaleProvider locale={currentAppLocale.antd}>
    <IntlProvider
      locale={currentAppLocale.locale}
      messages={currentAppLocale.messages}
    >
      <ComposedComponent {...props} />
    </IntlProvider>
  </LocaleProvider>
);
