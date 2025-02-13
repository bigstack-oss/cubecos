import React, { Component } from "react";
import { connect } from "react-redux";
import { Layout } from "antd";
import appActions from "../../redux/app/actions";
import TopbarNotification from "./topbarNotification";
import TopbarUser from "./topbarUser";
import TopbarCluster from "./topbarCluster";
import TopbarWrapper from "./topbar.style";

import basic from '../../app/basic';

const { Header } = Layout;
const { toggleCollapsed } = appActions;

class Topbar extends Component {
  render() {
    const { toggleCollapsed, url, customizedTheme, locale, role } = this.props;
    const collapsed = this.props.collapsed && !this.props.openDrawer;
    const styling = {
      background: customizedTheme.backgroundColor,
      position: "fixed",
      width: "100%",
      height: 70
    };
    return (
      <TopbarWrapper>
        <Header
          style={styling}
          className={
            collapsed ? "isomorphicTopbar collapsed" : "isomorphicTopbar"
          }
        >
          <div className="isoLeft">
            <button
              className={
                collapsed ? "triggerBtn menuCollapsed" : "triggerBtn menuOpen"
              }
              style={{ color: customizedTheme.textColor }}
              onClick={toggleCollapsed}
            />
          </div>
          <div className="isoLeft">
            <TopbarCluster style={{ margin: '32px 32px 32px 32px' }} locale={locale} />
          </div>
          <ul className="isoRight">
            {role == 'admin' &&
              <li onClick={() => this.setState({ selectedItem: "notification" })} className="isoNotify" >
                <TopbarNotification locale={locale} />
              </li>
            }
            <li onClick={() => this.setState({ selectedItem: "user" })} className="isoUser" >
              <TopbarUser locale={locale} />
            </li>
          </ul>
        </Header>
      </TopbarWrapper>
    );
  }
}

export default connect(
  state => ({
    ...state.App,
    locale: state.LanguageSwitcher.language.locale,
    customizedTheme: state.ThemeSwitcher.topbarTheme,
    role: state[basic.constant.NAME].userInfo.role,
  }),
  { toggleCollapsed }
)(Topbar);
