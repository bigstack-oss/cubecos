import antdSA from 'antd/lib/locale-provider/ca_ES';
import appLocaleData from 'react-intl/locale-data/es';
import saMessages from '../locales/es_ES.json';

const saLang = {
  messages: {
    ...saMessages
  },
  antd: antdSA,
  locale: 'es',
  data: appLocaleData
};
export default saLang;
