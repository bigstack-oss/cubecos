import { getCurrentTheme } from '../../containers/ThemeSwitcher/config';
const actions = {
  CHANGE_THEME: 'CHANGE_THEME',
  SWITCH_ACTIVATION: 'SWITCH_ACTIVATION',
  switchActivation: () => ({
    type: actions.SWITCH_ACTIVATION
  }),
  changeTheme: (attribute, themeName) => {
    const theme = getCurrentTheme(attribute, themeName);
    if (attribute === 'layoutTheme') {
      document.getElementsByClassName(
        'isomorphicContent'
      )[0].style.backgroundColor =
        theme.backgroundColor;
    }
    return {
      type: actions.CHANGE_THEME,
      attribute,
      theme
    };
  }
};
export default actions;
