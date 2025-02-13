import { getCurrentLanguage } from '../../containers/LanguageSwitcher/config';
const actions = {
  CHANGE_LANGUAGE: 'CHANGE_LANGUAGE',
  ACTIVATE_LANG_MODAL: 'ACTIVATE_LANG_MODAL',
  switchActivation: () => ({
    type: actions.ACTIVATE_LANG_MODAL
  }),
  changeLanguage: language => {
    return {
      type: actions.CHANGE_LANGUAGE,
      language: getCurrentLanguage(language)
    };
  }
};
export default actions;
