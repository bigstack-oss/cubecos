import { themeConfig } from '../../config/index';
const changeThemes = {
  id: 'changeThemes',
  label: 'themeSwitcher',
  defaultTheme: themeConfig.theme,
  options: [
    {
      themeName: 'themedefault',
      buttonColor: '#ffffff',
      textColor: '#323332'
    },
    {
      themeName: 'theme2',
      buttonColor: '#ffffff',
      textColor: '#323332'
    }
  ]
};
const topbarTheme = {
  id: 'topbarTheme',
  label: 'themeSwitcher.Topbar',
  defaultTheme: themeConfig.topbar,
  options: [
    {
      themeName: 'themedefault',
      buttonColor: '#ffffff',
      textColor: '#323332'
    },
    {
      themeName: 'theme1',
      buttonColor: '#e0364c',
      backgroundColor: '#e0364c',
      textColor: '#ffffff'
    },
    {
      themeName: 'theme2',
      buttonColor: '#6534ff',
      backgroundColor: '#6534ff',
      textColor: '#ffffff'
    },
    {
      themeName: 'theme3',
      buttonColor: '#4482FF',
      backgroundColor: '#4482FF',
      textColor: '#ffffff'
    },
    {
      themeName: 'theme4',
      buttonColor: '#422e62',
      backgroundColor: '#422e62',
      textColor: '#ffffff'
    },
    {
      themeName: 'theme5',
      buttonColor: '#22144c',
      backgroundColor: '#22144c',
      textColor: '#ffffff'
    },
    {
      themeName: 'theme6',
      buttonColor: '#4670a2',
      backgroundColor: '#4670a2',
      textColor: '#ffffff'
    },
    {
      themeName: 'theme7',
      buttonColor: '#494982',
      backgroundColor: '#494982',
      textColor: '#ffffff'
    }
  ]
};
const sidebarTheme = {
  id: 'sidebarTheme',
  label: 'themeSwitcher.Sidebar',
  defaultTheme: themeConfig.sidebar,
  options: [
    {
      themeName: 'themedefault',
      buttonColor: '#323332',
      backgroundColor: undefined,
      textColor: '#788195'
    },
    {
      themeName: 'theme1',
      buttonColor: '#e0364c',
      backgroundColor: '#e0364c',
      textColor: '#ffffff'
    },
    {
      themeName: 'theme2',
      buttonColor: '#6534ff',
      backgroundColor: '#6534ff',
      textColor: '#ffffff'
    },
    {
      themeName: 'theme3',
      buttonColor: '#4482FF',
      backgroundColor: '#4482FF',
      textColor: '#ffffff'
    },
    {
      themeName: 'theme4',
      buttonColor: '#422e62',
      backgroundColor: '#422e62',
      textColor: '#ffffff'
    },
    {
      themeName: 'theme5',
      buttonColor: '#22144c',
      backgroundColor: '#22144c',
      textColor: '#ffffff'
    },
    {
      themeName: 'theme6',
      buttonColor: '#4670a2',
      backgroundColor: '#4670a2',
      textColor: '#ffffff'
    },
    {
      themeName: 'theme7',
      buttonColor: '#494982',
      backgroundColor: '#494982',
      textColor: '#ffffff'
    }
  ]
};
const layoutTheme = {
  id: 'layoutTheme',
  label: 'themeSwitcher.Background',
  defaultTheme: themeConfig.layout,
  options: [
    {
      themeName: 'themedefault',
      buttonColor: '#ffffff',
      backgroundColor: '#F1F3F6',
      textColor: undefined
    },
    {
      themeName: 'theme1',
      buttonColor: '#ffffff',
      backgroundColor: '#ffffff',
      textColor: '#323232'
    },
    {
      themeName: 'theme2',
      buttonColor: '#F9F9F9',
      backgroundColor: '#F9F9F9',
      textColor: '#ffffff'
    },
    {
      themeName: 'theme3',
      buttonColor: '#ebebeb',
      backgroundColor: '#ebebeb',
      textColor: '#ffffff'
    }
  ]
};
const customizedThemes = {
  changeThemes,
  topbarTheme,
  sidebarTheme,
  layoutTheme
};
export function getCurrentTheme(attribute, selectedThemename) {
  let selecetedTheme = {};
  customizedThemes[attribute].options.forEach(theme => {
    if (theme.themeName === selectedThemename) {
      selecetedTheme = theme;
    }
  });
  return selecetedTheme;
}
export default customizedThemes;
