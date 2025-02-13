import React, { Component } from 'react';
import { connect } from 'react-redux';
import clone from 'clone';
import Link from 'next/link';
import { Layout } from 'antd';
import { Scrollbars } from 'react-custom-scrollbars';
import Menu from '../../components/uielements/menu';
import IntlMessages from '../../components/utility/intlMessages';
import SidebarWrapper from './sidebar.style';

import appActions from '../../redux/app/actions';
import Logo from '../../components/utility/logo';
import { rtl } from '../../config/withDirection';
import { siteConfig } from '../../config';

const { Sider } = Layout;
const {
  toggleOpenDrawer,
  changeOpenKeys,
  changeCurrent,
  toggleCollapsed,
} = appActions;

class SidebarUser extends Component {
  constructor(props) {
    super(props);
    this.handleClick = this.handleClick.bind(this);
    this.onOpenChange = this.onOpenChange.bind(this);
  }
  handleClick(e) {
    this.props.changeCurrent([e.key]);
    if (this.props.app.view === 'MobileView') {
      setTimeout(() => {
        this.props.toggleCollapsed();
        this.props.toggleOpenDrawer();
      }, 100);
    }
  }
  onOpenChange(newOpenKeys) {
    const { app, changeOpenKeys } = this.props;
    const latestOpenKey = newOpenKeys.find(
      key => !(app.openKeys.indexOf(key) > -1)
    );
    const latestCloseKey = app.openKeys.find(
      key => !(newOpenKeys.indexOf(key) > -1)
    );
    let nextOpenKeys = [];
    if (latestOpenKey) {
      nextOpenKeys = this.getAncestorKeys(latestOpenKey).concat(latestOpenKey);
    }
    if (latestCloseKey) {
      nextOpenKeys = this.getAncestorKeys(latestCloseKey);
    }
    changeOpenKeys(nextOpenKeys);
  }
  getAncestorKeys = key => {
    const map = {
      sub3: ['sub2'],
    };
    return map[key] || [];
  };

  renderView({ style, ...props }) {
    const viewStyle = {
      marginRight: rtl === 'rtl' ? '0' : '-17px',
      paddingRight: rtl === 'rtl' ? '0' : '9px',
      marginLeft: rtl === 'rtl' ? '-17px' : '0',
      paddingLeft: rtl === 'rtl' ? '9px' : '0',
    };
    return (
      <div className='box' style={{ ...style, ...viewStyle }} {...props} />
    );
  }

  render() {
    const { app, toggleOpenDrawer, customizedTheme, groups } = this.props;
    const collapsed = clone(app.collapsed) && !clone(app.openDrawer);
    const { openDrawer } = app;
    const mode = collapsed === true ? 'vertical' : 'inline';
    const onMouseEnter = event => {
      if (openDrawer === false) {
        toggleOpenDrawer();
      }
      return;
    };
    const onMouseLeave = () => {
      if (openDrawer === true) {
        toggleOpenDrawer();
      }
      return;
    };
    const scrollheight = app.height;
    const styling = {
      backgroundColor: customizedTheme.backgroundColor,
    };
    const submenuStyle = {
      backgroundColor: 'rgba(0,0,0,0.3)',
      color: customizedTheme.textColor,
    };
    const submenuColor = {
      color: customizedTheme.textColor,
    };

    let g = [ 'all' ];
    if (groups) {
      if (typeof groups == 'string')
        g.push(groups);
      else
        g.concat(groups);
    }

    let apps = [];
    for (var i = 0; i < g.length; i++) {
      const items = window.app[g[i]];
      if (!items)
        continue;

      for (var j = 0; j < items.length; j++) {
        let found = false;
        for (var k = 0; k < apps.length; k++) {
          if (apps[k].NAME == items[j].NAME) {
            found = true;
            break;
          }
        }
        if (!found)
          apps.push(items[j]);
      }
    }

    return (
      <SidebarWrapper>
        <Sider
          trigger={null}
          collapsible={true}
          collapsed={collapsed}
          width={240}
          className='isomorphicSidebar'
          onMouseEnter={onMouseEnter}
          onMouseLeave={onMouseLeave}
          style={styling}
        >
          <Logo collapsed={collapsed} />
          <Scrollbars style={{ height: scrollheight - 70 }}>
            <Menu
              onClick={this.handleClick}
              theme='dark'
              mode={mode}
              openKeys={collapsed ? [] : (app.openKeys != [] ? app.openKeys : ['logs'])}
              selectedKeys={app.current != [] ? app.current : ['log-alerts']}
              onOpenChange={this.onOpenChange}
              className='isoDashboardMenu'
            >
              <Menu.Item key='account'>
                <a href={
                    window.cluster[window.env.CLUSTER].IAM_USER_URL ?
                    window.cluster[window.env.CLUSTER].IAM_USER_URL :
                    `https://${window.cluster[window.env.CLUSTER].CUBE_URL}:10443/auth/realms/master/account/sessions`
                  } target='_blank'>
                  <span className='isoMenuHolder' style={submenuColor}>
                    <i className='ti-user' />
                    <span className='nav-text'>
                      <IntlMessages id='sidebar.account' />
                    </span>
                  </span>
                </a>
              </Menu.Item>
              <Menu.Item key="app">
                <Link href={`/dashboard/application`}>
                  <span className="isoMenuHolder" style={submenuColor}>
                  <i className='ti-layout-tab' />
                    <span className="nav-text">
                      <IntlMessages id="sidebar.dashboard.app" />
                    </span>
                  </span>
                </Link>
              </Menu.Item>
              <Menu.Item key="images">
                <Link href={`/dashboard/images`}>
                  <span className="isoMenuHolder" style={submenuColor}>
                  <i className='ti-files' />
                    <span className="nav-text">
                      <IntlMessages id="sidebar.dashboard.images" />
                    </span>
                  </span>
                </Link>
              </Menu.Item>
              <Menu.Item key="exports">
                <Link href={`/dashboard/exports`}>
                  <span className="isoMenuHolder" style={submenuColor}>
                  <i className='ti-export' />
                    <span className="nav-text">
                      <IntlMessages id="sidebar.dashboard.exports" />
                    </span>
                  </span>
                </Link>
              </Menu.Item>
            </Menu>
          </Scrollbars>
        </Sider>
      </SidebarWrapper>
    );
  }
}

export default connect(
  state => ({
    app: state.App,
    customizedTheme: state.ThemeSwitcher.sidebarTheme,
    groups: state['basic'].userInfo.groups,
  }),
  { toggleOpenDrawer, changeOpenKeys, changeCurrent, toggleCollapsed }
)(SidebarUser);
