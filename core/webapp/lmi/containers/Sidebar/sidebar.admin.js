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

const SubMenu = Menu.SubMenu;
const MenuItemGroup = Menu.ItemGroup;
const { Sider } = Layout;
const {
  toggleOpenDrawer,
  changeOpenKeys,
  changeCurrent,
  toggleCollapsed,
} = appActions;

class SidebarAdmin extends Component {
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
              openKeys={collapsed ? [] : app.openKeys}
              selectedKeys={app.current != [] ? app.current : ['dashboard']}
              onOpenChange={this.onOpenChange}
              className='isoDashboardMenu'
            >
              <Menu.Item key='dashboard'>
                <Link href={`/dashboard`}>
                  <span className='isoMenuHolder' style={submenuColor}>
                    <i className='ti-dashboard' />
                    <span className='nav-text'>
                      <IntlMessages id='sidebar.dashboard' />
                    </span>
                  </span>
                </Link>
              </Menu.Item>
              <Menu.Item key='iam'>
                <a href={
                    window.cluster[window.env.CLUSTER].IAM_ADMIN_URL ?
                    window.cluster[window.env.CLUSTER].IAM_ADMIN_URL :
                    `https://${window.cluster[window.env.CLUSTER].CUBE_URL}:10443/auth/admin/`
                  } target='_blank'>
                  <span className='isoMenuHolder' style={submenuColor}>
                    <i className='ti-key' />
                    <span className='nav-text'>
                      <IntlMessages id='sidebar.iam' />
                    </span>
                  </span>
                </a>
              </Menu.Item>
              {apps.length &&
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
              }
              <Menu.Item key='openstack'>
                <a href={
                    window.cluster[window.env.CLUSTER].IAAS_URL ?
                    window.cluster[window.env.CLUSTER].IAAS_URL :
                    `http://${window.cluster[window.env.CLUSTER].CUBE_URL}/horizon`
                  } target='_blank'>
                  <span className='isoMenuHolder' style={submenuColor}>
                    <i className='ti-harddrives' />
                    <span className='nav-text'>
                      <IntlMessages id='sidebar.infra' />
                    </span>
                  </span>
                </a>
              </Menu.Item>
              {window.env.RANCHER && !window.env.EDGE_CORE &&
                <Menu.Item key='kubernetes'>
                  <a href={
                    window.cluster[window.env.CLUSTER].K8S_URL ?
                    window.cluster[window.env.CLUSTER].K8S_URL :
                    `https://${window.cluster[window.env.CLUSTER].CUBE_URL}:10443`
                  } target='_blank'>
                    <span className='isoMenuHolder' style={submenuColor}>
                      <i className='ti-layout-grid2' />
                      <span className='nav-text'>
                        <IntlMessages id='sidebar.kubernetes' />
                      </span>
                    </span>
                  </a>
                </Menu.Item>
              }
              <Menu.Item key='storage'>
                <a href={
                    window.cluster[window.env.CLUSTER].STORAGE_URL ?
                    window.cluster[window.env.CLUSTER].STORAGE_URL :
                    `https://${window.cluster[window.env.CLUSTER].CUBE_URL}/ceph/`
                  } target='_blank'>
                  <span className='isoMenuHolder' style={submenuColor}>
                    <i className='ti-server' />
                    <span className='nav-text'>
                      <IntlMessages id='sidebar.storage' />
                    </span>
                  </span>
                </a>
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
              <SubMenu
                key="monitor"
                title={
                  <span className="isoMenuHolder" style={submenuColor}>
                    <i className="ti-bar-chart" />
                    <span className="nav-text">
                      <IntlMessages id="sidebar.monitor" />
                    </span>
                  </span>
                }
              >
                <Menu.Item style={submenuStyle} key='mon-host'>
                  <Link href={`/monitoring/host`}>
                    <span className='isoMenuHolder' style={submenuColor}>
                      <span className='nav-text'>
                        <IntlMessages id='sidebar.host' />
                      </span>
                    </span>
                  </Link>
                </Menu.Item>
                <Menu.Item style={submenuStyle} key='mon-storage'>
                  <Link href={`/monitoring/storage`}>
                    <span className='isoMenuHolder' style={submenuColor}>
                      <span className='nav-text'>
                        <IntlMessages id='sidebar.storage' />
                      </span>
                    </span>
                  </Link>
                </Menu.Item>
                <Menu.Item style={submenuStyle} key='mon-network'>
                  <Link href={`/monitoring/network`}>
                    <span className='isoMenuHolder' style={submenuColor}>
                      <span className='nav-text'>
                        <IntlMessages id='sidebar.network' />
                      </span>
                    </span>
                  </Link>
                </Menu.Item>
                <Menu.Item style={submenuStyle} key='mon-instance'>
                  <Link href={`/monitoring/instance`}>
                    <span className='isoMenuHolder' style={submenuColor}>
                      <span className='nav-text'>
                        <IntlMessages id='sidebar.instance' />
                      </span>
                    </span>
                  </Link>
                </Menu.Item>
                <Menu.Item style={submenuStyle} key='mon-device'>
                  <Link href={`/monitoring/device`}>
                    <span className='isoMenuHolder' style={submenuColor}>
                      <span className='nav-text'>
                        <IntlMessages id='sidebar.device' />
                      </span>
                    </span>
                  </Link>
                </Menu.Item>
                <Menu.Item style={submenuStyle} key='mon-host-top'>
                  <Link href={`/monitoring/top_host`}>
                    <span className='isoMenuHolder' style={submenuColor}>
                      <span className='nav-text'>
                        <IntlMessages id='sidebar.host.top' />
                      </span>
                    </span>
                  </Link>
                </Menu.Item>
                <Menu.Item style={submenuStyle} key='mon-instance-top'>
                  <Link href={`/monitoring/top_instance`}>
                    <span className='isoMenuHolder' style={submenuColor}>
                      <span className='nav-text'>
                        <IntlMessages id='sidebar.instance.top' />
                      </span>
                    </span>
                  </Link>
                </Menu.Item>
                <Menu.Item style={submenuStyle} key='mon-device-top'>
                  <Link href={`/monitoring/top_device`}>
                    <span className='isoMenuHolder' style={submenuColor}>
                      <span className='nav-text'>
                        <IntlMessages id='sidebar.device.top' />
                      </span>
                    </span>
                  </Link>
                </Menu.Item>
              </SubMenu>
              <SubMenu
                key="logs"
                title={
                  <span className="isoMenuHolder" style={submenuColor}>
                    <i className="ti-write" />
                    <span className="nav-text">
                      <IntlMessages id="sidebar.logs" />
                    </span>
                  </span>
                }
              >
                <Menu.Item style={submenuStyle} key="logs-alert">
                  <Link href={`/logs/alert`}>
                    <span className="isoMenuHolder" style={submenuColor}>
                      <span className="nav-text">
                        <IntlMessages id="sidebar.logs.alert" />
                      </span>
                    </span>
                  </Link>
                </Menu.Item>
                <Menu.Item style={submenuStyle} key="logs-notification">
                  <Link href={`/logs/notification`}>
                    <span className="isoMenuHolder" style={submenuColor}>
                      <span className="nav-text">
                        <IntlMessages id="sidebar.logs.notification" />
                      </span>
                    </span>
                  </Link>
                </Menu.Item>
                {!window.env.EDGE_CORE &&
                <Menu.Item style={submenuStyle} key="logs-analytic">
                  <Link href={`/logs/analytic`}>
                    <span className="isoMenuHolder" style={submenuColor}>
                      <span className="nav-text">
                        <IntlMessages id="sidebar.logs.analytic" />
                      </span>
                    </span>
                  </Link>
                </Menu.Item>
                }
              </SubMenu>
              <SubMenu
                key="manage"
                title={
                  <span className="isoMenuHolder" style={submenuColor}>
                    <i className="ti-settings" />
                    <span className="nav-text">
                      <IntlMessages id="sidebar.manage" />
                    </span>
                  </span>
                }
              >
                <Menu.Item style={submenuStyle} key="manage-health">
                  <Link href={`/manage/cluster-health`}>
                    <span className="isoMenuHolder" style={submenuColor}>
                      <span className="nav-text">
                        <IntlMessages id="sidebar.manage.health" />
                      </span>
                    </span>
                  </Link>
                </Menu.Item>
                <Menu.Item style={submenuStyle} key="manage-cluster">
                  <Link href={`/manage/cluster-nodes`}>
                    <span className="isoMenuHolder" style={submenuColor}>
                      <span className="nav-text">
                        <IntlMessages id="sidebar.manage.cluster" />
                      </span>
                    </span>
                  </Link>
                </Menu.Item>
              </SubMenu>
              <Menu.Item key='skyline'>
                <a href={
                    window.cluster[window.env.CLUSTER].IAAS_URL ?
                    window.cluster[window.env.CLUSTER].IAAS_URL :
                    `https://${window.cluster[window.env.CLUSTER].CUBE_URL}:9999`
                  } target='_blank'>
                  <span className='isoMenuHolder' style={submenuColor}>
                    <i className='ti-cloud' />
                    <span className='nav-text'>
                      <IntlMessages id='sidebar.skyline' />
                    </span>
                  </span>
                </a>
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
)(SidebarAdmin);