import { language } from '../../config/index';

const englishLang = '/static/image/flag/uk.svg';
const chineseLang = '/static/image/flag/china.svg';
const spanishLang = '/static/image/flag/spain.svg';
const frenchLang = '/static/image/flag/france.svg';
const italianLang = '/static/image/flag/italy.svg';
const config = {
  defaultLanguage: language,
  options: [
    {
      languageId: 'english',
      locale: 'en',
      text: 'English',
      icon: englishLang
    },
    {
      languageId: 'chinese',
      locale: 'zh',
      text: 'Chinese',
      icon: chineseLang
    },
    {
      languageId: 'spanish',
      locale: 'es',
      text: 'Spanish',
      icon: spanishLang
    },
    {
      languageId: 'french',
      locale: 'fr',
      text: 'French',
      icon: frenchLang
    },
    {
      languageId: 'italian',
      locale: 'it',
      text: 'Italian',
      icon: italianLang
    }
  ]
};

export function getCurrentLanguage(lang) {
  let selecetedLanguage = config.options[0];
  config.options.forEach(language => {
    if (language.languageId === lang) {
      selecetedLanguage = language;
    }
  });
  return selecetedLanguage;
}
export default config;
