// reducer.js

import { combineReducers } from 'redux';

// import shared modules
import App from '../redux/app/reducer';
import LanguageSwitcher from '../redux/languageSwitcher/reducer';
import ThemeSwitcher from '../redux/themeSwitcher/reducer';

// import cube app modules
import basic from './basic';
import dashboard from './dashboard';
import logs from './logs';
import mgmt from './mgmt';

export default combineReducers({
  App,
  LanguageSwitcher,
  ThemeSwitcher,
  [basic.constant.NAME]: basic.reducer,
  [dashboard.constant.NAME]: dashboard.reducer,
  [logs.constant.NAME]: logs.reducer,
  [mgmt.constant.NAME]: mgmt.reducer,
});