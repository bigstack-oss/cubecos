import antdSA from 'antd/lib/locale-provider/fr_FR';
import appLocaleData from 'react-intl/locale-data/fr';
import saMessages from '../locales/fr_FR.json';

const saLang = {
  messages: {
    ...saMessages
  },
  antd: antdSA,
  locale: 'fr-FR',
  data: appLocaleData
};
export default saLang;
