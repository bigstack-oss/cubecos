import React, { Component } from "react";
import { Popover, Avatar } from "antd";
import { connect } from "react-redux";
import TopbarDropdownWrapper from "./topbarDropdown.style";
import Link from 'next/link';
import IntlMessages from '../../components/utility/intlMessages';

import basic from '../../app/basic';
import logs from '../../app/logs';
import mgmt from '../../app/mgmt';

const fetchAlertSummary = logs.action.fetchAlertSummary;
const fetchLicenseStatus = mgmt.action.fetchLicenseStatus;

const COLORS = {
  crit: '#E42B56',
  warn: '#ffbf00',
  info: '#39C783',
}

const STYLES = {
  crit: { backgroundColor: COLORS.crit, verticalAlign: 'middle', margin: '0px 12px' },
  warn: { backgroundColor: COLORS.warn, verticalAlign: 'middle', margin: '0px 12px' },
  info: { backgroundColor: COLORS.info, verticalAlign: 'middle', margin: '0px 12px' },
}

const getColor = (summary, def) => {
  if (summary.system.crit + summary.host.crit + summary.instance.crit)
    return COLORS.crit;
  if (summary.system.warn + summary.host.warn + summary.instance.warn)
    return COLORS.warn;
  if (summary.system.info + summary.host.info + summary.instance.info)
    return COLORS.info;
  else
    return def;
}

const getCrit = (summary) => {
  return summary.system.crit + summary.host.crit + summary.instance.crit
}

const getDate = (summary) => {
  if (summary.date) {
    const d = new Date(summary.date * 1000);
    return 'Since ' + d.toLocaleString();
  }
}

class TopbarNotification extends Component {
  constructor(props) {
    super(props);
    this.handleVisibleChange = this.handleVisibleChange.bind(this);
    this.hide = this.hide.bind(this);
    this.state = {
      refresh: true,
      visible: false,
      licenseNotice: true,
    };
  }
  componentDidMount() {
    this.interval = setInterval(() => this.setState({ refresh: true }), logs.constant.REFRESH * 3);
  }
  componentWillUnmount() {
    clearInterval(this.interval);
  }
  hide() {
    this.setState({ visible: false });
  }
  handleVisibleChange() {
    this.setState({ visible: !this.state.visible });
  }
  render() {
    const { customizedTheme, summary, license, fetchAlertSummary, fetchLicenseStatus } = this.props;
    const crit = getCrit(summary);

    if (this.state.refresh) {
      fetchAlertSummary();
      this.setState({ refresh: false });
    }
    if (this.state.licenseNotice) {
      fetchLicenseStatus(license);
      this.setState({ licenseNotice: false });
    }

    const content = (
      <TopbarDropdownWrapper className="topbarNotification">
        <div className="isoDropdownHeader">
          <h3><IntlMessages id='topbar.alerts.title' /></h3>
          <h5>{getDate(summary)}</h5>
        </div>
        <div className="isoDropdownBody">
          {summary.system &&
            <a className="isoDropdownListItem" key={0}>
              <h5>System Events</h5>
              <div>
                <Avatar style={STYLES.crit} >{summary.system.crit}</Avatar>
                <Avatar style={STYLES.warn} >{summary.system.warn}</Avatar>
                <Avatar style={STYLES.info} >{summary.system.info}</Avatar>
              </div>
            </a>
          }
          {summary.host &&
            <a className="isoDropdownListItem" key={1}>
              <h5>Host Alerts</h5>
              <div>
                <Avatar style={STYLES.crit} >{summary.host.crit}</Avatar>
                <Avatar style={STYLES.warn} >{summary.host.warn}</Avatar>
                <Avatar style={STYLES.info} >{summary.host.info}</Avatar>
              </div>
            </a>
          }
          {summary.instance &&
            <a className="isoDropdownListItem" key={2}>
              <h5>Instance Alerts</h5>
              <div>
                <Avatar style={STYLES.crit} >{summary.instance.crit}</Avatar>
                <Avatar style={STYLES.warn} >{summary.instance.warn}</Avatar>
                <Avatar style={STYLES.info} >{summary.instance.info}</Avatar>
              </div>
            </a>
          }
        </div>
        <Link href={`/logs/alert`}>
          <a className="isoViewAllBtn"><IntlMessages id='topbar.alerts.view' /></a>
        </Link>
      </TopbarDropdownWrapper>
    );

    return (
      <Popover
        content={content}
        trigger="click"
        visible={this.state.visible}
        onVisibleChange={this.handleVisibleChange}
        placement="bottomLeft"
      >
        <div className="isoIconWrapper">
          <i className="ion-android-notifications" style={{ color: getColor(summary, customizedTheme.textColor) }} />
          {crit > 0 && <span>{crit}</span>}
        </div>
      </Popover>
    );
  }
}

const mapStateToProps = (state, ownProps) => {
  return {
    customizedTheme: state.ThemeSwitcher.topbarTheme,
    summary: state[logs.constant.NAME].summary,
    license: state[mgmt.constant.NAME].license,
  };
};

export default connect(mapStateToProps, { fetchAlertSummary, fetchLicenseStatus })(TopbarNotification);
